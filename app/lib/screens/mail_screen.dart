import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

/// E-mail op eigen domein (host op de Mini-PC): inbox, sturen, en voor
/// beheerders mailboxen aanmaken / toegang geven / eigendom overdragen.
class MailScreen extends StatefulWidget {
  const MailScreen({super.key});

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _status;
  List<dynamic> _boxes = [];
  List<dynamic> _msgs = [];
  int? _boxId;
  String _tab = 'in';
  bool _busy = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && _boxId != null) _loadInbox(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fout(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _loadAll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final st = await _api.apiGet('/mail/status');
      final boxes = await _api.apiGet('/mail/mailboxes');
      if (!mounted) return;
      setState(() {
        _status = st is Map<String, dynamic> ? st : null;
        _boxes = boxes is List ? boxes : [];
        if (_boxId == null || !_boxes.any((b) => b['id'] == _boxId)) {
          _boxId = _boxes.isNotEmpty ? (_boxes.first['id'] as num).toInt() : null;
        }
        _busy = false;
      });
      if (_boxId != null) _loadInbox();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _fout(e);
      });
    }
  }

  Future<void> _loadInbox({bool silent = false}) async {
    if (_boxId == null) return;
    try {
      final r = await _api.apiGet('/mail/inbox/$_boxId?box=$_tab');
      if (!mounted || r is! Map) return;
      setState(() {
        _msgs = (r['messages'] as List?) ?? [];
        final s = r['unread'];
        final box = _boxes.firstWhere((b) => b['id'] == _boxId,
            orElse: () => <String, dynamic>{});
        if (box is Map) box['unread'] = s ?? 0;
      });
    } catch (e) {
      if (!silent) _snack(_fout(e));
    }
  }

  Future<void> _openMessage(dynamic id) async {
    try {
      final m = await _api.apiGet('/mail/messages/$id');
      if (!mounted || m is! Map<String, dynamic>) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MailMessageView(api: _api, msg: m)),
      );
      _loadInbox(silent: true);
    } catch (e) {
      _snack(_fout(e));
    }
  }

  Future<void> _compose() async {
    if (_boxId == null) return;
    final box = _boxes.firstWhere((b) => b['id'] == _boxId,
        orElse: () => <String, dynamic>{});
    final from = box is Map ? (box['address'] ?? '').toString() : '';
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => MailComposeScreen(api: _api, from: from, mailboxId: _boxId!)),
    );
    if (sent == true) {
      _snack('Verzonden');
      _loadInbox();
      _loadAll();
    }
  }

  Future<void> _manage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MailAdminScreen(api: _api)),
    );
    _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.loggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mail')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Log in om je mailbox te openen.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Inloggen'),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
              ),
            ],
          ),
        ),
      );
    }

    final manage = _status?['manage'] == true;
    final address = _boxes
        .firstWhere((b) => b['id'] == _boxId, orElse: () => <String, dynamic>{});

    return Scaffold(
      appBar: AppBar(
        title: Text(address is Map && address['address'] != null
            ? 'Mail  ·  ${address['address']}'
            : 'Mail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Vernieuwen',
            onPressed: () {
              _loadAll();
            },
          ),
          if (manage)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Mailbeheer (admin)',
              onPressed: _manage,
            ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Nieuw bericht',
            onPressed: _boxId == null ? null : _compose,
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _empty(Icons.error_outline, _error!, 'Opnieuw proberen', _loadAll)
              : Column(
                  children: [
                    if (_boxes.length > 1)
                      SizedBox(
                        height: 46,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          children: _boxes.map((b) {
                            final sel = b['id'] == _boxId;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text((b['address'] ?? '').toString()),
                                selected: sel,
                                onSelected: (_) {
                                  setState(() => _boxId = (b['id'] as num).toInt());
                                  _loadInbox();
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: Row(
                        children: [
                          _tabChip('in', 'Inbox', Icons.inbox),
                          const SizedBox(width: 8),
                          _tabChip('out', 'Verzonden', Icons.send),
                          const Spacer(),
                          if (_tab == 'in' && _boxId != null)
                            Text(
                              '${_unread()} ongelezen',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white54),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 16),
                    Expanded(
                      child: _boxId == null
                          ? _empty(Icons.mail_lock, 'Nog geen mailbox.',
                              manage ? 'Mailbox aanmaken' : null, manage ? _manage : null)
                          : RefreshIndicator(
                              onRefresh: () => _loadInbox(),
                              child: _msgs.isEmpty
                                  ? ListView(children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 80),
                                        child: _emptyText(_tab == 'in'
                                            ? 'Inbox is leeg.'
                                            : 'Nog niets verzonden.'),
                                      )
                                    ])
                                  : ListView.separated(
                                      padding: const EdgeInsets.only(bottom: 80),
                                      itemCount: _msgs.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (ctx, i) =>
                                          _tile(_msgs[i]),
                                    ),
                            ),
                    ),
                  ],
                ),
      floatingActionButton: _boxId == null
          ? null
          : FloatingActionButton(
              onPressed: _compose,
              tooltip: 'Nieuw bericht',
              child: const Icon(Icons.edit),
            ),
    );
  }

  int _unread() {
    for (final b in _boxes) {
      if (b is Map && b['id'] == _boxId) {
        return (b['unread'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  Widget _tabChip(String value, String label, IconData icon) {
    final sel = _tab == value;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: sel ? Colors.black : Colors.white70),
      label: Text(label),
      selected: sel,
      onSelected: (_) {
        setState(() => _tab = value);
        _loadInbox();
      },
    );
  }

  Widget _tile(dynamic raw) {
    if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
    final m = raw;
    final unread = m['dir'] == 'in' && m['is_read'] != true;
    final out = m['dir'] == 'out';
    final who = out ? 'Aan: ${m['to_addr']}' : 'Van: ${m['from_addr']}';
    final code = m['code']?.toString();
    final dt = DateTime.tryParse((m['received_at'] ?? '').toString())?.toLocal();
    final when = dt == null
        ? ''
        : '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return ListTile(
      tileColor: unread ? Colors.white.withOpacity(0.05) : null,
      leading: out
          ? const Icon(Icons.outgoing_mail, color: Colors.white54)
          : Icon(unread ? Icons.mark_email_unread : Icons.mail_outline,
              color: unread ? Colors.greenAccent : Colors.white54),
      title: Text(
        (m['subject'] ?? '(geen onderwerp)').toString(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontWeight: unread ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Text(
        '$who\n${m['snippet'] ?? ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white60),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(when, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          if (code != null && code.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade800,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(code,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
            ),
        ],
      ),
      onTap: () => _openMessage(m['id']),
    );
  }

  Widget _empty(IconData icon, String text, String? action, VoidCallback? onAction) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.white24),
          const SizedBox(height: 10),
          _emptyText(text),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ],
      ),
    );
  }

  Widget _emptyText(String t) => Center(
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
      );
}

