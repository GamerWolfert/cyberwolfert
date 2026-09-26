import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'internal_web.dart';

/// Echte CyberWolfert-browser:
/// - Android/iOS/macOS: ingebedde WebView
/// - Web: intern iframe-blad (direct of via proxy bij framing-blokkade)
/// - Windows/Linux: systeem-browser
class BrowserView extends StatefulWidget {
  final String url;
  final void Function()? onClose;
  const BrowserView({super.key, required this.url, this.onClose});

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

  final List<String> _stack = [];
  int _index = -1;
  int _frameKey = 0;
  String? _embedUrl;
  bool _checking = false;
  bool _viaProxy = false;

  String get _current => (_index >= 0 && _index < _stack.length) ? _stack[_index] : widget.url;
  bool get _canBack => _index > 0;
  bool get _canForward => _index >= 0 && _index < _stack.length - 1;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _push(widget.url);
      _resolve(widget.url);
    } else if (BrowserView.isMobileEmbedded) {
      _ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
        ))
        ..loadRequest(Uri.parse(widget.url));
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
      _embedUrl = url;
    });
    try {
      final origin = Uri.base.origin;
      final r = await http
          .get(Uri.parse(
              '$origin/api/frame-check?url=${Uri.encodeComponent(url)}'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['framing'] == 'blocked') {
          if (mounted) {
            setState(() {
              _viaProxy = true;
              _embedUrl =
                  '$origin/api/proxy?url=${Uri.encodeComponent(url)}';
            });
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
                  message: 'Deze site weigert inbedden; hij loopt veilig via de CyberWolfert-proxy. Inloggen op zo\'n site kan beperkt werken.',
                  child: Text('⚡ via CyberWolfert',
                      style: TextStyle(fontSize: 12, color: Color(0xFF29B6F6))),
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
      return Column(children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2),
        Expanded(child: WebViewWidget(controller: _ctrl!)),
      ]);
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
