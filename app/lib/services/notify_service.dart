import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'local_notify_stub.dart'
    if (dart.library.io) 'local_notify.dart';
import 'sound_service.dart';

/// Luistert overal in de app (en website) naar nieuwe gebeurtenissen:
/// DM's, groepsberichten, mail en vriendschapsverzoeken.
/// Bij binnenkomst: meldingsgeluid + systeemmelding (Android, ook als de app
/// op de achtergrond draait).
class NotifyService {
  static Timer? _t;
  static bool _started = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    await LocalNotify.init();
    await _poll(first: true); // meting vastleggen, nog geen geluid
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  static Future<void> stop() async {
    _t?.cancel();
    _t = null;
    _started = false;
  }

  static Future<void> _poll({bool first = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      var since = p.getInt('notify_since') ?? 0;
      if (since <= 0) {
        await p.setInt('notify_since', DateTime.now().millisecondsSinceEpoch ~/ 1000);
        return;
      }
      final api = ApiService();
      if (!await api.resolveBase()) return;
      final j = await api.apiGet('/notify/events?since=$since');
      if (j is! Map) return;
      final m = j.cast<String, dynamic>();
      final now = (m['now'] as num?)?.toInt() ?? 0;
      if (now <= 0) return;
      await p.setInt('notify_since', now);
      if (first) return;

      final dms = _list(m['dms']);
      final groups = _list(m['groups']);
      final mails = _list(m['mails']);
      final friends = _list(m['friends']);
      if (dms.isEmpty && groups.isEmpty && mails.isEmpty && friends.isEmpty) {
        return;
      }

      String titel = 'AeroSurf';
      String body = '';
      if (dms.isNotEmpty) {
        final x = dms.first;
        titel = _s(x['from']) .isEmpty ? 'AeroTalk' : _s(x['from']);
        body = _s(x['body']);
      } else if (mails.isNotEmpty) {
        final x = mails.first;
        titel = 'Nieuwe mail';
        body = '${_s(x['from'])}: ${_s(x['body'])}';
      } else if (friends.isNotEmpty) {
        titel = 'Vriendschapsverzoek';
        body = _s(friends.first['from']);
      } else {
        final x = groups.first;
        titel = _s(x['group']).isEmpty ? 'AeroTalk' : _s(x['group']);
        body = '${_s(x['from'])}: ${_s(x['body'])}';
      }

      await SoundService.playNotif();
      await LocalNotify.show(titel, body.isEmpty ? 'Nieuwe melding' : body);
    } catch (_) {
      // stille backend / offline: volgende ronde opnieuw proberen
    }
  }

  static List<dynamic> _list(dynamic v) => v is List ? v : const [];

  static String _s(dynamic v) => v == null ? '' : v.toString();
}
