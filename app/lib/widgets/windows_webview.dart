// Alleen op native platforms wordt webview_windows gecompileerd.
// Op Web: lege stub (daar draait het iframe-blad).
export 'browser_view_windows_real.dart'
    if (dart.library.js_interop) 'browser_view_windows_stub.dart';
