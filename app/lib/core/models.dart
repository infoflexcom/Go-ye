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
      accessTokenExpiresInSeconds: _requiredInt(
        response,
        'accessTokenExpiresInSeconds',
      ),
      refreshTokenExpiresInSeconds: _requiredInt(
        response,
        'refreshTokenExpiresInSeconds',
      ),
      userId: _requiredString(claims, 'sub'),
      roles: rawRoles is List
          ? rawRoles.whereType<String>().toSet()
          : const <String>{},
      homePath:
          claims['homePath'] is String ? claims['homePath'] as String : null,
    );
  }

  static Session fromJson(Map<String, Object?> value) {
    final roles = value['roles'];
    return Session(
      accessToken: _requiredString(value, 'accessToken'),
      refreshToken: _requiredString(value, 'refreshToken'),
      accessTokenExpiresInSeconds: _requiredInt(
        value,
        'accessTokenExpiresInSeconds',
      ),
      refreshTokenExpiresInSeconds: _requiredInt(
        value,
        'refreshTokenExpiresInSeconds',
      ),
      userId: _requiredString(value, 'userId'),
      roles:
          roles is List ? roles.whereType<String>().toSet() : const <String>{},
      homePath:
          value['homePath'] is String ? value['homePath'] as String : null,
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
      parentId:
          value['parentId'] is String ? value['parentId'] as String : null,
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
  return objectFromJson(
    utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
  );
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
  const SummaryTotal({
    required this.id,
    required this.code,
    required this.name,
    required this.total,
  });

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

class ConvertRecord {
  const ConvertRecord({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.address,
    required this.registeredAtUnitId,
    required this.parishId,
    required this.stage,
    required this.createdAt,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String? address;
  final String registeredAtUnitId;
  final String? parishId;
  final String stage;
  final DateTime? createdAt;

  factory ConvertRecord.fromJson(Map<String, Object?> value) {
    return ConvertRecord(
      id: _requiredString(value, 'id'),
      fullName: _requiredString(value, 'fullName'),
      phone: value['phone'] is String ? value['phone'] as String : null,
      address: value['address'] is String ? value['address'] as String : null,
      registeredAtUnitId: _requiredString(value, 'registeredAtUnitId'),
      parishId:
          value['parishId'] is String ? value['parishId'] as String : null,
      stage: _requiredString(value, 'stage'),
      createdAt: _date(value['createdAt']),
    );
  }
}

class ConvertPage {
  const ConvertPage({required this.total, required this.items});

  final int total;
  final List<ConvertRecord> items;

  factory ConvertPage.fromJson(Map<String, Object?> value) {
    final rawItems = value['items'];
    final rawTotal = value['total'];
    if (rawItems is! List) {
      throw const FormatException(
        'The server response did not contain convert items.',
      );
    }
    return ConvertPage(
      total: rawTotal is num ? rawTotal.toInt() : 0,
      items: rawItems
          .whereType<Map>()
          .map(
            (Map<Object?, Object?> item) => ConvertRecord.fromJson(
              item.map<String, Object?>((Object? key, Object? itemValue) {
                return MapEntry<String, Object?>(key.toString(), itemValue);
              }),
            ),
          )
          .toList(growable: false),
    );
  }
}

class UnassignedConvert extends ConvertRecord {
  const UnassignedConvert({
    required super.id,
    required super.fullName,
    required super.phone,
    required super.address,
    required super.registeredAtUnitId,
    required super.parishId,
    required super.stage,
    required super.createdAt,
    required this.unassignedAgeDays,
  });

  final int unassignedAgeDays;

  factory UnassignedConvert.fromJson(Map<String, Object?> value) {
    final base = ConvertRecord.fromJson(value);
    final rawAge = value['unassignedAgeDays'];
    return UnassignedConvert(
      id: base.id,
      fullName: base.fullName,
      phone: base.phone,
      address: base.address,
      registeredAtUnitId: base.registeredAtUnitId,
      parishId: base.parishId,
      stage: base.stage,
      createdAt: base.createdAt,
      unassignedAgeDays: rawAge is num ? rawAge.toInt() : 0,
    );
  }
}

DateTime? _date(Object? rawValue) {
  return rawValue is String ? DateTime.tryParse(rawValue)?.toLocal() : null;
}

class ScopedCount {
  const ScopedCount({
    required this.total,
    required this.byStage,
    this.scopeName,
  });

  final int total;
  final Map<String, int> byStage;
  final String? scopeName;

  factory ScopedCount.fromJson(
    Map<String, Object?> value, {
    String? scopeName,
  }) {
    final rawStages = value['byStage'];
    final stages = <String, int>{};
    if (rawStages is Map) {
      rawStages.forEach((Object? key, Object? count) {
        if (count is num) {
          stages[key.toString()] = count.toInt();
        }
      });
    }
    final rawTotal = value['total'];
    return ScopedCount(
      total: rawTotal is num ? rawTotal.toInt() : 0,
      byStage: stages,
      scopeName: scopeName,
    );
  }
}

class FollowUpTask {
  const FollowUpTask({
    required this.id,
    required this.convertId,
    required this.parishId,
    required this.taskType,
    required this.occurrenceNumber,
    required this.dueAt,
    required this.status,
    required this.convertName,
    this.phone,
    this.outcome,
    this.note,
    this.completedAt,
    this.completedBy,
  });

  final String id;
  final String convertId;
  final String parishId;
  final String taskType;
  final int occurrenceNumber;
  final DateTime dueAt;
  final String status;
  final String convertName;
  final String? phone;
  final String? outcome;
  final String? note;
  final DateTime? completedAt;
  final String? completedBy;

  factory FollowUpTask.fromJson(Map<String, Object?> value) {
    final dueAt = _date(value['dueAt']);
    if (dueAt == null) {
      throw const FormatException(
        'The server response did not contain follow-up dueAt.',
      );
    }
    return FollowUpTask(
      id: _requiredString(value, 'id'),
      convertId: _requiredString(value, 'convertId'),
      parishId: _requiredString(value, 'parishId'),
      taskType: _requiredString(value, 'taskType'),
      occurrenceNumber: _requiredInt(value, 'occurrenceNumber'),
      dueAt: dueAt,
      status: _requiredString(value, 'status'),
      convertName: _requiredString(value, 'convertName'),
      phone: value['phone'] is String ? value['phone'] as String : null,
      outcome: value['outcome'] is String ? value['outcome'] as String : null,
      note: value['note'] is String ? value['note'] as String : null,
      completedAt: _date(value['completedAt']),
      completedBy: value['completedBy'] is String
          ? value['completedBy'] as String
          : null,
    );
  }
}
