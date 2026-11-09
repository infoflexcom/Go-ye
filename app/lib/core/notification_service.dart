import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/follow_up/follow_up_repository.dart';
import 'models.dart';

const bool fcmPushEnabled =
    bool.fromEnvironment('FCM_ENABLED', defaultValue: false);
const FirebaseOptions _firebaseOptions = FirebaseOptions(
  apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
  appId: String.fromEnvironment('FIREBASE_APP_ID'),
  messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
  projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
);
const String _localReminderStoreKey = 'follow-up-local-reminder-ids-v1';

/// Shows generic, non-PII reminders. Android receives FCM while Windows turns
/// the synced Today list into a local toast. The task ID is stable so retries
/// replace an existing platform notification instead of adding another one.
class DeviceNotificationService {
  DeviceNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    FlutterSecureStorage? storage,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _storage = storage ?? const FlutterSecureStorage();

  final FlutterLocalNotificationsPlugin _plugin;
  final FlutterSecureStorage _storage;
  final Set<String> _shownInProcess = <String>{};
  var _initialised = false;

  Future<void> initialize() async {
    if (_initialised || (!Platform.isAndroid && !Platform.isWindows)) {
      return;
    }
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'RCCG Go-Ye',
          appUserModelId: 'org.rccg.goye',
          guid: '9d85f872-c434-4c7e-9c2a-41c9a8d99313',
        ),
      );
      await _plugin.initialize(settings);
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            'goye_follow_up',
            'Follow-up reminders',
            description: 'Reminders for due convert follow-up tasks.',
            importance: Importance.high,
          ),
        );
        await android?.requestNotificationsPermission();
      }
      _initialised = true;
    } catch (_) {
      // A platform notification service may be disabled. Follow-up remains
      // available in the server-backed Today list.
    }
  }

  Future<void> syncWindowsTodayTasks(List<FollowUpTask> tasks) async {
    if (!Platform.isWindows) {
      return;
    }
    for (final task in tasks) {
      await showFollowUpReminder(task.id);
    }
  }

  Future<void> showFollowUpReminder(String taskId) async {
    if (await _hasBeenShown(taskId)) {
      return;
    }
    await initialize();
    if (!_initialised) {
      return;
    }
    try {
      await _plugin.show(
        _notificationId(taskId),
        'Follow-up due',
        'Open Go-Ye to record the outcome.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'goye_follow_up',
            'Follow-up reminders',
            channelDescription: 'Reminders for due convert follow-up tasks.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
        payload: taskId,
      );
      await _rememberShown(taskId);
    } catch (_) {
      // Do not expose a native notification failure to a pastoral workflow.
    }
  }

  Future<bool> _hasBeenShown(String taskId) async {
    if (_shownInProcess.contains(taskId)) {
      return true;
    }
    try {
      final raw = await _storage.read(key: _localReminderStoreKey);
      if (raw == null) {
        return false;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return false;
      }
      final shown = decoded.whereType<String>().toSet();
      _shownInProcess.addAll(shown);
      return shown.contains(taskId);
    } catch (_) {
      return false;
    }
  }

  Future<void> _rememberShown(String taskId) async {
    _shownInProcess.add(taskId);
    try {
      final stored = await _storage.read(key: _localReminderStoreKey);
      final decoded = stored == null ? null : jsonDecode(stored);
      final ids =
          decoded is List ? decoded.whereType<String>().toList() : <String>[];
      ids.remove(taskId);
      ids.add(taskId);
      final retained = ids.length <= 250 ? ids : ids.sublist(ids.length - 250);
      await _storage.write(
        key: _localReminderStoreKey,
        value: jsonEncode(retained),
      );
    } catch (_) {
      // In-memory de-duplication still protects the current app session.
    }
  }

  int _notificationId(String taskId) {
    var hash = 0x811c9dc5;
    for (final unit in taskId.codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0x7fffffff;
    }
    return hash;
  }
}

bool _hasFirebaseOptions() {
  return _firebaseOptions.apiKey.isNotEmpty &&
      _firebaseOptions.appId.isNotEmpty &&
      _firebaseOptions.messagingSenderId.isNotEmpty &&
      _firebaseOptions.projectId.isNotEmpty;
}

class PushNotificationRegistration {
  PushNotificationRegistration({
    required FollowUpRepository repository,
    required DeviceNotificationService notifications,
  })  : _repository = repository,
        _notifications = notifications;

  final FollowUpRepository _repository;
  final DeviceNotificationService _notifications;
  var _started = false;

  Future<void> registerAndroidDevice() async {
    if (_started || !fcmPushEnabled || !Platform.isAndroid) {
      return;
    }
    _started = true;
    if (!_hasFirebaseOptions()) {
      return;
    }
    try {
      await Firebase.initializeApp(options: _firebaseOptions);
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _repository.registerPushToken(token);
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((String refreshedToken) {
        unawaited(
          _repository
              .registerPushToken(refreshedToken)
              .catchError((Object _) {}),
        );
      });
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final taskId = message.data['followUpTaskId'];
        if (taskId is String && taskId.isNotEmpty) {
          unawaited(_notifications.showFollowUpReminder(taskId));
        }
      });
    } catch (_) {
      // Firebase needs church-provided native configuration. It stays optional
      // until that configuration is present; the Today list remains usable.
    }
  }
}
