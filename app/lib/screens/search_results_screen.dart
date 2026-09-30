import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// AeroSeek-resultatenpagina: lokale links + web, met de AeroNova-AI
/// rechtsonder tussen de resultaten (zoals Gemini bij Google).
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
  final TextEditingController _ctrl = TextEditingController();
  List<dynamic> _suggest = [];

  // AeroNova-chat in dit zoekscherm.
  final _chat = TextEditingController();
  final List<Map<String, String>> _thread = [];
  bool _aiBusy = false;

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
    _chat.dispose();
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
      // AeroNova geeft direct een antwoord bij de zoekopdracht (Gemini-stijl).
      _askNova(q, reset: true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Zoeken mislukt. Probeer opnieuw.')));
      }
    }
  }

  /// Vraag stellen aan AeroNova; antwoord komt bovenaan tussen de resultaten.
  Future<void> _askNova(String vraag, {bool reset = false}) async {
    final q = vraag.trim();
    if (q.isEmpty || _aiBusy) return;
    setState(() {
      _aiBusy = true;
      if (reset) _thread.clear();
      _thread.add({'role': 'user', 'content': q});
    });
    try {
      final history = _thread
          .sublist(0, _thread.length - 1)
          .map((m) => {'role': m['role']!, 'content': m['content']!})
          .toList();
      final reply = await _api.askAi(q, history);
      if (!mounted) return;
      setState(() {
        _thread.add({'role': 'assistant', 'content': reply});
        _aiBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _thread.add({
          'role': 'assistant',
          'content': 'Ik kon nu geen antwoord geven. Controleer de verbinding en probeer opnieuw.',
        });
        _aiBusy = false;
      });
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
          decoration: const InputDecoration(
            hintText: 'Zoek met AeroSeek…',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white54),
            prefixIcon: Icon(Icons.search, color: Colors.white54),
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
        if (_results.isNotEmpty || _local.isNotEmpty || _thread.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'AeroSeek — ${_ctrl.text}',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        // AeroNova-antwoord tussen de resultaten (Google/Gemini-stijl).
        if (_thread.isNotEmpty || _aiBusy) _novaCard(),
        if (_local.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8, top: 16),
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

  /// AeroNova-kaart: antwoord + vervolgvraag (loopt mee met de resultaten).
  Widget _novaCard() {
    final last = _thread.isNotEmpty ? _thread.last : null;
    final isAssistant = last != null && last['role'] == 'assistant';
    return Card(
      color: const Color(0xFF0E1A12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF3CFF5C), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF3CFF5C)),
              const SizedBox(width: 8),
              const Text('AeroNova AI',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              if (_aiBusy)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF3CFF5C))),
            ]),
            const SizedBox(height: 10),
            if (_aiBusy && !isAssistant)
              const Text('AeroNova denkt na…',
                  style: TextStyle(color: Colors.white54)),
            ..._thread.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m['role'] == 'user')
                        const Padding(
                          padding: EdgeInsets.only(right: 8, top: 2),
                          child: Icon(Icons.person, size: 16, color: Colors.white38),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(right: 8, top: 2),
                          child: Icon(Icons.auto_awesome,
                              size: 16, color: Color(0xFF3CFF5C)),
                        ),
                      Expanded(
                        child: Text(
                          m['content'] ?? '',
                          style: TextStyle(
                            color: m['role'] == 'user'
                                ? Colors.white70
                                : Colors.white,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _chat,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) {
                    final t = v.trim();
                    _chat.clear();
                    _askNova(t);
                  },
                  decoration: InputDecoration(
                    hintText: 'Vraag het aan AeroNova…',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, size: 20, color: Color(0xFF3CFF5C)),
                onPressed: () {
                  final t = _chat.text.trim();
                  _chat.clear();
                  _askNova(t);
                },
              ),
            ]),
          ],
        ),
      ),
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