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
  // Audio per tabblad (via JS in de pagina, net als mobiel)
  bool _muted = false;
  double _volume = 1.0;

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
      if (mounted && url.isNotEmpty) {
        setState(() => _current = url);
        _applyAudio();
      }
    });
  }

  Future<void> _applyAudio() async {
    try {
      await _ctrl.executeScript(
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
              IconButton(
                icon: Icon(
                    _muted ? Icons.volume_off : Icons.volume_up,
                    size: 20,
                    color: _muted ? Colors.redAccent : null),
                tooltip: 'Geluid van dit tabblad',
                onPressed: _audioSheet,
              ),
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