/// Bericht lezen: code groot in beeld (kopiëren), tekst selecteerbaar.
class MailMessageView extends StatelessWidget {
  final ApiService api;
  final Map<String, dynamic> msg;
  const MailMessageView({super.key, required this.api, required this.msg});

  @override
  Widget build(BuildContext context) {
    final code = msg['code']?.toString();
    final dt = DateTime.tryParse((msg['received_at'] ?? '').toString())?.toLocal();
    final body = (msg['body_text'] ?? '').toString().trim().isEmpty
        ? _stripHtml((msg['body_html'] ?? '').toString())
        : (msg['body_text'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bericht'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Verwijderen',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Bericht verwijderen?'),
                  content: const Text('Dit kan niet ongedaan worden.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Annuleren')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Verwijderen')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                try {
                  await api.apiDelete('/mail/messages/${msg['id']}');
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            e.toString().replaceFirst('Exception: ', ''))));
                  }
                }
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text((msg['subject'] ?? '').toString(),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Van: ${msg['from_addr']}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text('Aan: ${msg['to_addr']}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (dt != null)
            Text(
                '${dt.day}-${dt.month}-${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (code != null && code.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withOpacity(0.35),
                border: Border.all(color: Colors.amberAccent),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Verificatiecode',
                            style: TextStyle(
                                fontSize: 12, color: Colors.white70)),
                        SizedBox(height: 4),
                      ],
                    ),
                  ),
                  Text(code,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                          color: Colors.amberAccent)),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.amberAccent),
                    tooltip: 'Code kopiëren',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code gekopieerd')));
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 32),
          SelectableText(body.isEmpty ? '(leeg bericht)' : body),
        ],
      ),
    );
  }

  static String _stripHtml(String html) {
    var t = html
        .replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|tr|li|h[1-6])>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}

/// Nieuw bericht versturen.
class MailComposeScreen extends StatefulWidget {
  final ApiService api;
  final String from;
  final int mailboxId;
  const MailComposeScreen(
      {super.key, required this.api, required this.from, required this.mailboxId});

  @override
  State<MailComposeScreen> createState() => _MailComposeScreenState();
}

