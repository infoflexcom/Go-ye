import '../../core/api_client.dart';
import '../../core/models.dart';

class AdminReportsRepository {
  const AdminReportsRepository(this._api);

  final ApiClient _api;

  Future<List<SummaryTotal>> listCountries() async {
    final response = await _api.getList('admin/reports/countries');
    return response.map(SummaryTotal.fromJson).toList(growable: false);
  }

  Future<List<SummaryTotal>> listRegions(String countryId) async {
    final response = await _api.getList('admin/reports/countries/$countryId/regions');
    return response.map(SummaryTotal.fromJson).toList(growable: false);
  }
}
