import '../../core/api_client.dart';
import '../../core/models.dart';

class DirectoryRepository {
  const DirectoryRepository(this._api);

  final ApiClient _api;

  Future<List<OrgUnit>> listUnits() async {
    final response = await _api.getList('directory/org-units');
    return response.map(OrgUnit.fromJson).toList(growable: false);
  }
}
