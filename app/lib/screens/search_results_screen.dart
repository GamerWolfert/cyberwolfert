import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Google-like search results page for AeroSeek
class SearchResultsScreen extends StatefulWidget {
  final String query;
  final void Function(String url) onOpenUrl;

  const SearchResultsScreen({
    super.key,
    required this.query,
    required this.onOpenUrl,
  });

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  final _api = ApiService();
  List<dynamic> _results = [];
  List<dynamic> _local = [];
  bool _busy = true;
  Timer? _debounce;
  TextEditingController _ctrl = TextEditingController();
  List<dynamic> _suggest = [];

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.query;
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _suggest = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final j = await _api.search(q);
        if (!mounted) return;
        setState(() {
          _suggest = ((j['results'] ?? []) as List<dynamic>).take(6).toList();
        });
      } catch (_) {}
    });
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _busy = true);
    try {
      final j = await _api.search(q);
      if (!mounted) return;
      setState(() {
        _results = (j['results'] ?? []) as List<dynamic>;
        _local = (j['local'] ?? []) as List<dynamic>;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zoeken mislukt. Probeer opnieuw.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          onSubmitted: (_) => _search(),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Zoek met AeroSeek…',
            border: InputBorder.none,
            hintStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 18),
          onChanged: (_) => _onChanged(_ctrl.text),
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white),
              tooltip: 'Wissen',
              onPressed: () {
                _ctrl.clear();
                setState(() {
                  _results = [];
                  _local = [];
                  _suggest = [];
                });
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_busy && _results.isEmpty && _local.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_results.isNotEmpty || _local.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              '🚀 AeroSeek — ${_ctrl.text}',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        if (_local.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '⭐ Lokale prioriteitslinks',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.amber,
              ),
            ),
          ),
          ..._local.map((r) =>
              _buildResultTile(Map<String, dynamic>.from(r as Map), true)),
        ],
        if (_results.isNotEmpty) ...[
          if (_local.isNotEmpty) const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '🌍 Webresultaten',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),
          ..._results.map((r) =>
              _buildResultTile(Map<String, dynamic>.from(r as Map), false)),
        ],
        if (_suggest.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '💡 Suggesties',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
              ),
            ),
          ),
          ..._suggest.map((r) => ListTile(
                dense: true,
                leading: const Icon(Icons.search, size: 18),
                title: Text('${r is Map ? (r['title'] ?? r['query'] ?? '') : r}'),
                onTap: () {
                  _ctrl.text = '${r is Map ? (r['title'] ?? r['query'] ?? '') : r}';
                  _search();
                },
              )),
        ],
        if (_results.isEmpty && _local.isEmpty && !_busy)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(Icons.search_off,
                      size: 64, color: Colors.white38),
                  const SizedBox(height: 16),
                  Text(
                    'Geen resultaten voor "${_ctrl.text}"',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Probeer andere zoektermen of controleer de verbinding.',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResultTile(Map<String, dynamic> r, bool isLocal) {
    final title = (r['title'] ?? '').toString();
    final url = (r['url'] ?? '').toString();
    final snippet = (r['snippet'] ?? '').toString();

    return Card(
      child: ListTile(
        leading: Icon(
          isLocal ? Icons.star : Icons.public,
          color: isLocal ? Colors.amber : const Color(0xFF3CFF5C),
          size: 22,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          snippet.isEmpty ? url : snippet,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.white60),
        ),
        trailing: const Icon(Icons.chevron_right,
            color: Colors.white38, size: 20),
        onTap: () {
          widget.onOpenUrl(url);
          Navigator.of(context).maybePop();
        },
      ),
    );
  }
}