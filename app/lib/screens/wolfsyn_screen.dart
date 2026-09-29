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
  List<dynamic> _groups = [];
  Map<String, dynamic> _friends = {'friends': [], 'incoming': [], 'outgoing': []};
  Map<String, dynamic>? _profile;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
      Map<String, dynamic> f = {'friends': [], 'incoming': [], 'outgoing': []};
      List<dynamic> gs = [];
      try {
        f = await _api.friends();
      } catch (_) {}
      try {
        gs = await _api.groups();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _servers = s;
        _inbox = inbox;
        _profile = p;
        _friends = f;
        _groups = gs;
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
          tabs: const [
            Tab(text: 'Servers'),
            Tab(text: 'Vrienden'),
            Tab(text: 'DM\'s'),
          ],
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
                    _friendsTab(),
                    _inboxTab(),
                  ],
                ),
      floatingActionButton: _tabs.index == 1
          ? FloatingActionButton(
              tooltip: 'Groep met vrienden maken',
              onPressed: _groupDialog,
              child: const Icon(Icons.groups),
            )
          : _tabs.index == 2
              ? FloatingActionButton(
                  tooltip: 'Nieuw gesprek',
                  onPressed: _dmDialog,
                  child: const Icon(Icons.person_add),
                )
              : FloatingActionButton(
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
        final boosts = (s['boosts'] as num?)?.toInt() ?? 0;
        final level = boosts >= 7 ? 2 : boosts >= 2 ? 1 : 0;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
                backgroundColor: level > 0
                    ? _boostColor(level)
                    : null,
                child: Text((s['name'] ?? '?').toString().characters.first.toUpperCase())),
            title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text((s['name'] ?? '').toString()),
              if (level > 0)
                Tooltip(
                  message: 'Server boost niveau $level — gratis',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF7B2FF7), Color(0xFF29B6F6)]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('⚡ $level',
                        style: const TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                ),
            ]),
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

  Widget _friendsTab() {
    final friends = ((_friends['friends'] ?? []) as List).cast<dynamic>();
    final incoming = ((_friends['incoming'] ?? []) as List).cast<dynamic>();
    final outgoing = ((_friends['outgoing'] ?? []) as List).cast<dynamic>();
    final rows = <Widget>[];

    rows.add(Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _addFriendDialog,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Vriend toevoegen'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _groupDialog,
            icon: const Icon(Icons.groups),
            label: const Text('Groep maken'),
          ),
        ),
      ]),
    ));

    if (incoming.isNotEmpty) {
      rows.add(_sectionHeader('Vriendverzoeken (${incoming.length})'));
      rows.addAll(incoming.map((r) {
        final m = r as Map<String, dynamic>;
        return Card(
          child: ListTile(
            leading: _avatar(m['avatar']?.toString(),
                (m['display'] ?? m['username'] ?? '?').toString(), r: 18),
            title: Text((m['display'] ?? m['username'] ?? '?').toString()),
            subtitle: const Text('wil vriend worden'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                tooltip: 'Accepteren',
                onPressed: () async {
                  try {
                    await _api.respondFriend((m['id'] as num).toInt());
                    _load();
                  } catch (e) {
                    _snack(e);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.redAccent),
                tooltip: 'Weigeren',
                onPressed: () async {
                  try {
                    await _api.respondFriend((m['id'] as num).toInt(),
                        accept: false);
                    _load();
                  } catch (e) {
                    _snack(e);
                  }
                },
              ),
            ]),
          ),
        );
      }));
    }

    rows.add(_sectionHeader('Vrienden (${friends.length})'));
    if (friends.isEmpty) {
      rows.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Nog geen vrienden. Voeg iemand toe om te chatten of een groep te maken.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
      ));
    }
    rows.addAll(friends.map((f) {
      final m = f as Map<String, dynamic>;
      return Card(
        child: ListTile(
          leading: _avatar(
              m['avatar']?.toString(),
              (m['display'] ?? m['username'] ?? '?').toString(),
              r: 18),
          title: Text((m['display'] ?? m['username'] ?? '?').toString()),
          subtitle: Text('@${m['username'] ?? ''}',
              style: const TextStyle(fontSize: 11)),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'dm') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DmScreen(
                          userId: (m['id'] as num).toInt(),
                          name: (m['display'] ?? m['username'] ?? '?')
                              .toString())),
                ).then((_) => _load());
              } else if (v == 'weg') {
                try {
                  await _api.removeFriend((m['id'] as num).toInt());
                  _load();
                } catch (e) {
                  _snack(e);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dm', child: Text('Bericht sturen')),
              PopupMenuItem(value: 'weg', child: Text('Vriend verwijderen')),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => DmScreen(
                    userId: (m['id'] as num).toInt(),
                    name: (m['display'] ?? m['username'] ?? '?').toString())),
          ).then((_) => _load()),
        ),
      );
    }));

    if (outgoing.isNotEmpty) {
      rows.add(_sectionHeader('Verzonden verzoeken (${outgoing.length})'));
      rows.addAll(outgoing.map((o) {
        final m = o as Map<String, dynamic>;
        return ListTile(
          leading: _avatar(
              m['avatar']?.toString(),
              (m['display'] ?? m['username'] ?? '?').toString(),
              r: 16),
          title: Text((m['display'] ?? m['username'] ?? '?').toString()),
          subtitle: const Text('wacht op reactie'),
        );
      }));
    }

    rows.add(_sectionHeader('Mijn groepen (${_groups.length})'));
    if (_groups.isEmpty) {
      rows.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Nog geen groepen. Maak een groep met je vrienden.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
      ));
    }
    rows.addAll(_groups.map((g) {
      final m = g as Map<String, dynamic>;
      return Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.groups, size: 20)),
          title: Text((m['name'] ?? '').toString()),
          subtitle: Text(
              '${m['members'] ?? '?'} leden${(m['last_body'] ?? '').toString().isEmpty ? '' : ' • ${m['last_body']}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => GroupScreen(
                    groupId: (m['id'] as num).toInt(),
                    name: (m['name'] ?? '').toString())),
          ).then((_) => _load()),
        ),
      );
    }));

    rows.add(const SizedBox(height: 72));
    return ListView(
        padding: const EdgeInsets.all(12), children: rows);
  }

  Color _boostColor(int level) =>
      level >= 2 ? const Color(0xFFF4B400) : const Color(0xFF29B6F6);

  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.white70)),
      );

  void _snack(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  Future<void> _addFriendDialog() async {
    final q = TextEditingController();
    List<dynamic> found = [];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Vriend toevoegen'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: q,
                  decoration: const InputDecoration(
                      labelText: 'Gebruikersnaam',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (v) async {
                    if (v.trim().length < 2) return;
                    try {
                      final r = await _api.users(v.trim());
                      setD(() => found = r);
                    } catch (_) {}
                  },
                ),
                ...found.map((u) {
                  final m = u as Map;
                  return ListTile(
                    leading: _avatar(m['avatar']?.toString(),
                        (m['display'] ?? m['username'] ?? '?').toString(),
                        r: 18),
                    title: Text((m['display'] ?? m['username'] ?? '?').toString()),
                    trailing: const Icon(Icons.person_add),
                    onTap: () async {
                      try {
                        await _api.requestFriend((m['username'] ?? '').toString());
                        if (ctx.mounted) Navigator.pop(ctx);
                        _load();
                        _snack('Vriendverzoek verstuurd!');
                      } catch (e) {
                        _snack(e);
                      }
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Sluiten')),
          ],
        ),
      ),
    );
  }

  Future<void> _groupDialog() async {
    final friends = ((_friends['friends'] ?? []) as List).cast<dynamic>();
    if (friends.isEmpty) {
      _snack('Voeg eerst vrienden toe om een groep te maken.');
      return;
    }
    final naam = TextEditingController(text: 'Nieuwe groep');
    final sel = <int>{};
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Groep met vrienden'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: naam,
                    decoration: const InputDecoration(labelText: 'Groepsnaam')),
                const SizedBox(height: 8),
                ...friends.map((f) {
                  final m = f as Map<String, dynamic>;
                  final id = (m['id'] as num).toInt();
                  return CheckboxListTile(
                    dense: true,
                    title: Text(
                        (m['display'] ?? m['username'] ?? '?').toString()),
                    value: sel.contains(id),
                    onChanged: (v) => setD(() {
                      if (v == true) {
                        sel.add(id);
                      } else {
                        sel.remove(id);
                      }
                    }),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuleren')),
            FilledButton(
              onPressed: () async {
                if (sel.isEmpty) return;
                try {
                  final g = await _api.createGroup(
                      naam.text.trim().isEmpty ? 'Groep' : naam.text.trim(),
                      sel.toList());
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => GroupScreen(
                            groupId: (g['id'] as num).toInt(),
                            name: (g['name'] ?? '').toString())),
                  ).then((_) => _load());
                } catch (e) {
                  _snack(e);
                }
              },
              child: const Text('Maken'),
            ),
          ],
        ),
      ),
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
    final tag = TextEditingController();
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
            TextField(
                controller: tag,
                maxLength: 24,
                decoration: const InputDecoration(
                    labelText: 'Server-tag (achter je naam)',
                    helperText: 'Bijv. Wolf, Builder, Admin')),
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
        await _api.join(code.text.trim(), tag: tag.text.trim());
      } else {
        return;
      }
      _load();
    } catch (e) {
      _snack(e);
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
  String _myTag = '';
  int _boosts = 0;
  int _boostLevel = 0;
  bool _myBoost = false;
  int? _channelId;
  bool _busy = true;
  Timer? _poll;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _channelId != null) _loadMessages(silent: true);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final live = _messages
          .any((m) => m is Map && m['expires_at'] != null);
      if (live) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _msg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _api.serverDetail(widget.serverId);
      final ch = await _api.channels(widget.serverId);
      final boost = ((d['boost'] ?? {}) as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _members = (d['members'] ?? []) as List<dynamic>;
        _roles = (d['roles'] ?? []) as List<dynamic>;
        _rights = ((d['myRights'] ?? {}) as Map).cast<String, dynamic>();
        _invite = ((d['server'] ?? {})['invite_code'] ?? '').toString();
        _myTag = (d['myTag'] ?? '').toString();
        _boosts = (boost['boosts'] as num?)?.toInt() ?? 0;
        _boostLevel = (boost['level'] as num?)?.toInt() ?? 0;
        _myBoost = boost['mine'] == true;
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
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(
                '${widget.serverName} ${chName.isNotEmpty ? "#$chName" : ""}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16)),
          ),
          if (_boostLevel > 0) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Server boost niveau $_boostLevel ($_boosts boosts, gratis)',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF7B2FF7), Color(0xFF29B6F6)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('⚡ $_boostLevel',
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
              ),
            ),
          ],
        ]),
        actions: [
          IconButton(
              icon: Icon(Icons.bolt,
                  color: _myBoost ? Colors.amber : Colors.white54),
              tooltip: _myBoost
                  ? 'Boost dit (klik om te stoppen)'
                  : 'Boost deze server — gratis',
              onPressed: _boostToggle),
          IconButton(
              icon: const Icon(Icons.sell),
              tooltip: 'Mijn server-tag ($_myTag)',
              onPressed: _tagDialog),
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
                          final a = _authorOf(m);
                          final roles = (a['roles'] as List).cast<dynamic>();
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
                                              (a['display'] ?? '?')
                                                  .toString(),
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold)),
                                          if ((a['tag'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            _tagChip(a['tag'].toString()),
                                          ...roles.map((r) =>
                                              Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 6,
                                                    vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: _colorOf(
                                                      ((r is Map
                                                              ? r['color']
                                                              : null) ??
                                                          '#29B6F6')
                                                          .toString()),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8),
                                                ),
                                                child: Text(
                                                    ((r is Map
                                                            ? r['name']
                                                            : r) ?? '')
                                                        .toString(),
                                                    style: const TextStyle(
                                                        fontSize: 10)),
                                              )),
                                        ],
                                      ),
                                      Text((m['body'] ?? '').toString()),
                                      if (m['expires_at'] != null)
                                        _expiry(m['expires_at']),
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
                          hintText: 'Bericht…  (/delete om te wissen)',
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

  Widget _expiry(dynamic raw) {
    final exp = raw?.toString();
    if (exp == null || exp.isEmpty) return const SizedBox.shrink();
    final dt = DateTime.tryParse(exp)?.toLocal();
    if (dt == null) return const SizedBox.shrink();
    final left = dt.difference(DateTime.now()).inSeconds;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        left <= 0
            ? '⏳ verdwijnt zo…'
            : '⏳ verdwijnt over ${left}s (als iedereen het gelezen heeft)',
        style: const TextStyle(fontSize: 10, color: Colors.amberAccent),
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

  /// Berichten komen plat binnen (display/avatar/tag); rollen komen uit de
  /// ledenlijst, dus hier samengevoegd tot één auteurs-object.
  Map<String, dynamic> _authorOf(Map<String, dynamic> m) {
    final uid = (m['user_id'] as num?)?.toInt();
    dynamic mem;
    for (final x in _members) {
      if (x is Map && (x['id'] as num?)?.toInt() == uid) {
        mem = x;
        break;
      }
    }
    final ids = ((mem is Map ? mem['roles'] : null) ?? const []) as List;
    final roleObjs = _roles
        .where((r) => r is Map && ids.contains(r['id']))
        .take(3)
        .toList();
    return {
      'display': m['display'] ?? m['username'] ?? '?',
      'username': m['username'] ?? '',
      'avatar': m['avatar'],
      'tag': m['tag'] ?? '',
      'roles': roleObjs,
    };
  }

  Widget _tagChip(String tag) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white10,
          border: Border.all(color: Colors.white30),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(tag,
            style:
                const TextStyle(fontSize: 10, color: Colors.lightBlueAccent)),
      );

  Future<void> _tagDialog() async {
    final c = TextEditingController(text: _myTag);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mijn server-tag'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Kort label dat achter je naam verschijnt in deze server.',
                style: TextStyle(fontSize: 12)),
            TextField(
              controller: c,
              maxLength: 24,
              decoration:
                  const InputDecoration(labelText: 'Tag (bijv. Wolf, Builder)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuleren')),
          FilledButton(
            onPressed: () async {
              try {
                await _api.setServerTag(widget.serverId, c.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                _snack(e);
              }
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
  }

  Future<void> _boostToggle() async {
    try {
      final r = await _api.boost(widget.serverId);
      setState(() {
        _boosts = (r['boosts'] as num?)?.toInt() ?? _boosts;
        _boostLevel = (r['level'] as num?)?.toInt() ?? _boostLevel;
        _myBoost = r['mine'] == true;
      });
      _snack(_myBoost
          ? 'Server gebost! ⚡ niveau $_boostLevel — gratis, puur voor de looks.'
          : 'Boost ingetrokken.');
    } catch (e) {
      _snack(e);
    }
  }

  void _snack(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
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
                    final ids =
                        ((m['roles'] ?? []) as List).cast<dynamic>();
                    final roleObjs = _roles
                        .where((r) => r is Map && ids.contains(r['id']))
                        .toList();
                    final naam =
                        (m['display'] ?? m['username'] ?? '?').toString();
                    final tag = (m['tag'] ?? '').toString();
                    return ListTile(
                      leading: _avatar(m),
                      title: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(naam),
                            if (tag.isNotEmpty) _tagChip(tag),
                          ]),
                      subtitle: roleObjs.isEmpty
                          ? null
                          : Text(roleObjs
                              .map((r) => ((r as Map)['name'] ?? '').toString())
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
                              naam,
                              ids.map((r) => (r as num).toInt()).toList())
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
  Timer? _tick;
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
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final live = _messages
          .any((m) => m is Map && m['expires_at'] != null);
      if (live) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  String _dmExpiry(dynamic raw) {
    final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (dt == null) return '⏳ verdwijnt zo…';
    final left = dt.difference(DateTime.now()).inSeconds;
    return left <= 0
        ? '⏳ verdwijnt zo…'
        : '⏳ verdwijnt over ${left}s';
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
                    child: Column(
                      crossAxisAlignment: me
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text((m['body'] ?? '').toString()),
                        if (m['expires_at'] != null)
                          Text(
                            _dmExpiry(m['expires_at']),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.amberAccent),
                          ),
                      ],
                    ),
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

/// Groeps-DM met vrienden (zoals een Discord groeps-chat).
class GroupScreen extends StatefulWidget {
  final int groupId;
  final String name;
  const GroupScreen({super.key, required this.groupId, required this.name});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final _api = WolfSynService();
  final _msg = TextEditingController();
  List<dynamic> _messages = [];
  List<dynamic> _members = [];
  Map<String, dynamic> _group = {};
  Timer? _poll;
  Timer? _tick;
  int? _me;

  @override
  void initState() {
    super.initState();
    _api.profile().then((p) {
      if (mounted) setState(() => _me = (p['id'] as num?)?.toInt());
    });
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _load(silent: true);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final live =
          _messages.any((m) => m is Map && m['expires_at'] != null);
      if (live) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _msg.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final d = await _api.groupDetail(widget.groupId);
      if (!mounted) return;
      setState(() {
        _group = ((d['group'] ?? {}) as Map).cast<String, dynamic>();
        _members = (d['members'] ?? []) as List<dynamic>;
        _messages = (d['messages'] ?? []) as List<dynamic>;
      });
    } catch (e) {
      if (!silent) _snack(e);
    }
  }

  Future<void> _send() async {
    final t = _msg.text.trim();
    if (t.isEmpty) return;
    _msg.clear();
    try {
      await _api.sendGroup(widget.groupId, t);
      _load();
    } catch (e) {
      _snack(e);
    }
  }

  void _snack(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  String _expiry(dynamic raw) {
    final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (dt == null) return '⏳ verdwijnt zo…';
    final left = dt.difference(DateTime.now()).inSeconds;
    return left <= 0
        ? '⏳ verdwijnt zo…'
        : '⏳ verdwijnt over ${left}s (als iedereen het gelezen heeft)';
  }

  Widget _avatarOf(Map<String, dynamic> m, double r) {
    final url = m['avatar']?.toString();
    final name = (m['display'] ?? m['username'] ?? '?').toString();
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

  Future<void> _membersSheet() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Leden (${_members.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ..._members.map((m) {
                final mm = m as Map<String, dynamic>;
                return ListTile(
                  leading: _avatarOf(mm, 18),
                  title: Text((mm['display'] ?? mm['username'] ?? '?')
                      .toString()),
                  subtitle: Text(
                      (mm['id'] as num?)?.toInt() ==
                              (_group['owner_id'] as num?)?.toInt()
                          ? 'maker van de groep'
                          : '@${mm['username'] ?? ''}',
                      style: const TextStyle(fontSize: 11)),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Groep verlaten?'),
        content: const Text('De berichten die nog in de groep staan blijven '
            'voor de anderen, jij stapt eruit.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Blijven')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Verlaten')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.leaveGroup(widget.groupId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.groups, size: 20),
          const SizedBox(width: 6),
          Flexible(
              child: Text(widget.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16))),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.group),
              tooltip: 'Leden',
              onPressed: _membersSheet),
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Groep verlaten',
              onPressed: _leave),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final m = _messages[i] as Map<String, dynamic>;
                final uid = (m['user_id'] as num?)?.toInt();
                final me = _me != null && uid == _me;
                Map<String, dynamic> who = {'username': '?'};
                for (final x in _members) {
                  if (x is Map && (x['id'] as num?)?.toInt() == uid) {
                    who = x.cast<String, dynamic>();
                    break;
                  }
                }
                return Align(
                  alignment:
                      me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.all(10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(ctx).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: me ? Colors.green.shade700 : Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: me
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!me)
                          Text(
                              (who['display'] ?? who['username'] ?? '?')
                                  .toString(),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.lightBlueAccent)),
                        Text((m['body'] ?? '').toString()),
                        if (m['expires_at'] != null)
                          Text(
                            _expiry(m['expires_at']),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.amberAccent),
                          ),
                      ],
                    ),
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
                          hintText: 'Bericht naar de groep…  (/delete om te wissen)',
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
