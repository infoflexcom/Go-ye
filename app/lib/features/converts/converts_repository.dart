import '../../core/api_client.dart';
import '../../core/models.dart';

class ConvertsRepository {
  const ConvertsRepository(this._api);

  final ApiClient _api;

  Future<ConvertRecord> create({
    required String fullName,
    String? phone,
    String? address,
    String? registeredAtUnitId,
    required String consentMethod,
  }) async {
    final body = <String, Object?>{
      'fullName': fullName,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (address != null && address.isNotEmpty) 'address': address,
      if (registeredAtUnitId != null) 'registeredAtUnitId': registeredAtUnitId,
      'consent': <String, Object?>{
        'granted': true,
        'version': '2026-11',
        'method': consentMethod,
      },
    };
    return ConvertRecord.fromJson(await _api.post('converts', body));
  }

  Future<ConvertPage> list({int offset = 0, int limit = 50}) async {
    final response = await _api.get(
      'converts',
      query: <String, String>{'offset': '$offset', 'limit': '$limit'},
    );
    return ConvertPage.fromJson(response);
  }

  Future<ConvertRecord> get(String id) async {
    return ConvertRecord.fromJson(await _api.get('converts/$id'));
  }

  Future<List<UnassignedConvert>> listUnassigned() async {
    final response = await _api.getList('converts/unassigned');
    return response.map(UnassignedConvert.fromJson).toList(growable: false);
  }

  Future<ConvertRecord> assignToParish({
    required String convertId,
    required String parishId,
  }) async {
    return ConvertRecord.fromJson(
      await _api.post('converts/$convertId/assign-parish', <String, Object?>{
        'parishId': parishId,
      }),
    );
  }
}
