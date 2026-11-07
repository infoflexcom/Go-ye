import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goye/core/api_client.dart';
import 'package:goye/core/session_store.dart';
import 'package:goye/features/auth/auth_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'requests an OTP, verifies it and stores only a secure session',
    () async {
      final store = MemorySessionStore();
      final client = ApiClient(
        baseUrl: 'https://goye.test/api/v1/',
        sessionStore: store,
        httpClient: MockClient((http.Request request) async {
          expect(request.url.path, startsWith('/api/v1/auth/otp/'));
          if (request.url.path.endsWith('/request')) {
            expect(jsonDecode(request.body), <String, Object?>{
              'identity': '+2348030000044',
              'deviceIdentifier': 'test-device-identifier',
            });
            return http.Response('{"accepted":true}', 202);
          }
          if (request.url.path.endsWith('/verify')) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'accessToken': _jwt(<String, Object?>{
                  'sub': 'user-1',
                  'roles': <String>['AREA_LEADER'],
                  'homePath': 'n1.n2',
                }),
                'refreshToken': 'not-logged-or-rendered',
                'accessTokenExpiresInSeconds': 900,
                'refreshTokenExpiresInSeconds': 2592000,
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final controller = AuthController(api: client, sessionStore: store);
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, AuthStatus.signedOut);

      await controller.requestCode('+2348030000044');
      expect(controller.state.status, AuthStatus.awaitingCode);
      expect(controller.state.identity, '+2348030000044');

      await controller.verifyCode('123456');
      expect(controller.state.status, AuthStatus.signedIn);
      expect(store.session?.userId, 'user-1');
      expect(store.session?.roles, <String>{'AREA_LEADER'});

      await controller.signOut();
      expect(store.session, isNull);
    },
  );
}

String _jwt(Map<String, Object?> claims) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.${encode(claims)}.signature';
}
