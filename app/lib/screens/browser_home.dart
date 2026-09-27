import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/cyberwolf_panel.dart';
import '../widgets/background_menu.dart';
import '../widgets/browser_view.dart';
import '../widgets/app_logo.dart';
import '../widgets/made_by.dart';
import '../widgets/startpage/start_page.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import '../services/auto_update.dart';
import '../services/recent_service.dart';
import '../services/sound_service.dart';
import 'downloads_screen.dart';
import 'login_screen.dart';

class _Tab {
  String? url;
  _Tab();
  String get title {
    if (url == null) return 'WolfPulse';
    try {
      final h = Uri.parse(url!).host.replaceFirst(RegExp(r'^www\.'), '');
      return h.isEmpty ? 'Pagina' : h;
    } catch (_) {
      return 'Pagina';
    }
  }
}

class _NewTabIntent extends Intent {
  const _NewTabIntent();
}

class _CloseTabIntent extends Intent {
  const _CloseTabIntent();
}

class _FocusUrlIntent extends Intent {
  const _FocusUrlIntent();
}

class _ReloadIntent extends Intent {
  const _ReloadIntent();
}

class BrowserHomeScreen extends StatefulWidget {
  const BrowserHomeScreen({super.key});

  @override
  State<BrowserHomeScreen> createState() => _BrowserHomeScreenState();
}

class _BrowserHomeScreenState extends State<BrowserHomeScreen> {
  final _urlCtrl = TextEditingController();
  final _urlFocus = FocusNode();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _api = ApiService();
  final List<_Tab> _tabs = [_Tab()];
  int _active = 0;
  int _homeToken = 0;
  List<dynamic>? _barResults;
  bool _searching = false;

  static final _urlRe = RegExp(r'^(https?://)?[^\s]+\.[a-z]{2,}(/.*)?$', caseSensitive: false);

  _Tab get _tab => _tabs[_active];

