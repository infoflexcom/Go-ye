import '../../core/api_client.dart';
import '../../core/models.dart';

class FollowUpRepository {
  const FollowUpRepository(this._api);

  final ApiClient _api;

  Future<List<FollowUpTask>> listToday() async {
    final response = await _api.getList('follow-up/today');
    return response.map(FollowUpTask.fromJson).toList(growable: false);
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
