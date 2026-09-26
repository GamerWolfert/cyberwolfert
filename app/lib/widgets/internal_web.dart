// Conditional import: alleen op Web wordt de echte iframe-view gecompileerd.
export 'internal_web_stub.dart' if (dart.library.js_interop) 'internal_web_web.dart';