class _MailComposeScreenState extends State<MailComposeScreen> {
  final _to = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _to.text.trim();
    final body = _body.text.trim();
    if (to.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vul ontvanger en bericht in.')));
      return;
    }
    setState(() => _sending = true);
    try {
      final r = await widget.api.apiPost('/mail/send', {
        'mailbox_id': widget.mailboxId,
        'to': to,
        'subject': _subject.text.trim(),
        'body': body,
      });
      if (!mounted) return;
      String msg = 'Verzonden';
      if (r is Map) {
        if (r['local'] == true) msg = 'Bezorgd in eigen mailbox';
        else if (r['sent'] != true) {
          msg = 'Opgeslagen, maar externe verzending mislukt'
              '${r['reason'] != null ? ' (${r['reason']})' : ''}';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nieuw bericht')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Van: ${widget.from}',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _to,
            decoration: const InputDecoration(
                labelText: 'Aan (naam@domein)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(
                labelText: 'Onderwerp', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 12,
            decoration: const InputDecoration(
                labelText: 'Bericht', border: OutlineInputBorder(), alignLabelWithHint: true),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Versturen'),
          ),
        ],
      ),
    );
  }
}

/// Admin: domeinen, mailboxen aanmaken, toegang geven, eigendom overdragen.
class MailAdminScreen extends StatefulWidget {
  final ApiService api;
  const MailAdminScreen({super.key, required this.api});

  @override
  State<MailAdminScreen> createState() => _MailAdminScreenState();
}

