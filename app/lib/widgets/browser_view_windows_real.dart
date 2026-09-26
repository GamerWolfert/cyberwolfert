import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

/// Echte ingebedde browser op Windows via Edge WebView2.
/// Alleen gecompileerd/gebruikt op Windows (zie windows_webview.dart).
class WindowsBrowserView extends StatefulWidget {
  final String url;
  const WindowsBrowserView({super.key, required this.url});

  @override
  State<WindowsBrowserView> createState() => _WindowsBrowserViewState();
}

class _WindowsBrowserViewState extends State<WindowsBrowserView> {
  final WebviewController _ctrl = WebviewController();
  bool _ready = false;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _current = widget.url;
    _ctrl.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _ctrl.loadUrl(widget.url);
    });
    _ctrl.url.listen((url) {
      if (mounted && url.isNotEmpty) setState(() => _current = url);
    });
  }

  @override
  void didUpdateWidget(covariant WindowsBrowserView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url && _ready) {
      _ctrl.loadUrl(widget.url);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
