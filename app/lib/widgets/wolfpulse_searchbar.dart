import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';

/// WolfPulse-zoekbalk met blauwe gloed. Codewoord "download" -> apps-zip.
class WolfPulseSearchBar extends StatefulWidget {
  final void Function(String url) onOpenUrl;
  final bool showTitle;
  const WolfPulseSearchBar({super.key, required this.onOpenUrl, this.showTitle = true});

  @override
  State<WolfPulseSearchBar> createState() => _WolfPulseSearchBarState();
}

class _WolfPulseSearchBarState extends State<WolfPulseSearchBar> {
  final _ctrl = TextEditingController();
  final _api = ApiService();
  bool _busy = false;
  List<dynamic> _results = [];
  List<dynamic> _local = [];

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    if (q.toLowerCase() == 'download') {
      setState(() => _busy = true);
      try {
        final url = await UpdateService.bundleUrl();
        if (url != null && mounted) {
          await UpdateService.openUrl(url);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('🐺 CyberWolfert-apps.zip wordt gedownload…')));
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nog geen downloadbundle beschikbaar.')));
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Downloaden is mislukt. Probeer het opnieuw.')));
        }
      }
      setState(() => _busy = false);
      return;
    }
    setState(() => _busy = true);
    try {
      final j = await _api.search(q);
      setState(() {
        _results = (j['results'] ?? []) as List<dynamic>;
        _local = (j['local'] ?? []) as List<dynamic>;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Zoeken is mislukt. Controleer de verbinding.')));
      }
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTitle) ...[
          const Text('🐺 WolfPulse', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x5529B6F6), blurRadius: 18, spreadRadius: 1),
                  ],
                ),
                child: TextField(
                  controller: _ctrl,
                  onSubmitted: (_) => _search(),
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Zoek wereldwijd via WolfPulse…',
                    filled: true,
                    fillColor: const Color(0xFF0A1428).withValues(alpha: 0.9),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: const BorderSide(
                          color: Color(0xFF29B6F6), width: 1.2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide(
                          color: const Color(0xFF29B6F6).withValues(alpha: 0.6),
                          width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: const BorderSide(
                          color: Color(0xFF29B6F6), width: 2),
                    ),
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFF29B6F6)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _busy
                ? const CircularProgressIndicator()
                : FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF29B6F6),
                      foregroundColor: const Color(0xFF061224),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: _search,
                    child: const Text('Zoek',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
          ],
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final r = _results[i] as Map<String, dynamic>;
                final isLocal = i < _local.length;
                return ListTile(
                  dense: true,
                  leading: Icon(isLocal ? Icons.star : Icons.public,
                      color: isLocal ? Colors.amber : Colors.grey),
                  title: Text(r['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(r['snippet']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => widget.onOpenUrl(r['url'].toString()),
                );
              },
            ),
          ),
      ],
    );
  }
}
