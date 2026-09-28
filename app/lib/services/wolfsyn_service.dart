import 'api_service.dart';

/// WolfSyn API: servers, kanalen, berichten, rollen, DM's, profiel.
class WolfSynService {
  final ApiService _api = ApiService();

  Future<List<dynamic>> servers() async =>
      (await _api.apiGet('/wolf/servers')) as List<dynamic>;

  Future<Map<String, dynamic>> createServer(String name) async =>
      (await _api.apiPost('/wolf/servers', {'name': name})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> join(String code) async =>
      (await _api.apiPost('/wolf/join', {'code': code})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> serverDetail(int id) async =>
      (await _api.apiGet('/wolf/servers/$id')) as Map<String, dynamic>;

  Future<List<dynamic>> channels(int serverId) async =>
      (await _api.apiGet('/wolf/servers/$serverId/channels')) as List<dynamic>;

  Future<Map<String, dynamic>> createChannel(int serverId, String name) async =>
      (await _api.apiPost('/wolf/servers/$serverId/channels', {'name': name}))
          as Map<String, dynamic>;

  Future<List<dynamic>> messages(int channelId, {int before = 0}) async {
    final q = before > 0 ? '?before=$before&limit=50' : '?limit=50';
    return (await _api.apiGet('/wolf/channels/$channelId/messages$q')) as List<dynamic>;
  }

  Future<Map<String, dynamic>> send(int channelId, String body) async =>
      (await _api.apiPost('/wolf/channels/$channelId/messages', {'body': body}))
          as Map<String, dynamic>;

  Future<List<dynamic>> members(int serverId) async =>
      (await _api.apiGet('/wolf/servers/$serverId/members')) as List<dynamic>;

  Future<List<dynamic>> roles(int serverId) async =>
      (await _api.apiGet('/wolf/servers/$serverId/roles')) as List<dynamic>;

  Future<void> createRole(int serverId, String name, String color,
      {bool manage = false, bool kick = false}) async {
    await _api.apiPost('/wolf/servers/$serverId/roles',
        {'name': name, 'color': color, 'can_manage': manage, 'can_kick': kick});
  }

  Future<void> setRoles(int serverId, int userId, List<int> roleIds) async {
    await _api.apiPut('/wolf/servers/$serverId/members/$userId/roles',
        {'roleIds': roleIds});
  }

  Future<void> kick(int serverId, int userId) async {
    await _api.apiDelete('/wolf/servers/$serverId/members/$userId');
  }

  Future<List<dynamic>> users(String q) async =>
      (await _api.apiGet('/wolf/users?q=${Uri.encodeComponent(q)}')) as List<dynamic>;

  Future<List<dynamic>> inbox() async =>
      (await _api.apiGet('/wolf/inbox')) as List<dynamic>;

  Future<List<dynamic>> dms(int userId, {int before = 0}) async {
    final q = before > 0 ? '?before=$before&limit=50' : '?limit=50';
    return (await _api.apiGet('/wolf/dms/$userId$q')) as List<dynamic>;
  }

  Future<Map<String, dynamic>> sendDm(int userId, String body) async =>
      (await _api.apiPost('/wolf/dms/$userId', {'body': body})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> profile() async =>
      (await _api.apiGet('/wolf/profile')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> saveProfile({String? displayName, String? bio}) async =>
      (await _api.apiPut('/wolf/profile',
          {'display_name': displayName, 'bio': bio})) as Map<String, dynamic>;

  Future<String> uploadAvatar(String imagePath, String fileName) async {
    final url = await _api.uploadImage(imagePath, fileName);
    await _api.apiPost('/wolf/avatar', {'avatar_url': url});
    return url;
  }
}
