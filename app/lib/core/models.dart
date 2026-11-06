import 'dart:convert';

/// A short-lived session returned by the Go-Ye API. Refresh tokens are kept in
/// platform secure storage only and must never be logged or added to analytics.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresInSeconds,
    required this.refreshTokenExpiresInSeconds,
    required this.userId,
    required this.roles,
    required this.homePath,
  });

  final String accessToken;
  final String refreshToken;
  final int accessTokenExpiresInSeconds;
  final int refreshTokenExpiresInSeconds;
  final String userId;
  final Set<String> roles;
  final String? homePath;

  bool get isGlobalAdmin => roles.contains('GLOBAL_ADMIN');

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'accessTokenExpiresInSeconds': accessTokenExpiresInSeconds,
      'refreshTokenExpiresInSeconds': refreshTokenExpiresInSeconds,
      'userId': userId,
      'roles': roles.toList(growable: false),
      'homePath': homePath,
    };
  }

  static Session fromApi(Map<String, Object?> response) {
    final claims = _jwtClaims(_requiredString(response, 'accessToken'));
    final rawRoles = claims['roles'];
    return Session(
      accessToken: _requiredString(response, 'accessToken'),
      refreshToken: _requiredString(response, 'refreshToken'),
      accessTokenExpiresInSeconds: _requiredInt(response, 'accessTokenExpiresInSeconds'),
      refreshTokenExpiresInSeconds: _requiredInt(response, 'refreshTokenExpiresInSeconds'),
      userId: _requiredString(claims, 'sub'),
      roles: rawRoles is List
          ? rawRoles.whereType<String>().toSet()
          : const <String>{},
      homePath: claims['homePath'] is String ? claims['homePath'] as String : null,
    );
  }

  static Session fromJson(Map<String, Object?> value) {
    final roles = value['roles'];
    return Session(
      accessToken: _requiredString(value, 'accessToken'),
      refreshToken: _requiredString(value, 'refreshToken'),
      accessTokenExpiresInSeconds: _requiredInt(value, 'accessTokenExpiresInSeconds'),
      refreshTokenExpiresInSeconds: _requiredInt(value, 'refreshTokenExpiresInSeconds'),
      userId: _requiredString(value, 'userId'),
      roles: roles is List ? roles.whereType<String>().toSet() : const <String>{},
      homePath: value['homePath'] is String ? value['homePath'] as String : null,
    );
  }
}

class OrgUnit {
  const OrgUnit({
    required this.id,
    required this.type,
    required this.name,
    required this.code,
    required this.parentId,
    required this.path,
    required this.isActive,
  });

  final String id;
  final String type;
  final String name;
  final String code;
  final String? parentId;
  final String path;
  final bool isActive;

  factory OrgUnit.fromJson(Map<String, Object?> value) {
    return OrgUnit(
      id: _requiredString(value, 'id'),
      type: _requiredString(value, 'type'),
      name: _requiredString(value, 'name'),
      code: _requiredString(value, 'code'),
      parentId: value['parentId'] is String ? value['parentId'] as String : null,
      path: _requiredString(value, 'path'),
      isActive: value['isActive'] == true,
    );
  }
}

Map<String, Object?> objectFromJson(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('The server returned an invalid response.');
  }
  return decoded.map<String, Object?>((Object? key, Object? value) {
    return MapEntry<String, Object?>(key.toString(), value);
  });
}

List<Map<String, Object?>> objectListFromJson(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List) {
    throw const FormatException('The server returned an invalid list.');
  }
  return decoded.whereType<Map>().map((Map<Object?, Object?> item) {
    return item.map<String, Object?>((Object? key, Object? value) {
      return MapEntry<String, Object?>(key.toString(), value);
    });
  }).toList(growable: false);
}

Map<String, Object?> _jwtClaims(String token) {
  final segments = token.split('.');
  if (segments.length != 3) {
    throw const FormatException('The server returned an invalid access token.');
  }
  return objectFromJson(utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))));
}

String _requiredString(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw FormatException('The server response did not contain $key.');
  }
  return result;
}

int _requiredInt(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is int) {
    return result;
  }
  if (result is num) {
    return result.toInt();
  }
  throw FormatException('The server response did not contain $key.');
}

class SummaryTotal {
  const SummaryTotal({required this.id, required this.code, required this.name, required this.total});

  final String id;
  final String code;
  final String name;
  final int total;

  factory SummaryTotal.fromJson(Map<String, Object?> value) {
    final rawTotal = value['total'];
    return SummaryTotal(
      id: _requiredString(value, 'id'),
      code: _requiredString(value, 'code'),
      name: _requiredString(value, 'name'),
      total: rawTotal is num ? rawTotal.toInt() : 0,
    );
  }
}
