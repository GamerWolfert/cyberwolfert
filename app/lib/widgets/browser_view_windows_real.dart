import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/api_service.dart';
import 'wolf_error.dart';

/// Echte ingebedde browser op Windows via Edge WebView2.
/// Checkt vooraf bereikbaarheid; bij dode sites onze eigen errorpagina
/// (nooit Edge-teksten).
class WindowsBrowserView extends StatefulWidget {
  final String url;
  const WindowsBrowserView({super.key, required this.url});

  @override
  State<WindowsBrowserView> createState() => _WindowsBrowserViewState();
}

class _WindowsBrowserViewState extends State<WindowsBrowserView> {
  final WebviewController _ctrl = WebviewController();
  final ApiService _api = ApiService();
  bool _ready = false;
  bool _dead = false;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _current = widget.url;
    _check(widget.url);
    _ctrl.initialize().then((_) {
      if (!mounted || _dead) return;
      setState(() => _ready = true);
      _ctrl.loadUrl(widget.url);
    });
    _ctrl.url.listen((url) {
      if (mounted && url.isNotEmpty) setState(() => _current = url);
    });
  }

  Future<void> _check(String url) async {
    final mode = await _api.frameCheck(url);
    if (!mounted) return;
    if (mode == 'na') {
      // Backend zegt: domein bestaat niet / onbereikbaar -> eigen pagina
      final reachable = await _api.health();
      if (reachable) setState(() => _dead = true);
    }
  }

  @override
  void didUpdateWidget(covariant WindowsBrowserView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      setState(() => _dead = false);
      if (_ready) _ctrl.loadUrl(widget.url);
      _check(widget.url);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dead) {
      return WolfErrorView(
        url: widget.url,
        detail: 'Dit adres lijkt niet te bestaan.',
        onRetry: () {
          setState(() => _dead = false);
          _check(widget.url);
          if (_ready) _ctrl.loadUrl(widget.url);
        },
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Material(
          elevation: 2,
          child: Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _ctrl.goBack()),
              IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _ctrl.goForward()),
              IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _ctrl.reload()),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_current,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: Webview(_ctrl)),
      ],
    );
  }
}
