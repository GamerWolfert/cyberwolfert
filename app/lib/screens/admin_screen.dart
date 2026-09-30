import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_logo.dart';
import 'login_screen.dart';

class _Opt {
  final String group;
  final String key;
  final String label;
  final bool def;
  const _Opt(this.group, this.key, this.label, [this.def = true]);
}

const List<_Opt> _optDefs = [
  _Opt('Browser', 'newTabLinks', 'Links openen in een nieuw tabblad'),
  _Opt('Browser', 'restoreTabs', 'Tabbladen herstarten na herstart', true),
  _Opt('Browser', 'blockTrackers', 'Trackers blokkeren', true),
  _Opt('Browser', 'showFavicon', 'Favicon bij tabbladen tonen', true),
  _Opt('Browser', 'dblClickClose', 'Dubbelklik om tab te sluiten'),
  _Opt('Browser', 'autoReload', 'Dode pagina\'s automatisch verversen', true),
  _Opt('Browser', 'homeShortcut', 'Home-knop in de balk', true),
  _Opt('Browser', 'downloadsPrompt', 'Downloads eerst vragen', true),
  _Opt('Browser', 'zoomPerSite', 'Zoom per website onthouden', true),
  _Opt('Browser', 'nightMode', 'Nachtfilter op pagina\'s'),
  _Opt('Browser', 'spellCheck', 'Spellingscontrole in velden', true),
  _Opt('Browser', 'autoplayMedia', 'Video/audio automatisch afspelen'),
  _Opt('AeroSeek', 'safeSearch', 'SafeSearch aan', true),
  _Opt('AeroSeek', 'suggesties', 'Zoeksuggesties tonen', true),
  _Opt('AeroSeek', 'localFirst', 'Lokale prioriteitslinks eerst', true),
  _Opt('AeroSeek', 'history', 'Zoekgeschiedenis bijhouden', true),
  _Opt('AeroSeek', 'newTabResults', 'Resultaten in nieuw tabblad'),
  _Opt('AeroSeek', 'previewText', 'Snippet-tekst tonen', true),
  _Opt('AeroSeek', 'showSource', 'Bron van resultaat tonen', true),
  _Opt('AeroSeek', 'instantAnswers', 'Directe antwoorden bovenaan', true),
  _Opt('AeroSeek', 'dedupe', 'Dubbele resultaten samenvoegen', true),
  _Opt('AeroSeek', 'thumbPreviews', 'Voorbeelden bij resultaten'),
  _Opt('AeroNova AI', 'aiAan', 'AeroNova AI inschakelen', true),
  _Opt('AeroNova AI', 'aiCode', 'Codeermodus (uitvoer in blokken)', true),
  _Opt('AeroNova AI', 'aiNl', 'Nederlands afdwingen (je/jij)', true),
  _Opt('AeroNova AI', 'aiHistory', 'Chatgeschiedenis bewaren', true),
  _Opt('AeroNova AI', 'aiMemory', 'AI-geheugen gebruiken', true),
  _Opt('AeroNova AI', 'aiFast', 'Snelle antwoorden (kort antwoorden)', true),
  _Opt('AeroNova AI', 'aiWeb', 'Zoeken op het internet gebruiken', true),
  _Opt('AeroNova AI', 'aiImages', 'Afbeeldingen analyseren', true),
  _Opt('AeroNova AI', 'aiStream', 'Antwoord live tonen', true),
  _Opt('AeroNova AI', 'aiSummarize', 'Lange pagina\'s samenvatten', true),
  _Opt('AeroNova AI', 'aiTranslate', 'Automatisch vertalen', true),
  _Opt('AeroNova AI', 'aiExplain', 'Uitleg bij fouten geven', true),
  _Opt('AeroNova AI', 'aiFirstPerson', 'Eerste persoon als Wolf', true),
  _Opt('AeroNova AI', 'aiAgent', 'Remote agent: taken op apparaat', false),
  _Opt('AeroTalk', 'ephemeral', 'Berichten na 20s lezen wissen', true),
  _Opt('AeroTalk', 'onlineStatus', 'Online-status tonen', true),
  _Opt('AeroTalk', 'sounds', 'Geluiden bij nieuwe berichten', true),
  _Opt('AeroTalk', 'notify', 'Meldingen bij vermeldingen', true),
  _Opt('AeroTalk', 'images', 'Foto\'s toestaan in chat', true),
  _Opt('AeroTalk', 'typing', 'Typ-indicator tonen', true),
  _Opt('AeroTalk', 'timestamps', 'Tijd bij berichten tonen', true),
  _Opt('AeroTalk', 'readReceipts', 'Leesbevestigingen', true),
  _Opt('AeroTalk', 'dmAll', 'DM\'s van iedereen toestaan', true),
  _Opt('AeroTalk', 'compactChat', 'Compacte chatweergave'),
  _Opt('AeroTalk', 'linkPreviews', 'Link-previews in chat', true),
  _Opt('AeroTalk', 'mentionBadge', 'Badge bij vermeldingen', true),
  _Opt('Account', 'rememberDevice', 'Apparaat onthouden', true),
  _Opt('Account', 'loginAlerts', 'Melding bij nieuwe login', true),
  _Opt('Account', 'mailAlerts', 'E-mail bij belangrijke acties', true),
  _Opt('Account', 'twoStep', 'Extra bevestiging bij wijzigingen'),
  _Opt('Account', 'sessionTimeout', 'Sessie na inactiviteit afsluiten'),
  _Opt('Account', 'showEmail', 'E-mail zichtbaar in AeroTalk'),
  _Opt('Account', 'guestAccess', 'Gasten mogen zoeken', true),
  _Opt('Account', 'guestAI', 'Gasten mogen AI gebruiken', true),
  _Opt('Account', 'registerOpen', 'Nieuwe accounts toestaan', true),
  _Opt('Account', 'googleLogin', 'Inloggen met Google', true),
  _Opt('Account', 'avatarAuto', 'Avatar automatisch genereren', true),
  _Opt('Account', 'exportData', 'Mijn data exporteren', true),
  _Opt('Uiterlijk', 'darkDefault', 'Donker thema als standaard', true),
  _Opt('Uiterlijk', 'animations', 'Animaties aanzetten', true),
  _Opt('Uiterlijk', 'bigButtons', 'Grote knoppen', true),
  _Opt('Uiterlijk', 'compactNav', 'Compacte navigatie'),
  _Opt('Uiterlijk', 'gridHome', 'Startpagina als raster', true),
  _Opt('Uiterlijk', 'clock24', 'Klok in 24-uurs notatie', true),
  _Opt('Uiterlijk', 'iconLabels', 'Labels bij iconen tonen', true),
  _Opt('Uiterlijk', 'accentGlow', 'Gloed rond accentkleur', true),
  _Opt('Uiterlijk', 'weatherCard', 'Weerkaart op startpagina', true),
  _Opt('Uiterlijk', 'quickLinks', 'Snelle links op startpagina', true),
  _Opt('Uiterlijk', 'recentCard', 'Recente bezoeken tonen', true),
  _Opt('Uiterlijk', 'logoAnimation', 'Logo-animatie bij start', true),
  _Opt('Logs & Discord', 'discordSearch', 'Zoekopdrachten naar Discord', true),
  _Opt('Logs & Discord', 'discordAI', 'AI-chats naar Discord', true),
  _Opt('Logs & Discord', 'discordLogin', 'Logins naar Discord', true),
  _Opt('Logs & Discord', 'discordSystem', 'Systeem naar Discord', true),
  _Opt('Logs & Discord', 'discordWolfSyn', 'AeroTalk naar Discord', true),
  _Opt('Logs & Discord', 'keep30d', 'Logs 30 dagen bewaren', true),
  _Opt('Logs & Discord', 'anonymize', 'Gebruikersnamen maskeren in exports'),
  _Opt('Logs & Discord', 'allowExport', 'Log-exports toestaan', true),
  _Opt('Systeem', 'autoUpdate', 'Automatisch updaten', true),
  _Opt('Systeem', 'bgPersist', 'Achtergrond per account bewaren', true),
  _Opt('Systeem', 'strictRate', 'Strakke rate-limit', true),
  _Opt('Systeem', 'debugLog', 'Uitgebreid debuglogboek'),
  _Opt('Systeem', 'telemetry', 'Anonieme foutmeldingen', true),
  _Opt('Systeem', 'compress', 'Antwoorden comprimeren', true),
  _Opt('Systeem', 'healthPing', 'Elke minuut healthcheck', true),
  _Opt('Systeem', 'backupDb', 'Nachtelijke DB-backup', true),
  _Opt('Systeem', 'maintenance', 'Onderhoudsmodus'),
  _Opt('Systeem', 'killSwitch', 'Noodstop voor nieuwe logins'),
];

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _api = ApiService();
  final _userSearchCtrl = TextEditingController();
  final _announceCtrl = TextEditingController();
  Timer? _refreshTimer;
  Timer? _userSearchDebounce;
  Timer? _optSaveDebounce;

  int _section = 0;
  bool _busy = true;
  bool _saving = false;

  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _roles = [];
  Map<String, List<List<String>>> _permGroups = {};
  List<dynamic> _searchLogs = [];
  List<dynamic> _aiLogs = [];
  List<dynamic> _loginLogs = [];
  final Map<String, bool> _options = {};
  String? _message;

  @override
  void initState() {
    super.initState();
    for (final o in _optDefs) {
      _options[o.key] = o.def;
    }
    _loadAll();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 45), (_) => _loadOverview());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _userSearchDebounce?.cancel();
    _optSaveDebounce?.cancel();
    _userSearchCtrl.dispose();
    _announceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await Future.wait([
        _loadOverview(),
        _loadUsers(query: _userSearchCtrl.text),
        _loadRoles(),
        _loadPerms(),
        _loadLogs(),
        _loadSiteSettings(),
      ]);
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _loadOverview() async {
    try {
      final v = await _api.apiGet('/admin/overview');
      if (mounted && v is Map) {
        setState(() => _overview = Map<String, dynamic>.from(v));
      }
    } catch (_) {}
  }

  Future<void> _loadUsers({String query = ''}) async {
    try {
      final q = Uri.encodeComponent(query.trim());
      final r = await _api.apiGet('/admin/users?q=$q&limit=200');
      if (mounted && r is List) {
        setState(() => _users =
            r.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadRoles() async {
    try {
      final r = await _api.apiGet('/admin/roles');
      if (mounted && r is List) {
        setState(() => _roles =
            r.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadPerms() async {
    try {
      final r = await _api.apiGet('/admin/perms');
      final groups = (r is Map ? r['groups'] : null);
      if (mounted && groups is Map) {
        final out = <String, List<List<String>>>{};
        groups.forEach((k, v) {
          if (v is List) {
            out[k.toString()] = v
                .map((e) => (e as List).map((x) => x.toString()).toList())
                .toList();
          }
        });
        setState(() => _permGroups = out);
      }
    } catch (_) {}
  }

  Future<void> _loadLogs() async {
    try {
      final r = await Future.wait([
        _api.apiGet('/admin/logs/searches?limit=60'),
        _api.apiGet('/admin/logs/ai?limit=60'),
        _api.apiGet('/admin/logs/logins?limit=60'),
      ]);
      if (!mounted) return;
      setState(() {
        if (r[0] is List) _searchLogs = r[0] as List;
        if (r[1] is List) _aiLogs = r[1] as List;
        if (r[2] is List) _loginLogs = r[2] as List;
      });
    } catch (_) {}
  }

  Future<void> _loadSiteSettings() async {
    try {
      final r = await _api.apiGet('/admin/site/settings');
      if (mounted && r is Map) {
        final ann = (r['announcement'] ?? '').toString();
        _announceCtrl.text = ann;
        final raw = r['admin_options'];
        if (raw is String && raw.isNotEmpty) {
          final j = jsonDecode(raw);
          if (j is Map) {
            j.forEach((k, v) {
              if (v is bool) _options[k.toString()] = v;
            });
          }
        }
        setState(() {});
      }
    } catch (_) {}
  }

  void _flash(String msg) {
    if (!mounted) return;
    setState(() => _message = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _saveOptions() async {
    _optSaveDebounce?.cancel();
    _optSaveDebounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        await _api.apiPut('/admin/site/settings', {
          'announcement': _announceCtrl.text,
          'options': _options,
        });
        if (mounted) setState(() => _saving = false);
      } catch (_) {
        if (mounted) setState(() => _saving = false);
      }
    });
    if (mounted) setState(() => _saving = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.loggedIn || auth.user?['is_admin'] != true) {
      return _locked(context);
    }
    if (_busy) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 26, showName: false),
            SizedBox(width: 8),
            Text('Admin Panel'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
          IconButton(
            tooltip: 'Terug naar de browser',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _section,
            onDestinationSelected: (i) => setState(() => _section = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.admin_panel_settings,
                  color: Color(0xFF3CFF5C)),
            ),
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Overzicht'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('Gebruikers'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.workspace_premium_outlined),
                selectedIcon: Icon(Icons.workspace_premium),
                label: Text('Rollen'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: Text('Logs'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.tune),
                selectedIcon: Icon(Icons.tune),
                label: Text('Instellingen'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.warning_amber_outlined),
                selectedIcon: Icon(Icons.warning_amber),
                label: Text('Gevaar'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildSection()),
        ],
      ),
    );
  }

  Widget _locked(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 90),
            const SizedBox(height: 16),
            const Text(
              'Dit paneel is alleen voor de beheerder (gamerwolfert).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen())),
              icon: const Icon(Icons.login),
              label: const Text('Inloggen als admin'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Terug'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection() {
    switch (_section) {
      case 1:
        return _buildUsersSection();
      case 2:
        return _buildRolesSection();
      case 3:
        return _buildLogsSection();
      case 4:
        return _buildSettingsSection();
      case 5:
        return _buildDangerZone();
      default:
        return _buildOverview();
    }
  }

  Widget _wrap(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: const Color(0xFF0A120A),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Color(0xFF3CFF5C), size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_message!)),
                  ],
                ),
              ),
            ),
          ),
        ...children,
      ],
    );
  }

  Widget _title(String t, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(t, style: Theme.of(context).textTheme.headlineSmall),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildOverview() {
    final o = _overview ?? {};
    final up = (o['uptimeSec'] is num) ? (o['uptimeSec'] as num).toInt() : 0;
    return _wrap([
      _title('Overzicht',
          trailing: IconButton(
            tooltip: 'Vernieuwen',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          )),
      Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          _stat('Gebruikers', '${o['users'] ?? _users.length}', Icons.people),
          _stat('Zoekopdrachten (24u)', '${o['searches24h'] ?? 0}',
              Icons.search),
          _stat(
              'AI-chats (24u)', '${o['ai24h'] ?? 0}', Icons.smart_toy),
          _stat('Logins (24u)', '${o['logins24h'] ?? 0}', Icons.login),
          _stat('AeroTalk-servers', '${o['servers'] ?? 0}', Icons.groups),
          _stat('Uptime', _fmtDur(up), Icons.timelapse),
          _stat('Opties', '${_optDefs.length}', Icons.tune),
          _stat('Permissies', '${_permCount()}', Icons.lock),
        ],
      ),
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Snelle acties',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _action(Icons.person_add, 'Nieuwe gebruiker',
                      _showCreateUserDialog),
                  _action(Icons.mail, 'Testmail versturen', _testMail),
                  _action(Icons.search, 'Zoeklog wissen', () async {
                    await _api.apiDelete('/admin/logs/searches');
                    await _loadLogs();
                    _flash('Zoeklog gewist.');
                  }),
                  _action(Icons.smart_toy, 'AI-log wissen', () async {
                    await _api.apiDelete('/admin/logs/ai');
                    await _loadLogs();
                    _flash('AI-log gewist.');
                  }),
                  _action(Icons.refresh, 'Alles vernieuwen', _loadAll),
                ],
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _action(IconData icon, String label, Future<void> Function() fn) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: () async {
        try {
          await fn();
        } catch (e) {
          _flash(e.toString().replaceFirst('Exception: ', ''));
        }
      },
    );
  }

  int _permCount() {
    var n = 0;
    for (final v in _permGroups.values) {
      n += v.length;
    }
    return n;
  }

  String _fmtDur(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return h > 0 ? '${h}u ${m}m' : '${m}m';
  }

  Widget _stat(String label, String value, IconData icon) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A120A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF3CFF5C).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF3CFF5C), size: 24),
          const SizedBox(height: 10),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }

  // --- Gebruikers ---
  Widget _buildUsersSection() {
    return _wrap([
      _title('Gebruikers', trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _userSearchCtrl,
              decoration: const InputDecoration(
                hintText: 'Zoek op naam of e-mail…',
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                _userSearchDebounce?.cancel();
                _userSearchDebounce = Timer(const Duration(milliseconds: 400),
                    () => _loadUsers(query: v));
              },
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _showCreateUserDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Nieuwe gebruiker'),
          ),
        ],
      )),
      Card(
        child: _users.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Geen gebruikers gevonden.'),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('ID')),
                    DataColumn(label: Text('Gebruikersnaam')),
                    DataColumn(label: Text('Weergavenaam')),
                    DataColumn(label: Text('E-mail')),
                    DataColumn(label: Text('Bevestigd')),
                    DataColumn(label: Text('Admin')),
                    DataColumn(label: Text('Rollen')),
                    DataColumn(label: Text('Acties')),
                  ],
                  rows: _users.map((u) {
                    final id = (u['id'] as num?)?.toInt() ?? 0;
                    final roles = (u['roles'] is List)
                        ? (u['roles'] as List).join(', ')
                        : '';
                    return DataRow(cells: [
                      DataCell(Text('$id')),
                      DataCell(Text('${u['username'] ?? ''}')),
                      DataCell(Text('${u['displayName'] ?? ''}')),
                      DataCell(SizedBox(
                          width: 180,
                          child: Text('${u['email'] ?? '—'}',
                              overflow: TextOverflow.ellipsis))),
                      DataCell(Icon(
                          u['emailVerified'] == true
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 18,
                          color: u['emailVerified'] == true
                              ? Colors.greenAccent
                              : Colors.redAccent)),
                      DataCell(Icon(
                          u['is_admin'] == true
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 18,
                          color: u['is_admin'] == true
                              ? Colors.greenAccent
                              : Colors.redAccent)),
                      DataCell(SizedBox(
                          width: 160,
                          child: Text(roles, overflow: TextOverflow.ellipsis))),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Bewerken',
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _editUserDialog(u),
                          ),
                          IconButton(
                            tooltip: 'Wachtwoord resetten',
                            icon: const Icon(Icons.key, size: 18),
                            onPressed: () => _resetPassword(u),
                          ),
                          if (u['username']?.toString() != 'gamerwolfert')
                            IconButton(
                              tooltip: 'Verwijderen',
                              icon: const Icon(Icons.delete,
                                  size: 18, color: Colors.redAccent),
                              onPressed: () => _confirmDeleteUser(u),
                            ),
                        ],
                      )),
                    ]);
                  }).toList(),
                ),
              ),
      ),
    ]);
  }

  Future<void> _showCreateUserDialog() async {
    final user = TextEditingController();
    final pass = TextEditingController();
    final display = TextEditingController();
    final email = TextEditingController();
    var isAdmin = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nieuwe gebruiker'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: user,
                  decoration: const InputDecoration(
                      labelText: 'Gebruikersnaam', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: display,
                  decoration: const InputDecoration(
                      labelText: 'Weergavenaam', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'E-mail (optioneel)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Wachtwoord', border: OutlineInputBorder()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Admin-rechten'),
                  value: isAdmin,
                  onChanged: (v) => set(() => isAdmin = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuleren')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Aanmaken')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.apiPost('/admin/users', {
        'username': user.text.trim(),
        'password': pass.text,
        'displayName': display.text.trim().isEmpty
            ? user.text.trim()
            : display.text.trim(),
        'email': email.text.trim(),
        'is_admin': isAdmin,
      });
      await _loadUsers(query: _userSearchCtrl.text);
      await _loadOverview();
      _flash('Gebruiker aangemaakt.');
    } catch (e) {
      _flash(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editUserDialog(Map<String, dynamic> u) async {
    final display = TextEditingController(text: '${u['displayName'] ?? ''}');
    final email = TextEditingController(text: '${u['email'] ?? ''}');
    var verified = u['emailVerified'] == true;
    var isAdmin = u['is_admin'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('${u['username']} bewerken'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: display,
                  decoration: const InputDecoration(
                      labelText: 'Weergavenaam',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'E-mail', border: OutlineInputBorder()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('E-mail bevestigd'),
                  value: verified,
                  onChanged: (v) => set(() => verified = v),
                ),
                if (u['username']?.toString() != 'gamerwolfert')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Admin'),
                    value: isAdmin,
                    onChanged: (v) => set(() => isAdmin = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuleren')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Opslaan')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.apiPut('/admin/users/${u['id']}', {
        'displayName': display.text.trim(),
        'email': email.text.trim(),
        'emailVerified': verified,
        'is_admin': isAdmin,
      });
      await _loadUsers(query: _userSearchCtrl.text);
      _flash('Gebruiker bijgewerkt.');
    } catch (e) {
      _flash(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    try {
      final r = await _api.apiPost('/admin/users/${u['id']}/reset-password');
      final tmp = (r is Map ? r['tempPassword'] : '')?.toString() ?? '';
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tijdelijk wachtwoord'),
          content: SelectableText(
              'Nieuw wachtwoord voor ${u['username']}:\n\n$tmp'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Gekopieerd / oké')),
          ],
        ),
      );
    } catch (e) {
      _flash(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _confirmDeleteUser(Map<String, dynamic> u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gebruiker verwijderen?'),
        content: Text(
            'Weet je zeker dat je ${u['username']} wilt verwijderen? Dit kan niet ongedaan worden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.apiDelete('/admin/users/${u['id']}');
      await _loadUsers(query: _userSearchCtrl.text);
      await _loadOverview();
      _flash('Gebruiker verwijderd.');
    } catch (e) {
      _flash(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // --- Rollen & permissies ---
  Widget _buildRolesSection() {
    return _wrap([
      _title('Rollen & permissies',
          trailing: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Nieuwe rol'),
            onPressed: _showCreateRoleDialog,
          )),
      for (final g in _permGroups.entries) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.key,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: g.value
                      .map((p) => Chip(
                            avatar: const Icon(Icons.lock, size: 14),
                            label: Text('${p[1]} (${p[0]})',
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Card(
        child: _roles.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Nog geen rollen aangemaakt.'),
              )
            : Column(
                children: _roles.map((r) {
                  final perms = (r['permissions'] is Map)
                      ? (r['permissions'] as Map)
                      : <dynamic, dynamic>{};
                  final enabled =
                      perms.values.where((v) => v == true).length;
                  return ListTile(
                    leading: const Icon(Icons.workspace_premium),
                    title: Text('${r['name']}'),
                    subtitle: Text(
                        '${r['users'] ?? 0} gebruiker(s) · $enabled permissies'),
                    trailing: r['name'] == 'admin' || r['name'] == 'user'
                        ? const Chip(label: Text('systeem'))
                        : IconButton(
                            icon: const Icon(Icons.delete,
                                color: Colors.redAccent),
                            onPressed: () async {
                              try {
                                await _api
                                    .apiDelete('/admin/roles/${r['name']}');
                                await _loadRoles();
                                _flash('Rol verwijderd.');
                              } catch (e) {
                                _flash(e
                                    .toString()
                                    .replaceFirst('Exception: ', ''));
                              }
                            },
                          ),
                  );
                }).toList(),
              ),
      ),
    ]);
  }

  Future<void> _showCreateRoleDialog() async {
    final name = TextEditingController();
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nieuwe rol'),
          content: SizedBox(
            width: 460,
            height: 420,
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'Rolnaam (bijv. moderator)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: _permGroups.entries
                        .expand((g) => g.value.map((p) => CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(p[1],
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(p[0],
                                  style: const TextStyle(fontSize: 11)),
                              value: selected.contains(p[0]),
                              onChanged: (v) => set(() {
                                if (v == true) {
                                  selected.add(p[0]);
                                } else {
                                  selected.remove(p[0]);
                                }
                              }),
                            )))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuleren')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Aanmaken')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.apiPost('/admin/roles', {
        'name': name.text.trim().toLowerCase(),
        'permissions': {for (final p in selected) p: true},
      });
      await _loadRoles();
      _flash('Rol aangemaakt.');
    } catch (e) {
      _flash(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // --- Logs ---
  Widget _buildLogsSection() {
    return _wrap([
      _title('Logs',
          trailing: OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Vernieuwen'),
            onPressed: _loadLogs,
          )),
      _logCard('Zoekopdrachten', _searchLogs, (r) {
        return '${r['username'] ?? '?'} — ${r['query'] ?? ''}';
      }, (r) => '${r['created_at'] ?? ''}'),
      const SizedBox(height: 14),
      _logCard('AeroNova AI', _aiLogs, (r) {
        final role = '${r['role'] ?? ''}';
        final c = '${r['content'] ?? ''}';
        return '$role: $c';
      }, (r) => '${r['username'] ?? ''} · ${r['created_at'] ?? ''}'),
      const SizedBox(height: 14),
      _logCard('Logins & registraties', _loginLogs, (r) {
        return '${r['kind'] ?? ''} — ${r['username'] ?? ''}';
      }, (r) => '${r['created_at'] ?? ''}'),
    ]);
  }

  Widget _logCard(String title, List<dynamic> rows,
      String Function(Map) line, String Function(Map) meta) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text('${rows.length}',
                    style: const TextStyle(color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('Nog geen regels.')
            else
              ...rows.take(40).map((e) {
                final r = Map<String, dynamic>.from(e as Map);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 6, color: Colors.white24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(line(r),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text(meta(r),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white38)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // --- Instellingen ---
  Widget _buildSettingsSection() {
    final groups = <String>[];
    for (final o in _optDefs) {
      if (!groups.contains(o.group)) groups.add(o.group);
    }
    return _wrap([
      _title('Instellingen',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              Text('${_optDefs.length} opties',
                  style: const TextStyle(color: Colors.white54)),
            ],
          )),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mededeling op de startpagina',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _announceCtrl,
                maxLength: 500,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Bijv. Onderhoud om 22:00…'),
                onChanged: (_) => _saveOptions(),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      ...groups.map((g) => Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                    child: Text(g,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  ..._optDefs.where((o) => o.group == g).map((o) =>
                      SwitchListTile(
                        dense: true,
                        title: Text(o.label),
                        subtitle: Text(o.key,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white38)),
                        value: _options[o.key] ?? o.def,
                        onChanged: (v) {
                          setState(() => _options[o.key] = v);
                          _saveOptions();
                        },
                      )),
                ],
              ),
            ),
          )),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Testmail',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                          labelText: 'E-mailadres',
                          border: OutlineInputBorder(),
                          isDense: true),
                      onSubmitted: (_) => _testMail(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: _testMail,
                      child: const Text('Versturen')),
                ],
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Future<void> _testMail() async {
    var to = '';
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Testmail versturen'),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
              labelText: 'E-mailadres', border: OutlineInputBorder()),
          onChanged: (v) => to = v,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuleren')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Versturen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _api.apiPost('/admin/mail/test', {'to': to.trim()});
      final sent = r is Map && r['sent'] == true;
      _flash(sent
          ? 'Testmail verstuurd naar $to.'
          : 'Niet verstuurd: ${r is Map ? (r['reason'] ?? '?') : '?'}');
    } catch (e) {
      _flash(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // --- Gevaarzone ---
  Widget _buildDangerZone() {
    return _wrap([
      _title('Gevaarzone'),
      Card(
        color: const Color(0xFF2A0B10),
        child: Column(
          children: [
            _dangerTile(
              Icons.search,
              'Alle zoekopdrachten wissen',
              'Verwijdert de complete zoekgeschiedenis van iedereen.',
              () async {
                await _api.apiDelete('/admin/logs/searches');
                await _loadLogs();
                await _loadOverview();
                _flash('Zoekgeschiedenis gewist.');
              },
            ),
            _dangerTile(
              Icons.smart_toy,
              'Alle AI-chats wissen',
              'Verwijdert het volledige AI-chatlog.',
              () async {
                await _api.apiDelete('/admin/logs/ai');
                await _loadLogs();
                await _loadOverview();
                _flash('AI-chatlog gewist.');
              },
            ),
            _dangerTile(
              Icons.mail,
              'Testmail versturen',
              'Controleert of de SMTP-relay het doet.',
              _testMail,
            ),
            _dangerTile(
              Icons.restore,
              'Instellingen terug naar standaard',
              'Zet alle opties en de mededeling terug.',
              () async {
                setState(() {
                  for (final o in _optDefs) {
                    _options[o.key] = o.def;
                  }
                  _announceCtrl.clear();
                });
                await _api.apiPut('/admin/site/settings', {
                  'announcement': '',
                  'options': _options,
                });
                _flash('Terug naar de standaard.');
              },
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _dangerTile(
      IconData icon, String title, String sub, Future<void> Function() fn) {
    return ListTile(
      leading: Icon(icon, color: Colors.redAccent),
      title: Text(title),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: const Text('Weet je het zeker? Dit kan niet ongedaan worden.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuleren')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Uitvoeren'),
              ),
            ],
          ),
        );
        if (yes != true) return;
        try {
          await fn();
        } catch (e) {
          _flash(e.toString().replaceFirst('Exception: ', ''));
        }
      },
    );
  }
}
