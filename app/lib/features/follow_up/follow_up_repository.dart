import '../../core/api_client.dart';
import '../../core/models.dart';

class FollowUpRepository {
  const FollowUpRepository(this._api);

  final ApiClient _api;

  Future<List<FollowUpTask>> listToday() async {
    final response = await _api.getList('follow-up/today');
    return response.map(FollowUpTask.fromJson).toList(growable: false);
  }

  Future<FollowUpRiskPage<OverdueFollowUpTask>> listEscalations({
    int offset = 0,
    int limit = 50,
  }) async {
    final response = await _api.get(
      'follow-up/escalations',
      query: <String, String>{'offset': '$offset', 'limit': '$limit'},
    );
    return FollowUpRiskPage<OverdueFollowUpTask>.fromJson(
      response,
      OverdueFollowUpTask.fromJson,
    );
  }

  Future<FollowUpRiskPage<NeglectedConvert>> listNeglected({
    int offset = 0,
    int limit = 50,
  }) async {
    final response = await _api.get(
      'follow-up/neglected',
      query: <String, String>{'offset': '$offset', 'limit': '$limit'},
    );
    return FollowUpRiskPage<NeglectedConvert>.fromJson(
      response,
      NeglectedConvert.fromJson,
    );
  }

  Future<FollowUpTask> complete(
    String taskId, {
    required String outcome,
    String? note,
  }) async {
    return FollowUpTask.fromJson(
      await _api.post('follow-up/tasks/$taskId/complete', <String, Object?>{
        'outcome': outcome,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }),
    );
  }

  Future<void> registerPushToken(String token) async {
    await _api.post('follow-up/push-tokens', <String, Object?>{'token': token});
  }
}
