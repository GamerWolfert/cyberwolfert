/// Stuurman voor de browser-werkbalk: de knoppen buiten de WebView
/// (terug/vooruit/verversen) bedienen de actieve pagina hiermee.
///
/// Elk tabblad heeft één exemplaar; de BrowserView (mobiel/web/Windows)
/// vult de callbacks zodra die gemonteerd is.
class BrowserHandle {
  void Function()? back;
  void Function()? forward;
  void Function()? reload;

  void clear() {
    back = null;
    forward = null;
    reload = null;
  }
}
