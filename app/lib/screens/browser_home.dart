import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/cyberwolf_panel.dart';
import '../widgets/background_menu.dart';
import '../widgets/browser_handle.dart';
import '../widgets/browser_view.dart';
import '../widgets/app_logo.dart';
import '../widgets/made_by.dart';
import '../widgets/startpage/start_page.dart';
import '../services/update_service.dart';
import '../services/auto_update.dart';
import '../services/recent_service.dart';
import '../services/sound_service.dart';
import '../services/url_utils.dart';
import 'downloads_screen.dart';
import 'login_screen.dart';
import 'wolfsyn_screen.dart';
import 'mail_screen.dart';
import 'search_results_screen.dart';
import 'admin_screen.dart';

class _Tab {
  static int _nextId = 0;
  final int id = _nextId++;
  String? url;
  final handle = BrowserHandle(); // terug/vooruit/verversen per tabblad
  _Tab();
  String get title {
    if (url == null) return 'AeroSeek';
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
  final List<_Tab> _tabs = [_Tab()];
  int _active = 0;
  int _homeToken = 0;
  bool _gateShown = false;

  /// Zie [UrlUtils]: alles wat een adres is wordt URL, de rest gezocht.
  static String? asUrl(String raw) => UrlUtils.asUrl(raw);

  _Tab get _tab => _tabs[_active];

  void _openUrl(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return;
    final alsUrl = UrlUtils.asUrl(raw);
    if (alsUrl == null) {
      // Geen adres -> zoeken, net als in de werkbalk. Zo "werkt" alles.
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                SearchResultsScreen(query: raw, onOpenUrl: _openUrl)),
      );
      return;
    }
    final u = UrlUtils.normScheme(alsUrl);
    RecentService.add(u);
    setState(() {
      _tab.url = u;
      _urlCtrl.text = u;
    });
  }

  void _newTab() {
    setState(() {
      _tabs.add(_Tab());
      _active = _tabs.length - 1;
      _urlCtrl.clear();
      _homeToken++;
    });
  }

  void _closeTab(int i) {
    setState(() {
      _tabs.removeAt(i);
      if (_tabs.isEmpty) _tabs.add(_Tab());
      if (_active >= _tabs.length) _active = _tabs.length - 1;
      _urlCtrl.text = _tab.url ?? '';
      _homeToken++;
    });
  }

  void _switchTab(int i) {
    setState(() {
      _active = i;
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
    final alsUrl = asUrl(t);
    if (alsUrl != null) {
      _openUrl(alsUrl);
      return;
    }
    if (!mounted) return;
    _urlCtrl.clear();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(query: t, onOpenUrl: _openUrl),
      ),
    );
  }

  void _goHome() => setState(() {
        _tab.url = null;
        _urlCtrl.clear();
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
      await _maybeLoginGate();
      if (!mounted) return;
      final done = await AutoUpdate.checkAndInstall(context);
      if (!done && mounted) UpdateService.checkAndPrompt(context);
    });
  }

  /// Start scherm: eerst vragen om in te loggen (gast mag ook verder).
  Future<void> _maybeLoginGate() async {
    if (_gateShown) return;
    _gateShown = true;
    final auth = context.read<AuthProvider>();
    for (var i = 0; i < 20 && auth.loading && mounted; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted || auth.loggedIn) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 76),
            const SizedBox(height: 14),
            const Text('Welkom bij AeroSurf',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Log in om je eigen achtergrond, geschiedenis en AI-geheugen te gebruiken.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Inloggen / account maken'),
                onPressed: () {
                  final nav = Navigator.of(ctx);
                  nav.pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ).then((_) {
                    if (!mounted) return;
                    context.read<SettingsProvider>().load();
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Verder als gast'),
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted) context.read<SettingsProvider>().load();
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
          if (context.watch<AuthProvider>().user?['is_admin'] == true)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Admin Panel',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
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
          IconButton(
            icon: const Icon(Icons.groups),
            tooltip: 'AeroTalk',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WolfSynScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.mail),
            tooltip: 'Mail',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MailScreen()),
            ),
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
                        textInputAction: TextInputAction.go,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText:
                              'Zoek met AeroSeek of typ een adres…',
                          hintStyle:
                              const TextStyle(color: Color(0xFF949BA4)),
                          prefixIcon: const Icon(Icons.search_rounded,
                              size: 19, color: Color(0xFF949BA4)),
                          suffixIcon: IconButton(
                            tooltip: 'Openen',
                            icon: const Icon(Icons.arrow_forward_rounded,
                                size: 18, color: Color(0xFF3CFF5C)),
                            onPressed: () => _submitBar(_urlCtrl.text),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0E140E),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
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
                      child: Material(
                        color: active
                            ? const Color(0xFF0E140E)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => _switchTab(i),
                          child: Container(
                            height: 34,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: active
                                    ? const Color(0xFF3CFF5C)
                                        .withValues(alpha: 0.45)
                                    : Colors.white10,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppLogo(size: 15, showName: false),
                                const SizedBox(width: 7),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 130),
                                  child: Text(
                                    _tabs[i].title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: active
                                            ? Colors.white
                                            : Colors.white70),
                                  ),
                                ),
                                if (_tabs.length > 1) ...[
                                  const SizedBox(width: 6),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _closeTab(i),
                                    child: const Icon(Icons.close_rounded,
                                        size: 15, color: Colors.white54),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
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
      // IndexedStack: alle tabs blijven leven (geluid/video loopt door
      // bij wisselen, webviews worden niet opnieuw opgebouwd)
      body: settings.buildBackground(child: _buildBody()),
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

  Widget _buildStartPage() {
    return StartPage(
        key: ValueKey(_homeToken), onOpenUrl: _openUrl, onApp: _openApp);
  }

  /// Openen van de ingebouwde apps vanaf de startpagina-tegels.
  void _openApp(String id) {
    switch (id) {
      case 'search':
        _urlFocus.requestFocus();
        break;
      case 'ai':
        _scaffoldKey.currentState?.openEndDrawer();
        break;
      case 'chat':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WolfSynScreen()));
        break;
      case 'mail':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const MailScreen()));
        break;
      case 'downloads':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => DownloadsScreen(onOpenUrl: _openUrl)));
        break;
      case 'settings':
        showModalBottomSheet(
            context: context, builder: (_) => const BackgroundMenu());
        break;
    }
  }

  /// Alle webviews blijven gemount (IndexedStack): geluid/video loopt door
  /// bij het wisselen van tabblad. Startpagina/resultaten liggen erbovenop.
  Widget _buildBody() {
    final urlTabs = <int>[];
    for (var i = 0; i < _tabs.length; i++) {
      if (_tabs[i].url != null) urlTabs.add(i);
    }
    if (_tab.url == null) {
      return Stack(
        children: [
          Visibility(
            visible: false,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: false,
            child: _buildTabsStack(urlTabs, 0),
          ),
          _buildStartPage(),
        ],
      );
    }
    return _buildTabsStack(urlTabs, urlTabs.indexOf(_active));
  }

  Widget _buildTabsStack(List<int> urlTabs, int visiblePos) {
    if (urlTabs.isEmpty) return const SizedBox.shrink();
    return IndexedStack(
      index: visiblePos < 0 ? 0 : visiblePos,
      children: [
        for (final i in urlTabs) _buildWebView(_tabs[i].url!, i),
      ],
    );
  }

  Widget _buildWebView(String url, [int? tabIndex]) {
    final tab = _tabs[tabIndex ?? _active];
    return Column(
      children: [
        Material(
          elevation: 2,
          color: const Color(0xFF080C08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Terug',
                  icon: const Icon(Icons.arrow_back_rounded, size: 19),
                  onPressed: tab.handle.back),
                IconButton(
                  tooltip: 'Vooruit',
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                  onPressed: tab.handle.forward),
                IconButton(
                  tooltip: 'Vernieuwen',
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  onPressed: tab.handle.reload),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E140E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_rounded,
                            size: 13, color: Color(0xFF3CFF5C)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5, color: Colors.white70)),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Extern openen',
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  onPressed: () async {
                    try {
                      await launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                ),
                IconButton(
                    tooltip: 'Startpagina',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: _goHome),
              ],
            ),
          ),
        ),
        Expanded(
            child: BrowserView(
                // Stabiele key per tabblad: webview (en geluid) blijft leven
                key: ValueKey('webview-${tabIndex ?? _active}'),
                url: url,
                handle: tab.handle,
                onClose: _goHome)),
      ],
    );
  }
}
