import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/api_service.dart';
import 'browser_handle.dart';
import 'wolf_error.dart';

/// Echte ingebedde browser op Windows via Edge WebView2.
/// Checkt vooraf bereikbaarheid; bij dode sites onze eigen errorpagina
/// (nooit Edge-teksten).
class WindowsBrowserView extends StatefulWidget {
  final String url;
  final BrowserHandle? handle;
  const WindowsBrowserView(
      {super.key, required this.url, this.handle});

  @override
  State<WindowsBrowserView> createState() => _WindowsBrowserViewState();
}

class _WindowsBrowserViewState extends State<WindowsBrowserView> {
  final WebviewController _ctrl = WebviewController();
  final ApiService _api = ApiService();
  bool _ready = false;
  bool _dead = false;
  String? _errDetail; // laadfout van WebView2 -> onze eigen tekst
  String _current = '';
  // Audio per tabblad (via JS in de pagina, net als mobiel)
  bool _muted = false;
  double _volume = 1.0;

  /// WebView2-status vertalen naar AeroSurf-taal (nooit Edge-teksten).
  static String _fout(WebErrorStatus s) {
    switch (s) {
      case WebErrorStatus.WebErrorStatusHostNameNotResolved:
        return 'Domein niet gevonden — controleer de spelling van het adres.';
      case WebErrorStatus.WebErrorStatusTimeout:
        return 'Deze site reageert niet (timeout). Probeer het later nog eens.';
      case WebErrorStatus.WebErrorStatusCertificateExpired:
      case WebErrorStatus.WebErrorStatusCertificateIsInvalid:
      case WebErrorStatus.WebErrorStatusCertificateCommonNameIsIncorrect:
      case WebErrorStatus.WebErrorStatusCertificateRevoked:
      case WebErrorStatus.WebErrorStatusClientCertificateContainsErrors:
        return 'De beveiligde verbinding (SSL) van deze site klopt niet.';
      case WebErrorStatus.WebErrorStatusValidAuthenticationCredentialsRequired:
      case WebErrorStatus.WebErrorStatusValidProxyAuthenticationRequired:
        return 'Deze site vraagt om inloggen en weigert het verzoek.';
      case WebErrorStatus.WebErrorStatusCannotConnect:
      case WebErrorStatus.WebErrorStatusServerUnreachable:
      case WebErrorStatus.WebErrorStatusConnectionAborted:
      case WebErrorStatus.WebErrorStatusConnectionReset:
      case WebErrorStatus.WebErrorStatusDisconnected:
        return 'Verbinding met deze site mislukt — hij is nu niet bereikbaar.';
      case WebErrorStatus.WebErrorStatusErrorHTTPInvalidServerResponse:
        return 'Deze site geeft een ongeldig antwoord (HTTP-fout).';
      default:
        return 'Deze pagina is niet bereikbaar. Controleer het adres of je verbinding.';
    }
  }

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
    // Laadfouten: Eigen foutpagina i.p.v. het standaard Edge-plaatje.
    // Volgorde in WebView2: eerst onLoadError, daarna navigationCompleted —
    // dus alleen wissen zodra er een NIEUWE navigatie start.
    _ctrl.onLoadError.listen((status) {
      if (!mounted) return;
      setState(() => _errDetail = _fout(status));
    });
    _ctrl.loadingState.listen((state) {
      if (!mounted) return;
      if (state == LoadingState.loading && _errDetail != null) {
        setState(() => _errDetail = null);
      }
    });
    _ctrl.url.listen((url) {
      if (mounted && url.isNotEmpty) {
        setState(() => _current = url);
        _applyAudio();
      }
    });
    widget.handle?.back = () => _ctrl.goBack();
    widget.handle?.forward = () => _ctrl.goForward();
    widget.handle?.reload = () => _ctrl.reload();
  }

  @override
  void dispose() {
    widget.handle?.clear();
    _ctrl.dispose();
    super.dispose();
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
    final info = await _api.frameInfo(url);
    if (!mounted) return;
    final mode = info?['framing']?.toString();
    if (mode == 'na') {
      // Backend zegt: onbereikbaar / ongeldig -> eigen pagina met reden
      setState(() {
        _dead = true;
        _errDetail = info?['reason']?.toString() ?? 'Dit adres lijkt niet te bestaan.';
      });
    } else {
      setState(() => _dead = false);
    }
  }

  @override
  void didUpdateWidget(covariant WindowsBrowserView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      setState(() {
        _dead = false;
        _errDetail = null;
      });
      if (_ready) _ctrl.loadUrl(widget.url);
      _check(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dead || _errDetail != null) {
      return WolfErrorView(
        url: widget.url,
        detail: _errDetail ?? 'Dit adres lijkt niet te bestaan.',
        onRetry: () {
          setState(() {
            _dead = false;
            _errDetail = null;
          });
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