  void _openUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    RecentService.add(u);
    setState(() {
      _tab.url = u;
      _barResults = null;
      _urlCtrl.text = u;
    });
  }

  void _newTab() {
    setState(() {
      _tabs.add(_Tab());
      _active = _tabs.length - 1;
      _barResults = null;
      _urlCtrl.clear();
      _homeToken++;
    });
  }

  void _closeTab(int i) {
    setState(() {
      _tabs.removeAt(i);
      if (_tabs.isEmpty) _tabs.add(_Tab());
      if (_active >= _tabs.length) _active = _tabs.length - 1;
      _barResults = null;
      _urlCtrl.text = _tab.url ?? '';
      _homeToken++;
    });
  }

  void _switchTab(int i) {
    setState(() {
      _active = i;
      _barResults = null;
      _urlCtrl.text = _tab.url ?? '';
      _homeToken++;
    });
  }

  Future<void> _submitBar(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    if (t.toLowerCase() == 'download') {
      _downloadApps();
      return;
    }
    if (_urlRe.hasMatch(t)) {
      _openUrl(t);
      return;
    }
    setState(() {
      _searching = true;
      _tab.url = null;
      _barResults = null;
    });
    try {
      final j = await _api.search(t);
      if (!mounted) return;
      setState(() => _barResults = (j['results'] ?? []) as List<dynamic>);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zoeken is mislukt. Controleer de verbinding.')));
      }
    }
    if (mounted) setState(() => _searching = false);
  }

  void _goHome() => setState(() {
        _tab.url = null;
        _urlCtrl.clear();
        _barResults = null;
        _homeToken++;
      });

  void _closeActiveTab() {
    if (_tabs.length <= 1) {
      // Laatste tabblad dicht = app sluiten (net als andere browsers)
      SystemNavigator.pop();
      return;
    }
    _closeTab(_active);
  }

  void _reloadActive() {
    final u = _tab.url;
    if (u != null) {
      setState(() {
        _tab.url = null;
        _homeToken++;
      });
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _openUrl(u);
      });
    } else {
      setState(() => _homeToken++);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SoundService.playStartup();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final done = await AutoUpdate.checkAndInstall(context);
      if (!done && mounted) UpdateService.checkAndPrompt(context);
    });
  }

  Future<void> _downloadApps() async {
    final url = await UpdateService.bundleUrl();
    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nog geen downloadbundle beschikbaar.')));
      }
      return;
    }
    await UpdateService.openUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyT): const _NewTabIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyW): const _CloseTabIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyL): const _FocusUrlIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyR): const _ReloadIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyT): const _NewTabIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyW): const _CloseTabIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NewTabIntent: CallbackAction<_NewTabIntent>(onInvoke: (_) => _newTab()),
          _CloseTabIntent: CallbackAction<_CloseTabIntent>(onInvoke: (_) => _closeActiveTab()),
          _FocusUrlIntent: CallbackAction<_FocusUrlIntent>(
              onInvoke: (_) {
                _urlFocus.requestFocus();
                _urlCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _urlCtrl.text.length);
                return null;
              }),
          _ReloadIntent: CallbackAction<_ReloadIntent>(onInvoke: (_) => _reloadActive()),
        },
        child: Focus(
          autofocus: true,
          child: _buildScaffold(settings),
        ),
      ),
    );
  }

  Widget _buildScaffold(SettingsProvider settings) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 30, showName: false),
            SizedBox(width: 8),
            Flexible(child: Text(AppConfig.browserName)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.home), onPressed: _goHome, tooltip: 'Startpagina'),
          IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Downloads',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DownloadsScreen(onOpenUrl: _openUrl)))),
          _accountButton(),
          IconButton(
            icon: const Icon(Icons.smart_toy),
            tooltip: AppConfig.aiName,
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlCtrl,
                        focusNode: _urlFocus,
                        onSubmitted: _submitBar,
                        decoration: const InputDecoration(
                          hintText: 'Voer URL in of zoek via WolfPulse…',
                          prefixIcon: Icon(Icons.lock_outline, size: 16),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.image),
                        tooltip: 'Achtergrond',
                        onPressed: () => showModalBottomSheet(
                            context: context,
                            builder: (_) => const BackgroundMenu())),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
                  itemCount: _tabs.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == _tabs.length) {
                      return IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: 'Nieuw tabblad',
                        onPressed: _newTab,
                      );
                    }
                    final active = i == _active;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        selected: active,
                        showCheckmark: false,
                        avatar: const AppLogo(size: 18, showName: false),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(_tabs[i].title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        deleteIcon: _tabs.length > 1
                            ? const Icon(Icons.close, size: 16)
                            : null,
                        onDeleted:
                            _tabs.length > 1 ? () => _closeTab(i) : null,
                        onPressed: () => _switchTab(i),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      endDrawer: const Drawer(width: 360, child: CyberWolfPanel()),
      body: settings.buildBackground(
        child: _tab.url != null
            ? _buildWebView(_tab.url!)
            : (_barResults != null || _searching
                ? _buildResults()
                : _buildStartPage()),
      ),
      floatingActionButton: _tab.url != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              icon: const Icon(Icons.smart_toy),
              label: const Text(AppConfig.aiName),
            ),
    );
  }

  Widget _accountButton() {
    final auth = context.watch<AuthProvider>();
    final label = auth.loggedIn && auth.naam.isNotEmpty
        ? auth.naam.characters.first.toUpperCase()
        : null;
    return IconButton(
      tooltip: auth.loggedIn ? 'Account (${auth.naam})' : 'Inloggen',
      icon: label == null
          ? const Icon(Icons.account_circle)
          : CircleAvatar(radius: 12, child: Text(label)),
      onPressed: _accountSheet,
    );
  }

  Future<void> _accountSheet() async {
    final auth = context.read<AuthProvider>();
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            CircleAvatar(
                radius: 28,
                child: Text(
                    auth.loggedIn ? auth.naam.characters.first.toUpperCase() : '?',
                    style: const TextStyle(fontSize: 24))),
            const SizedBox(height: 8),
            Text(auth.loggedIn ? auth.naam : 'Gastmodus',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
                auth.loggedIn
                    ? 'Eigen instellingen, geschiedenis en AI-geheugen.'
                    : 'Log in voor je eigen ruimte.',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 12),
            if (!auth.loggedIn)
              FilledButton.icon(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav
                      .push(MaterialPageRoute(
                          builder: (_) => const LoginScreen()))
                      .then((_) {
                    if (!mounted) return;
                    context.read<SettingsProvider>().load();
                  });
                },
                icon: const Icon(Icons.login),
                label: const Text('Inloggen / account maken'),
              )
            else
              OutlinedButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  await auth.logout();
                  if (!mounted) return;
                  context.read<SettingsProvider>().load();
                  nav.pop();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Uitloggen'),
              ),
            const SizedBox(height: 8),
            const MadeBy(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _barResults ?? [];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: results.length + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('🐺 ${results.length} resultaten via WolfPulse',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              );
            }
            final r = results[i - 1] as Map<String, dynamic>;
            return Card(
              child: ListTile(
                leading: Icon(
                    (r['source'] == 'local') ? Icons.star : Icons.public,
                    color: (r['source'] == 'local')
                        ? Colors.amber
                        : const Color(0xFF29B6F6)),
                title: Text(r['title']?.toString() ?? ''),
                subtitle: Text(r['snippet']?.toString() ?? '',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _openUrl(r['url'].toString()),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStartPage() {
    return StartPage(key: ValueKey(_homeToken), onOpenUrl: _openUrl);
  }

  Widget _buildWebView(String url) {
    return Column(
      children: [
        Material(
          elevation: 2,
          child: Row(
            children: [
              Expanded(
                  child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
              )),
              IconButton(icon: const Icon(Icons.close), onPressed: _goHome),
            ],
          ),
        ),
        Expanded(
            child: BrowserView(
                key: ValueKey('tab$_active-$url'),
                url: url,
                onClose: _goHome)),
      ],
    );
  }
}
