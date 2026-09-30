import 'api_service.dart';

/// AeroTalk API: servers, kanalen, berichten, rollen, DM's, profiel.
class WolfSynService {
  final ApiService _api = ApiService();

  Future<List<dynamic>> servers() async =>
      (await _api.apiGet('/wolf/servers')) as List<dynamic>;

  Future<Map<String, dynamic>> createServer(String name) async =>
      (await _api.apiPost('/wolf/servers', {'name': name})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> join(String code) async =>
      (await _api.apiPost('/wolf/join', {'code': code})) as Map<String, dynamic>;

  /// Server-tag instellen — alleen voor de server-eigenaar.
  Future<Map<String, dynamic>> setServerTag(int serverId, String tag) async =>
      (await _api.apiPut('/wolf/servers/$serverId/tag', {'tag': tag})) as Map<String, dynamic>;

  /// De server-tag voor jezelf verbergen (of weer tonen).
  Future<Map<String, dynamic>> setTagHidden(int serverId, {required bool hidden}) async =>
      (await _api.apiPost('/wolf/servers/$serverId/tag/visibility', {'hidden': hidden}))
          as Map<String, dynamic>;

  /// Server verwijderen — alleen de eigenaar (of admin).
  Future<Map<String, dynamic>> deleteServer(int serverId) async =>
      (await _api.apiDelete('/wolf/servers/$serverId')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> boost(int serverId) async =>
      (await _api.apiPost('/wolf/servers/$serverId/boost', {})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> serverDetail(int id) async =>
      (await _api.apiGet('/wolf/servers/$id')) as Map<String, dynamic>;

  Future<List<dynamic>> channels(int serverId) async =>
      (await _api.apiGet('/wolf/servers/$serverId/channels')) as List<dynamic>;

  Future<Map<String, dynamic>> createChannel(int serverId, String name,
          {String category = 'algemeen'}) async =>
      (await _api.apiPost('/wolf/servers/$serverId/channels',
          {'name': name, 'category': category})) as Map<String, dynamic>;

  Future<void> deleteChannel(int serverId, int channelId) async {
    await _api.apiDelete('/wolf/servers/$serverId/channels/$channelId');
  }

  Future<Map<String, dynamic>> updateChannel(int serverId, int channelId,
          {String? name, String? category}) async =>
      (await _api.apiPut('/wolf/servers/$serverId/channels/$channelId',
          {if (name != null) 'name': name, if (category != null) 'category': category}))
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

  // --- Vrienden ---
  Future<Map<String, dynamic>> friends() async =>
      (await _api.apiGet('/wolf/friends')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> requestFriend(String username) async =>
      (await _api.apiPost('/wolf/friends/request', {'username': username}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> respondFriend(int fromId, {bool accept = true}) async =>
      (await _api.apiPost('/wolf/friends/respond', {'from': fromId, 'accept': accept}))
          as Map<String, dynamic>;

  Future<void> removeFriend(int userId) async {
    await _api.apiDelete('/wolf/friends/$userId');
  }

  // --- Groepen (groeps-DM's) ---
  Future<List<dynamic>> groups() async =>
      (await _api.apiGet('/wolf/groups')) as List<dynamic>;

  Future<Map<String, dynamic>> createGroup(String name, List<int> memberIds) async =>
      (await _api.apiPost('/wolf/groups', {'name': name, 'memberIds': memberIds}))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> groupDetail(int id) async =>
      (await _api.apiGet('/wolf/groups/$id')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> sendGroup(int id, String body) async =>
      (await _api.apiPost('/wolf/groups/$id/messages', {'body': body}))
          as Map<String, dynamic>;

  Future<void> leaveGroup(int id) async {
    await _api.apiPost('/wolf/groups/$id/leave', {});
  }

  Future<Map<String, dynamic>> saveProfile({String? displayName, String? bio}) async =>
      (await _api.apiPut('/wolf/profile',
          {'display_name': displayName, 'bio': bio})) as Map<String, dynamic>;

  /// GIF's/stickers voor de AeroTalk-kiezer (Tenor via de backend).
  Future<List<dynamic>> gifs(String q, {bool stickers = false}) async {
    final term = q.trim().isNotEmpty ? q.trim() : (stickers ? 'sticker' : '');
    final r = await _api
        .apiGet(term.isEmpty ? '/gifs' : '/gifs?q=${Uri.encodeComponent(term)}');
    if (r is Map<String, dynamic>) {
      return (r['results'] as List<dynamic>?) ?? const [];
    }
    return r is List<dynamic> ? r : const [];
  }

  Future<String> uploadAvatar(String imagePath, String fileName) async {
    final url = await _api.uploadImage(imagePath, fileName);
    await _api.apiPost('/wolf/avatar', {'avatar_url': url});
    return url;
  }
}
