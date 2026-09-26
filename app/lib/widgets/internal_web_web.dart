import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

/// Iframe-blad voor Web: pagina's BINNEN CyberWolfert (met eigen navigatiestack).
class InternalWebFrame extends StatefulWidget {
  final String url;
  const InternalWebFrame({super.key, required this.url});

  @override
  State<InternalWebFrame> createState() => _InternalWebFrameState();
}

class _InternalWebFrameState extends State<InternalWebFrame> {
  late final web.HTMLIFrameElement _iframe;
  late final String _viewType;
  static int _counter = 0;

  @override
  void initState() {
    super.initState();
    _iframe = web.HTMLIFrameElement()
      ..src = widget.url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allowFullscreen = true;
    _iframe.setAttribute('sandbox',
        'allow-scripts allow-same-origin allow-forms allow-modals allow-popups-to-escape-sandbox');
    _viewType = 'cyberwolf-iframe-${_counter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _iframe);
  }

  @override
  void didUpdateWidget(covariant InternalWebFrame old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _iframe.src = widget.url;
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
