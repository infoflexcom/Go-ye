import '../../core/api_client.dart';
import '../../core/models.dart';

/// Retrieves server-authoritative roll-ups. The client never totals convert
/// records locally, so every hierarchy role sees its own RLS-scoped count.
class ReportsRepository {
  const ReportsRepository(this._api);

  final ApiClient _api;

  Future<ScopedCount> countForUnit(OrgUnit unit) async {
    final response = await _api.get('reports/org-units/${unit.id}/converts');
    return ScopedCount.fromJson(response, scopeName: unit.name);
  }

  Future<ScopedCount> grandTotal() async {
    final response = await _api.get('admin/reports/grand-total');
    return ScopedCount.fromJson(response, scopeName: 'All countries');
  }
}
