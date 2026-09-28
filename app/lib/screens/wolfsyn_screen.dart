import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/wolfsyn_service.dart';
import '../widgets/app_logo.dart';
import 'login_screen.dart';

/// WolfSyn: community zoals Discord — servers, kanalen, rollen, DM's.
/// Volledig scherm; zonder login eerst naar browser-login.
class WolfSynScreen extends StatefulWidget {
  const WolfSynScreen({super.key});

  @override
  State<WolfSynScreen> createState() => _WolfSynScreenState();
}

class _WolfSynScreenState extends State<WolfSynScreen>
    with SingleTickerProviderStateMixin {
  final _api = WolfSynService();
  late TabController _tabs;
  List<dynamic> _servers = [];
  List<dynamic> _inbox = [];
  Map<String, dynamic>? _profile;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await _api.servers();
      final inbox = await _api.inbox();
      final p = await _api.profile();
      if (!mounted) return;
      setState(() {
        _servers = s;
        _inbox = inbox;
        _profile = p;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.loggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('WolfSyn')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 90),
              const SizedBox(height: 12),
              const Text('Log eerst in op je browser-account\nom WolfSyn te gebruiken.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()));
                  _load();
                },
                icon: const Icon(Icons.login),
                label: const Text('Naar browser-login'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 28, showName: false),
            SizedBox(width: 8),
            Text('WolfSyn'),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.person),
              tooltip: 'Mijn profiel',
              onPressed: () => _profileSheet().then((_) => _load())),
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Vernieuwen',
              onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Servers'), Tab(text: 'DM\'s')],
        ),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      FilledButton(
                          onPressed: _load,
                          child: const Text('Opnieuw')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _serversTab(),
                    _inboxTab(),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Server maken of joinen',
        onPressed: _serverDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _avatar(String? url, String name, {double r = 20}) {
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
          radius: r,
          backgroundImage: NetworkImage(url),
          onBackgroundImageError: (_, __) {},
          child: Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?'));
    }
    return CircleAvatar(
        radius: r,
        child: Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?'));
  }

  Widget _serversTab() {
    if (_servers.isEmpty) {
      return const Center(
          child: Text('Nog geen servers.\nMaak er een of join met een code.',
              textAlign: TextAlign.center));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _servers.length,
      itemBuilder: (ctx, i) {
        final s = _servers[i] as Map<String, dynamic>;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
                child: Text((s['name'] ?? '?').toString().characters.first.toUpperCase())),
            title: Text((s['name'] ?? '').toString()),
            subtitle: Text(
                '${s['members'] ?? '?'} leden • code: ${s['invite_code'] ?? ''}'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ServerScreen(
                      serverId: (s['id'] as num).toInt(),
                      serverName: (s['name'] ?? '').toString())),
            ).then((_) => _load()),
          ),
        );
      },
    );
  }

  Widget _inboxTab() {
    if (_inbox.isEmpty) {
      return const Center(
          child: Text('Nog geen DM\'s.\nZoek iemand op naam om te chatten.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _inbox.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: _dmDialog,
              icon: const Icon(Icons.person_search),
              label: const Text('Nieuw gesprek (zoek op naam)'),
            ),
          );
        }
        final c = _inbox[i - 1] as Map<String, dynamic>;
        final u = (c['user'] ?? {}) as Map<String, dynamic>;
        return Card(
          child: ListTile(
            leading: _avatar(u['avatar']?.toString(),
                (u['display'] ?? u['username'] ?? '?').toString()),
            title: Text(
                (u['display'] ?? u['username'] ?? '?').toString()),
            subtitle: Text((c['last'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DmScreen(
                      userId: (u['id'] as num).toInt(),
                      name: (u['display'] ?? u['username'] ?? '?')
                          .toString())),
            ).then((_) => _load()),
          ),
        );
      },
    );
  }

  Future<void> _serverDialog() async {
    final naam = TextEditingController();
    final code = TextEditingController();
    final tab = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: naam,
                decoration:
                    const InputDecoration(labelText: 'Nieuwe server-naam')),
            TextField(
                controller: code,
                decoration: const InputDecoration(
                    labelText: 'Of join-code plakken')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuleren')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'join'),
              child: const Text('Joinen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'nieuw'),
              child: const Text('Maken')),
        ],
      ),
    );
    try {
      if (tab == 'nieuw' && naam.text.trim().isNotEmpty) {
        await _api.createServer(naam.text.trim());
      } else if (tab == 'join' && code.text.trim().isNotEmpty) {
        await _api.join(code.text.trim());
      } else {
        return;
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _dmDialog() async {
    final q = TextEditingController();
    List<dynamic> found = [];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Persoon zoeken'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: q,
                  decoration: const InputDecoration(
                      labelText: 'Naam', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) async {
                    if (v.trim().length < 2) return;
                    try {
                      final r = await _api.users(v.trim());
                      setD(() => found = r);
                    } catch (_) {}
                  },
                ),
                ...found.map((u) => ListTile(
                      leading: _avatar(
                          (u as Map)['avatar']?.toString(),
                          (u['display'] ?? u['username'] ?? '?').toString(),
                          r: 18),
                      title: Text(
                          (u['display'] ?? u['username'] ?? '?').toString()),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DmScreen(
                                  userId: (u['id'] as num).toInt(),
                                  name: (u['display'] ??
                                          u['username'] ??
                                          '?')
                                      .toString())),
                        ).then((_) => _load());
                      },
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _profileSheet() async {
    final naam = TextEditingController(text: (_profile?['display_name'] ?? '').toString());
    final bio = TextEditingController(text: (_profile?['bio'] ?? '').toString());
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () async {
                final img = await ImagePicker()
                    .pickImage(source: ImageSource.gallery);
                if (img == null) return;
                try {
                  await _api.uploadAvatar(img.path, img.name);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Profielfoto bijgewerkt.')));
                    Navigator.pop(ctx);
                    _load();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e
                            .toString()
                            .replaceFirst('Exception: ', ''))));
                  }
                }
              },
              child: _avatar(
                  _profile?['avatar']?.toString(),
                  (_profile?['display_name'] ?? '?').toString(),
                  r: 36),
            ),
            const SizedBox(height: 4),
            const Text('Tik op de foto om te wijzigen',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 12),
            const Text('Mijn WolfSyn-profiel (los van browser-loginnaam)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
                controller: naam,
                decoration:
                    const InputDecoration(labelText: 'WolfSyn-naam')),
            TextField(
                controller: bio,
                decoration: const InputDecoration(labelText: 'Bio')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                try {
                  await _api.saveProfile(
                      displayName: naam.text.trim(), bio: bio.text.trim());
                  if (mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e
                            .toString()
                            .replaceFirst('Exception: ', ''))));
                  }
                }
              },
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Server met kanalen, berichten, leden en rollen.
class ServerScreen extends StatefulWidget {
  final int serverId;
  final String serverName;
  const ServerScreen(
      {super.key, required this.serverId, required this.serverName});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _api = WolfSynService();
  final _msg = TextEditingController();
  List<dynamic> _channels = [];
  List<dynamic> _messages = [];
  List<dynamic> _members = [];
  List<dynamic> _roles = [];
  Map<String, dynamic> _rights = {};
  String _invite = '';
  int? _channelId;
  bool _busy = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _channelId != null) _loadMessages(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _msg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _api.serverDetail(widget.serverId);
      final ch = await _api.channels(widget.serverId);
      if (!mounted) return;
      setState(() {
        _members = (d['members'] ?? []) as List<dynamic>;
        _roles = (d['roles'] ?? []) as List<dynamic>;
        _rights = ((d['myRights'] ?? {}) as Map).cast<String, dynamic>();
        _invite = ((d['server'] ?? {})['invite_code'] ?? '').toString();
        _channels = ch;
        _channelId ??= ch.isNotEmpty ? (ch.first['id'] as num).toInt() : null;
        _busy = false;
      });
      if (_channelId != null) _loadMessages();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_channelId == null) return;
    try {
      final m = await _api.messages(_channelId!);
      if (mounted) setState(() => _messages = m);
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Berichten laden mislukt.')));
      }
    }
  }

  Future<void> _send() async {
    final t = _msg.text.trim();
    if (t.isEmpty || _channelId == null) return;
    _msg.clear();
    try {
      await _api.send(_channelId!, t);
      _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chName = _channels
        .where((c) => (c['id'] as num).toInt() == _channelId)
        .map((c) => (c['name'] ?? '').toString())
        .fold<String>('', (a, b) => b);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.serverName} ${chName.isNotEmpty ? "#$chName" : ""}',
            style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
              icon: const Icon(Icons.group),
              tooltip: 'Leden en rollen',
              onPressed: _membersSheet),
          IconButton(
              icon: const Icon(Icons.tag),
              tooltip: 'Kanalen',
              onPressed: _channelsSheet),
          IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Uitnodigingscode',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Nodig mensen uit'),
                    content: SelectableText('Code: $_invite'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Sluiten')),
                    ],
                  ),
                );
              }),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _channelId == null
                    ? const Center(child: Text('Nog geen kanalen.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) {
                          final m =
                              _messages[i] as Map<String, dynamic>;
                          final a = (m['author'] ?? {}) as Map<String, dynamic>;
                          final roles =
                              ((a['roles'] ?? []) as List).cast<dynamic>();
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _avatar(a),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                              (a['display'] ??
                                                      a['username'] ??
                                                      '?')
                                                  .toString(),
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold)),
                                          ...roles.take(2).map((r) =>
                                              Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 6,
                                                    vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: _colorOf(
                                                      (r['color'] ??
                                                              '#29B6F6')
                                                          .toString()),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8),
                                                ),
                                                child: Text(
                                                    (r['name'] ?? '')
                                                        .toString(),
                                                    style: const TextStyle(
                                                        fontSize: 10)),
                                              )),
                                        ],
                                      ),
                                      Text((m['body'] ?? '').toString()),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msg,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                          hintText: 'Bericht…',
                          border: OutlineInputBorder()),
                    ),
                  ),
                  IconButton(
                      onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(Map<String, dynamic> a) {
    final url = a['avatar']?.toString();
    final name = (a['display'] ?? a['username'] ?? '?').toString();
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
          radius: 18,
          backgroundImage: NetworkImage(url),
          onBackgroundImageError: (_, __) {},
          child: Text(name.characters.first.toUpperCase()));
    }
    return CircleAvatar(
        radius: 18,
        child: Text(name.characters.first.toUpperCase()));
  }

  Color _colorOf(String hex) {
    try {
      var h = hex.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return const Color(0xFF29B6F6);
    }
  }

  Future<void> _channelsSheet() async {
    final manage = _rights['manage'] == true;
    final naam = TextEditingController();
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Kanalen',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ..._channels.map((c) => ListTile(
                    leading: const Icon(Icons.tag, size: 18),
                    title: Text((c['name'] ?? '').toString()),
                    trailing: (c['id'] as num).toInt() == _channelId
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    onTap: () {
                      setState(() => _channelId =
                          (c['id'] as num).toInt());
                      _loadMessages();
                      Navigator.pop(ctx);
                    },
                  )),
              if (manage)
                Row(children: [
                  Expanded(
                    child: TextField(
                        controller: naam,
                        decoration: const InputDecoration(
                            labelText: 'Nieuw kanaal')),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      if (naam.text.trim().isEmpty) return;
                      await _api.createChannel(
                          widget.serverId, naam.text.trim());
                      if (mounted) Navigator.pop(ctx);
                      _load();
                    },
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _membersSheet() async {
    final manage = _rights['manage'] == true;
    final kick = _rights['kick'] == true;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Leden en rollen',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (manage)
                TextButton.icon(
                  onPressed: () => _roleDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nieuwe rol'),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _members.length,
                  itemBuilder: (c2, i) {
                    final m = _members[i] as Map<String, dynamic>;
                    final roles =
                        ((m['roles'] ?? []) as List).cast<dynamic>();
                    return ListTile(
                      leading: _avatar(m),
                      title: Text((m['display'] ?? m['username'] ?? '?')
                          .toString()),
                      subtitle: roles.isEmpty
                          ? null
                          : Text(roles
                              .map((r) => (r['name'] ?? '').toString())
                              .join(', ')),
                      trailing: kick
                          ? IconButton(
                              icon: const Icon(Icons.person_remove,
                                  size: 20),
                              onPressed: () async {
                                await _api.kick(widget.serverId,
                                    (m['id'] as num).toInt());
                                if (mounted) Navigator.pop(ctx);
                                _load();
                              },
                            )
                          : null,
                      onTap: manage
                          ? () => _rolesDialog(
                              (m['id'] as num).toInt(),
                              (m['display'] ?? m['username'] ?? '?')
                                  .toString(),
                              roles
                                  .map((r) => (r['id'] as num).toInt())
                                  .toList())
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _roleDialog() async {
    final naam = TextEditingController();
    bool manage = false;
    bool kick = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nieuwe rol'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: naam,
                  decoration:
                      const InputDecoration(labelText: 'Rolnaam')),
              CheckboxListTile(
                  title: const Text('Mag beheren'),
                  value: manage,
                  onChanged: (v) => setD(() => manage = v ?? false)),
              CheckboxListTile(
                  title: const Text('Mag kicken'),
                  value: kick,
                  onChanged: (v) => setD(() => kick = v ?? false)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuleren')),
            FilledButton(
              onPressed: () async {
                if (naam.text.trim().isEmpty) return;
                await _api.createRole(widget.serverId, naam.text.trim(),
                    '#29B6F6',
                    manage: manage, kick: kick);
                if (mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Maken'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rolesDialog(int uid, String name, List<int> has) async {
    final sel = Set<int>.of(has);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Rollen voor $name'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _roles.map((r) {
                final id = (r['id'] as num).toInt();
                return CheckboxListTile(
                  title: Text((r['name'] ?? '').toString()),
                  value: sel.contains(id),
                  onChanged: (v) => setD(() {
                    if (v == true) {
                      sel.add(id);
                    } else {
                      sel.remove(id);
                    }
                  }),
                );
              }).toList(),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                await _api.setRoles(widget.serverId, uid, sel.toList());
                if (mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 1-op-1 DM-gesprek.
class DmScreen extends StatefulWidget {
  final int userId;
  final String name;
  const DmScreen({super.key, required this.userId, required this.name});

  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  final _api = WolfSynService();
  final _msg = TextEditingController();
  List<dynamic> _messages = [];
  Timer? _poll;
  int? _me;

  @override
  void initState() {
    super.initState();
    _api.profile().then((p) {
      if (mounted) setState(() => _me = (p['id'] as num?)?.toInt());
    });
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _msg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await _api.dms(widget.userId);
      if (mounted) setState(() => _messages = m);
    } catch (_) {}
  }

  Future<void> _send() async {
    final t = _msg.text.trim();
    if (t.isEmpty) return;
    _msg.clear();
    try {
      await _api.sendDm(widget.userId, t);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final m = _messages[i] as Map<String, dynamic>;
                final me = _me != null &&
                    (m['from_id'] as num).toInt() == _me;
                return Align(
                  alignment:
                      me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.all(10),
                    constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(ctx).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: me
                          ? Colors.green.shade700
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text((m['body'] ?? '').toString()),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msg,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                          hintText: 'Bericht…',
                          border: OutlineInputBorder()),
                    ),
                  ),
                  IconButton(
                      onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
