// Stub voor niet-Web platforms zonder webview_windows.
import 'package:flutter/material.dart';

class WindowsBrowserView extends StatelessWidget {
  final String url;
  const WindowsBrowserView({super.key, required this.url});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
