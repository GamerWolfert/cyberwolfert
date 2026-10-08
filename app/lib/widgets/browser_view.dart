import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/download_service.dart';
import '../screens/downloads_screen.dart' show DownloadsScreen;
import 'browser_handle.dart';
import 'internal_web.dart';
import 'windows_webview.dart';
import 'wolf_error.dart';

/// Echte AeroSurf-browser, alles intern:
/// - Android/iOS/macOS: ingebedde WebView
/// - Windows: ingebedde Edge WebView2
/// - Web: intern iframe-blad (direct of via proxy bij framing-blokkade)
/// - Linux: systeem-browser (fallback)
class BrowserView extends StatefulWidget {
  final String url;
  final void Function()? onClose;
  final BrowserHandle? handle;
  const BrowserView(
      {super.key, required this.url, this.onClose, this.handle});

  static bool get isMobileEmbedded {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };
  }

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> {
  WebViewController? _ctrl;
  int _progress = 0;
  String? _pageError;
  // Audio per tabblad: dempen + volume (mobiel via JS in de pagina)
  bool _muted = false;
  double _volume = 1.0; // eigen errorpagina i.p.v. andermans browser-tekst

  final List<String> _stack = [];
  int _index = -1;
  int _frameKey = 0;
  String? _embedUrl;
  bool _checking = false;
  bool _viaProxy = false;
  String? _webError; // eigen foutpagina op Web (nooit een kaal browser-plaatje)

  String get _current => (_index >= 0 && _index < _stack.length) ? _stack[_index] : widget.url;
  bool get _canBack => _index > 0;
  bool get _canForward => _index >= 0 && _index < _stack.length - 1;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _push(widget.url);
      _resolve(widget.url);
      widget.handle?.back = () {
        if (_canBack) setState(() => _index--);
        _resolve(_current);
      };
      widget.handle?.forward = () {
        if (_canForward) setState(() => _index++);
        _resolve(_current);
      };
      widget.handle?.reload = () => _resolve(_current);
    } else if (BrowserView.isMobileEmbedded) {
      _ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageFinished: (_) => _applyAudio(),
          onNavigationRequest: (req) {
            // Bestanden niet in de pagina laden maar downloaden (zoals echte browsers)
            if (DownloadService.looksLikeFile(req.url)) {
              _downloadInApp(req.url);
              return NavigationDecision.prevent;
            }
            setState(() => _pageError = null);
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => setState(() => _pageError = null),
          onWebResourceError: (e) {
            // Alleen hoofddocument-fouten: een kapotte afbeelding of
            // scriptje mag de pagina nooit vervangen door een foutpagina.
            if (e.isForMainFrame == false) return;
            setState(
                () => _pageError = _mobieleFout(e.errorType?.name ?? '', e.description));
          },
        ))
        ..loadRequest(Uri.parse(widget.url));
      widget.handle?.reload = _ctrl?.reload;
      widget.handle?.back = () => _ctrl?.goBack();
      widget.handle?.forward = () => _ctrl?.goForward();
    }
  }

  @override
  void dispose() {
    widget.handle?.clear();
    super.dispose();
  }

  /// Foutmelding van de WebView omzetten naar AeroSurf-taal
  /// (nooit een technische Engelstalige regel of een kaal browser-plaatje).
  String _mobieleFout(String type, String desc) {
    final t = type.toLowerCase();
    final d = desc.toLowerCase();
    if (t.contains('hostlookup') || d.contains('name resolution') || d.contains('dns')) {
      return 'Domein niet gevonden — controleer de spelling van het adres.';
    }
    if (t.contains('timeout') || d.contains('timeout')) {
      return 'Deze site reageert niet (timeout). Probeer het later nog eens.';
    }
    if (t.contains('connect') || d.contains('connect') || d.contains('connection')) {
      return 'Verbinding met deze site mislukt — hij is nu niet bereikbaar.';
    }
    if (t.contains('cert') || d.contains('certificate') || d.contains('ssl') || d.contains('tls')) {
      return 'De beveiligde verbinding (SSL) van deze site klopt niet.';
    }
    if (t.contains('io') || t.contains('file')) {
      return 'Netwerkfout — controleer je internetverbinding.';
    }
    if (desc.isNotEmpty && desc.length < 120 && !RegExp(r'^[a-z0-9_]+$').hasMatch(desc)) {
      return desc;
    }
    return 'Deze pagina is niet bereikbaar. Controleer het adres of je verbinding.';
  }

  /// Audio van dit tabblad dempen/zachter zetten (werkt op alle
  /// video/audio-elementen in de pagina, ook nieuwe na navigatie).
  Future<void> _applyAudio() async {
    final c = _ctrl;
    if (c == null) return;
    try {
      await c.runJavaScript(
          "document.querySelectorAll('video,audio').forEach(m=>{m.muted=${_muted ? 'true' : 'false'};m.volume=$_volume;});");
    } catch (_) {}
  }

  void _audioSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔊 Geluid van dit tabblad',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SwitchListTile(
                  secondary: Icon(
                      _muted ? Icons.volume_off : Icons.volume_up),
                  title: Text(_muted ? 'Gedempt' : 'Geluid aan'),
                  value: _muted,
                  onChanged: (v) {
                    setState(() => _muted = v);
                    setSheet(() {});
                    _applyAudio();
                  },
                ),
                Row(
                  children: [
                    const Icon(Icons.volume_down,
                        size: 20, color: Colors.white54),
                    Expanded(
                      child: Slider(
                        value: _volume,
                        onChanged: (v) {
                          setState(() => _volume = v);
                          setSheet(() {});
                          _applyAudio();
                        },
                      ),
                    ),
                    const Icon(Icons.volume_up,
                        size: 20, color: Colors.white54),
                  ],
                ),
                Text('${(_volume * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Download binnen de app + in de downloadlijst zetten.
  Future<void> _downloadInApp(String url) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloaden: ${DownloadService.fileNameOf(url)}…')));
    try {
      final e = await DownloadService.download(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gedownload: ${e.name}'),
          action: SnackBarAction(
            label: 'Openen',
            onPressed: () => DownloadsScreen.openEntry(context, e),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloaden is mislukt.')));
      }
    }
  }

  void _push(String url) {
    if (_index >= 0 && _stack[_index] == url) return;
    if (_index < _stack.length - 1) _stack.removeRange(_index + 1, _stack.length);
    _stack.add(url);
    _index = _stack.length - 1;
  }

  Future<void> _resolve(String url) async {
    if (!kIsWeb) return;
    setState(() {
      _checking = true;
      _viaProxy = false;
      _webError = null;
      _embedUrl = url;
    });
    try {
      final origin = Uri.base.origin;
      final r = await http
          .get(
              Uri.parse('$origin/api/frame-check?url=${Uri.encodeComponent(url)}'),
              headers: const {'ngrok-skip-browser-warning': '1'})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['framing'] == 'na') {
          if (mounted) {
            setState(() => _webError =
                (j['reason']?.toString()) ?? 'Deze pagina is niet bereikbaar.');
          }
        } else if (j['framing'] == 'blocked') {
          if (j['proxy'] == false) {
            // Bereikbaar, maar niet in te bedden en niet te proxy'en.
            if (mounted) {
              setState(() => _webError = (j['reason']?.toString()) ??
                  'Deze site weigert inbedden in AeroSurf.');
            }
          } else {
            if (mounted) {
              setState(() {
                _viaProxy = true;
                _embedUrl =
                    '$origin/api/proxy?url=${Uri.encodeComponent(url)}';
              });
            }
          }
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _checking = false;
        _frameKey++;
      });
    }
  }

  @override
  void didUpdateWidget(covariant BrowserView old) {
    super.didUpdateWidget(old);
    if (old.url == widget.url) return;
    setState(() => _pageError = null);
    if (kIsWeb) {
      setState(() {
        _push(widget.url);
      });
      _resolve(widget.url);
    } else {
      _ctrl?.loadRequest(Uri.parse(widget.url));
    }
  }

  Future<void> _openExternal() async {
    await launchUrl(Uri.parse(_current), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      if (_webError != null && !_checking) {
        return WolfErrorView(
          url: _current,
          detail: _webError,
          onRetry: () => _resolve(_current),
          onHome: () => widget.onClose?.call(),
        );
      }
      return Column(children: [
        Material(
          elevation: 2,
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _canBack
                  ? () {
                      setState(() => _index--);
                      _resolve(_current);
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: _canForward
                  ? () {
                      setState(() => _index++);
                      _resolve(_current);
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _resolve(_current),
            ),
            if (_checking)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_viaProxy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Tooltip(
                  message: 'Deze site weigert inbedden; hij loopt veilig via de AeroSurf-proxy. Inloggen op zo\'n site kan beperkt werken.',
                  child: Text('⚡ via AeroSurf',
                      style: TextStyle(fontSize: 12, color: Color(0xFF3CFF5C))),
                ),
              ),
            IconButton(icon: const Icon(Icons.open_in_new), onPressed: _openExternal,
                tooltip: 'Extern openen'),
          ]),
        ),
        Expanded(
            child: InternalWebFrame(
                key: ValueKey('$_frameKey-${_embedUrl ?? _current}'),
                url: _embedUrl ?? _current)),
      ]);
    }
    if (BrowserView.isMobileEmbedded) {
      if (_pageError != null) {
        return WolfErrorView(
          url: widget.url,
          detail: _pageError,
          onRetry: () {
            setState(() => _pageError = null);
            _ctrl?.reload();
          },
          onHome: () => widget.onClose?.call(),
        );
      }
      return Column(children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2),
        // Mini-werkbalk: terug/vooruit/verversen + geluid per tabblad
        Material(
          elevation: 1,
          child: Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => _ctrl?.goBack()),
              IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  onPressed: () => _ctrl?.goForward()),
              IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => _ctrl?.reload()),
              const Spacer(),
              IconButton(
                icon: Icon(
                    _muted ? Icons.volume_off : Icons.volume_up,
                    size: 20,
                    color: _muted ? Colors.redAccent : null),
                tooltip: 'Geluid van dit tabblad',
                onPressed: _audioSheet,
              ),
            ],
          ),
        ),
        Expanded(child: WebViewWidget(controller: _ctrl!)),
      ]);
    }
    // Windows: ingebedde Edge WebView2 (echte browser, geen doorverwijzing)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return WindowsBrowserView(key: ValueKey('win-${widget.url}'), url: widget.url);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.open_in_browser, size: 48),
                const SizedBox(height: 12),
                const Text('Deze pagina wordt extern geopend',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(widget.url, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openExternal,
                  icon: const Icon(Icons.launch),
                  label: const Text('Open pagina'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
