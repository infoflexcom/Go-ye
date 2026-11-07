import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_providers.dart';
import '../../core/models.dart';
import '../../core/session_store.dart';

enum AuthStatus { restoring, signedOut, awaitingCode, submitting, signedIn }

class AuthState {
  const AuthState({
    required this.status,
    this.identity,
    this.session,
    this.message,
  });

  const AuthState.restoring() : this(status: AuthStatus.restoring);

  final AuthStatus status;
  final String? identity;
  final Session? session;
  final String? message;

  AuthState copyWith({
    AuthStatus? status,
    String? identity,
    Session? session,
    String? message,
    bool clearMessage = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      identity: identity ?? this.identity,
      session: session ?? this.session,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({required ApiClient api, required SessionStore sessionStore})
    : _api = api,
      _sessionStore = sessionStore,
      super(const AuthState.restoring()) {
    unawaited(_restore());
  }

  final ApiClient _api;
  final SessionStore _sessionStore;

  Future<void> _restore() async {
    try {
      final session = await _sessionStore.readSession();
      state = session == null
          ? const AuthState(status: AuthStatus.signedOut)
          : AuthState(status: AuthStatus.signedIn, session: session);
    } on Object {
      await _sessionStore.clearSession();
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  Future<void> requestCode(String identity) async {
    final normalised = identity.trim();
    if (normalised.isEmpty) {
      state = const AuthState(
        status: AuthStatus.signedOut,
        message: 'Enter your approved phone number or email address.',
      );
      return;
    }
    state = AuthState(status: AuthStatus.submitting, identity: normalised);
    try {
      await _api.postPublic('auth/otp/request', <String, Object?>{
        'identity': normalised,
        'deviceIdentifier': await _sessionStore.deviceIdentifier(),
      });
      state = AuthState(status: AuthStatus.awaitingCode, identity: normalised);
    } on ApiException catch (error) {
      state = AuthState(status: AuthStatus.signedOut, message: error.message);
    } on Object {
      state = const AuthState(
        status: AuthStatus.signedOut,
        message:
            'Unable to reach Go-Ye. Check the server connection and try again.',
      );
    }
  }

  Future<void> verifyCode(String code) async {
    final identity = state.identity;
    if (identity == null || identity.isEmpty) {
      state = const AuthState(status: AuthStatus.signedOut);
      return;
    }
    final normalisedCode = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalisedCode)) {
      state = AuthState(
        status: AuthStatus.awaitingCode,
        identity: identity,
        message: 'Enter the six-digit code.',
      );
      return;
    }
    state = AuthState(status: AuthStatus.submitting, identity: identity);
    try {
      final result = await _api.postPublic('auth/otp/verify', <String, Object?>{
        'identity': identity,
        'code': normalisedCode,
        'deviceIdentifier': await _sessionStore.deviceIdentifier(),
        'platform': _platformName(),
        'deviceLabel': _deviceLabel(),
      });
      final session = Session.fromApi(result);
      await _sessionStore.writeSession(session);
      state = AuthState(status: AuthStatus.signedIn, session: session);
    } on ApiException catch (error) {
      state = AuthState(
        status: AuthStatus.awaitingCode,
        identity: identity,
        message: error.message,
      );
    } on Object {
      state = AuthState(
        status: AuthStatus.awaitingCode,
        identity: identity,
        message: 'Unable to complete sign-in. Please try again.',
      );
    }
  }

  Future<void> signOut() async {
    await _sessionStore.clearSession();
    state = const AuthState(status: AuthStatus.signedOut);
  }

  String _platformName() {
    if (Platform.isAndroid) {
      return 'ANDROID';
    }
    if (Platform.isIOS) {
      return 'IOS';
    }
    if (Platform.isWindows) {
      return 'WINDOWS';
    }
    return 'UNKNOWN';
  }

  String _deviceLabel() {
    if (Platform.isWindows) {
      return 'Windows desktop';
    }
    if (Platform.isAndroid) {
      return 'Android device';
    }
    if (Platform.isIOS) {
      return 'iOS device';
    }
    return 'Go-Ye client';
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (Ref ref) {
    return AuthController(
      api: ref.watch(apiClientProvider),
      sessionStore: ref.watch(sessionStoreProvider),
    );
  },
);