class _MailAdminScreenState extends State<MailAdminScreen> {
  Map<String, dynamic>? _status;
  List<dynamic> _domains = [];
  List<dynamic> _boxes = [];
  final _local = TextEditingController();
  final _domain = TextEditingController();
  final _owner = TextEditingController();
  int? _domainId;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _local.dispose();
    _domain.dispose();
    _owner.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _fout(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final st = await widget.api.apiGet('/mail/status');
      final dom = await widget.api.apiGet('/mail/domains');
      final boxes = await widget.api.apiGet('/mail/mailboxes');
      if (!mounted) return;
      setState(() {
        _status = st is Map<String, dynamic> ? st : null;
        _domains = dom is List ? dom : [];
        _boxes = boxes is List ? boxes : [];
        _domainId ??= _domains.isNotEmpty ? (_domains.first['id'] as num).toInt() : null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(_fout(e));
    }
  }

  Future<void> _createMailbox() async {
    final lp = _local.text.trim();
    if (lp.isEmpty) return;
    try {
      await widget.api.apiPost('/mail/mailboxes', {
        'localpart': lp,
        'domain_id': _domainId,
        if (_owner.text.trim().isNotEmpty) 'owner_username': _owner.text.trim(),
      });
      _local.clear();
      _owner.clear();
      _snack('Mailbox aangemaakt');
      _load();
    } catch (e) {
      _snack(_fout(e));
    }
  }

  Future<void> _createDomain() async {
    final d = _domain.text.trim().toLowerCase();
    if (d.isEmpty) return;
    try {
      await widget.api.apiPost('/mail/domains', {'domain': d});
      _domain.clear();
      _snack('Domein toegevoegd');
      _load();
    } catch (e) {
      _snack(_fout(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return Scaffold(
          appBar: AppBar(title: const Text('Mailbeheer')),
          body: const Center(child: CircularProgressIndicator()));
    }
    final relay = _status?['relay'] == true;
    final smtp = (_status?['smtp'] as Map?) ?? const {};
    final token = _status?['webhookToken']?.toString();
    final webhook = _status?['webhookUrl']?.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Mailbeheer'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Status',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Domeinen: ${_domains.length}'),
                  Text(
                      'SMTP (invoer): poorten ${(smtp['ports'] as List?)?.join(', ') ?? '-'}'),
                  Text('Uitgaand via relay: ${relay ? 'ja' : 'nee (MAIL_HOST niet ingesteld)'}'),
                  if (webhook != null && webhook.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                          child: Text('Webhook: $webhook',
                              style: const TextStyle(
                                  fontSize: 12, fontFamily: 'monospace'))),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: webhook));
                          _snack('Webhook-URL gekopieerd');
                        },
                      ),
                    ]),
                  ],
                  if (token != null && token.isNotEmpty)
                    Row(children: [
                      Expanded(
                          child: Text('Token: $token',
                              style: const TextStyle(
                                  fontSize: 12, fontFamily: 'monospace'))),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: token));
                          _snack('Token gekopieerd');
                        },
                      ),
                    ]),
                  const SizedBox(height: 6),
                  const Text(
                    'MX naar je server + poort 25 open: dan komt mail van buitenaf (sites, codes) binnen via de eigen SMTP-server. Zonder domein kun je de webhook-relay gebruiken.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nieuwe mailbox',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _local,
                        decoration: const InputDecoration(
                            labelText: 'naam', isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _domainId,
                      hint: const Text('domein'),
                      items: _domains
                          .map((d) => DropdownMenuItem<int>(
                              value: (d['id'] as num).toInt(),
                              child: Text((d['domain'] ?? '').toString())))
                          .toList(),
                      onChanged: (v) => setState(() => _domainId = v),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _owner,
                    decoration: const InputDecoration(
                        labelText: 'eigenaar (gebruikersnaam, leeg = jij)',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _createMailbox,
                    icon: const Icon(Icons.add),
                    label: const Text('Mailbox aanmaken'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Domeinen',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._domains.map((d) => ListTile(
                        dense: true,
                        leading: Icon(
                            d['is_default'] == true
                                ? Icons.star
                                : Icons.language,
                            size: 18),
                        title: Text('@${d['domain']}'),
                        subtitle: d['is_default'] == true
                            ? const Text('standaard', style: TextStyle(fontSize: 11))
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () async {
                            try {
                              await widget.api.apiDelete('/mail/domains/${d['id']}');
                              _load();
                            } catch (e) {
                              _snack(_fout(e));
                            }
                          },
                        ),
                      )),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _domain,
                        decoration: const InputDecoration(
                            labelText: 'domein.tld',
                            isDense: true,
                            border: OutlineInputBorder()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _createDomain,
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mailboxen',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._boxes.map((b) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.mail_outline, size: 18),
                        title: Text((b['address'] ?? '').toString()),
                        subtitle: Text(
                            'eigenaar: ${b['owner_username'] ?? '-'} · rol: ${b['role'] ?? '-'} · ${b['unread'] ?? 0} ongelezen',
                            style: const TextStyle(fontSize: 11)),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () async {
                          await _accessSheet(b);
                          _load();
                        },
                      )),
                  if (_boxes.isEmpty)
                    const Text('Nog geen mailboxen.',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _accessSheet(dynamic boxRaw) async {
    if (boxRaw is! Map) return;
    final box = boxRaw;
    final id = (box['id'] as num).toInt();
    final username = TextEditingController();
    var role = 'full';
    List<dynamic> access = [];
    try {
      final r = await widget.api.apiGet('/mail/mailboxes/$id/access');
      access = (r['access'] as List?) ?? [];
    } catch (e) {
      _snack(_fout(e));
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
                left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${box['address']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                const Text('Toegang', style: TextStyle(color: Colors.white70)),
                ...access.map((a) => ListTile(
                      dense: true,
                      leading: Icon(
                        a['role'] == 'owner'
                            ? Icons.star
                            : a['role'] == 'full'
                                ? Icons.edit
                                : Icons.visibility,
                        size: 18,
                      ),
                      title: Text('${a['username']}'),
                      subtitle: Text('${a['role']}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: a['role'] == 'owner'
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () async {
                                try {
                                  await widget.api.apiDelete(
                                      '/mail/mailboxes/$id/access/${a['user_id']}');
                                  setSheet(() => access.remove(a));
                                } catch (e) {
                                  _snack(_fout(e));
                                }
                              },
                            ),
                    )),
                const Divider(),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: username,
                      decoration: const InputDecoration(
                          labelText: 'gebruikersnaam',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: role,
                    items: const [
                      DropdownMenuItem(value: 'full', child: Text('volledig')),
                      DropdownMenuItem(value: 'read', child: Text('alleen lezen')),
                    ],
                    onChanged: (v) => setSheet(() => role = v ?? 'full'),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('Toegang geven'),
                      onPressed: () async {
                        try {
                          await widget.api.apiPost('/mail/mailboxes/$id/access',
                              {'username': username.text.trim(), 'role': role});
                          final r = await widget.api.apiGet('/mail/mailboxes/$id/access');
                          setSheet(() {
                            access = (r['access'] as List?) ?? [];
                            username.clear();
                          });
                        } catch (e) {
                          _snack(_fout(e));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Overdragen'),
                      onPressed: () async {
                        if (username.text.trim().isEmpty) {
                          _snack('Vul eerst een gebruikersnaam in');
                          return;
                        }
                        try {
                          await widget.api.apiPost('/mail/mailboxes/$id/transfer',
                              {'username': username.text.trim()});
                          final r = await widget.api.apiGet('/mail/mailboxes/$id/access');
                          setSheet(() {
                            access = (r['access'] as List?) ?? [];
                            username.clear();
                          });
                          _snack('Eigendom overgedragen');
                        } catch (e) {
                          _snack(_fout(e));
                        }
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Sluiten'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
