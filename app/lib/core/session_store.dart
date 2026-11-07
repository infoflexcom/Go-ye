import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

abstract class SessionStore {
  Future<Session?> readSession();
  Future<void> writeSession(Session session);
  Future<void> clearSession();
  Future<String> deviceIdentifier();
}

/// Stores only opaque session material in the OS keystore/keychain. It never
/// falls back to SharedPreferences or a file because refresh tokens are secrets.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _sessionKey = 'goye.session.v1';
  static const String _deviceKey = 'goye.device-id.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<void> clearSession() => _storage.delete(key: _sessionKey);

  @override
  Future<String> deviceIdentifier() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final random = Random.secure();
    final generated = List<String>.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
      growable: false,
    ).join();
    await _storage.write(key: _deviceKey, value: generated);
    return generated;
  }

  @override
  Future<Session?> readSession() async {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return Session.fromJson(objectFromJson(encoded));
    } on FormatException {
      await clearSession();
      return null;
    }
  }

  @override
  Future<void> writeSession(Session session) {
    return _storage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
  }
}

class MemorySessionStore implements SessionStore {
  Session? session;
  String _deviceId = 'test-device-identifier';

  @override
  Future<void> clearSession() async {
    session = null;
  }

  @override
  Future<String> deviceIdentifier() async => _deviceId;

  @override
  Future<Session?> readSession() async => session;

  @override
  Future<void> writeSession(Session newSession) async {
    session = newSession;
  }

  void setDeviceIdentifier(String value) {
    _deviceId = value;
  }
}
