import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import 'made_by.dart';

/// CyberWolf AI-zijpaneel: tekst + afbeeldingen, groene eigen ballonnen.
class _ChatMsg {
  String role;
  String text;
  Uint8List? image;
  _ChatMsg(this.role, this.text, [this.image]);
}

class CyberWolfPanel extends StatefulWidget {
  const CyberWolfPanel({super.key});

  @override
  State<CyberWolfPanel> createState() => _CyberWolfPanelState();
}

class _CyberWolfPanelState extends State<CyberWolfPanel> {
  final _ctrl = TextEditingController();
  final _api = ApiService();
  final _scroll = ScrollController();
  final List<_ChatMsg> _msgs = [
    _ChatMsg('assistant', 'Hoi! Ik ben CyberWolf AI 🐺. Waar kan ik je mee helpen?\n\n- Vraag om code of uitleg\n- Typ **voer uit:** + je doel, dan maak ik een plan voor de Mini-PC en vraag ik toestemming')
  ];
  bool _busy = false;
  bool? _online;
  Uint8List? _pendingImage;
  String? _pendingImagePath;

  @override
  void initState() {
    super.initState();
    _api.health().then((ok) {
      if (mounted) setState(() => _online = ok);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  Future<void> _attach() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    setState(() {
      _pendingImage = bytes;
      _pendingImagePath = img.path;
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if ((text.isEmpty && _pendingImage == null) || _busy) return;
    _ctrl.clear();
    final imgBytes = _pendingImage;
    final imgPath = _pendingImagePath;
    setState(() {
      _msgs.add(_ChatMsg('user', text.isEmpty ? '🖼️ [afbeelding]' : text, imgBytes));
      _busy = true;
      _pendingImage = null;
      _pendingImagePath = null;
    });
    _toBottom();
    if (imgBytes == null && _isAgentAsk(text)) {
      await _agent(text);
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final history = _msgs
          .where((m) => m.image == null)
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();
      final reply = (imgBytes != null && imgPath != null)
          ? await _api.askAiWithImage(
              text.isEmpty ? 'Beschrijf deze afbeelding.' : text,
              history,
              imgPath)
          : await _api.askAi(text, history);
      setState(() {
        _online = true;
        _msgs.add(_ChatMsg('assistant', reply));
      });
      _toBottom();
    } catch (_) {
      setState(() {
        _online = false;
        _msgs.add(_ChatMsg('assistant',
            'CyberWolf AI is offline. Controleer of de backend draait en probeer het opnieuw.'));
      });
    }
    setState(() => _busy = false);
  }

  // ---------- Remote agent: plan -> toestemming -> uitvoeren op de Mini-PC ----------

  bool _isAgentAsk(String t) {
    final s = t.toLowerCase().trim();
    if (s.startsWith('agent:') || s.startsWith('agent ')) return true;
    if (s.startsWith('voer uit')) return true;
    return RegExp(r'(voer\s+uit|uitvoer(en|ing)|remote\s+agent|op\s+(de|mijn)\s+(mini[\s-]?pc|apparaat|computer)|mini[\s-]?pc\s+(uitvoeren|draaien|doen))')
        .hasMatch(s);
  }

  String _fout(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  String _stepsMd(dynamic plan) {
    final steps = (plan is Map && plan['steps'] is List) ? plan['steps'] as List : const [];
    if (steps.isEmpty) return '';
    final b = StringBuffer();
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      if (s is! Map) continue;
      if (s['type'] == 'file') {
        b.writeln('${i + 1}. 📄 schrijf `${s['path']}`');
      } else {
        b.writeln('${i + 1}. ▶️ `${s['cmd']}`');
      }
    }
    return b.toString();
  }

  String _runMd(Map<String, dynamic> run) {
    final b = StringBuffer();
    b.writeln(run['ok'] == true
        ? '✅ **Plan uitgevoerd**'
        : '⚠️ **Plan deels uitgevoerd**');
    for (final r in (run['results'] is List ? run['results'] as List : const [])) {
      if (r is! Map) continue;
      final ok = r['ok'] == true;
      final label = r['type'] == 'file'
          ? '📄 `${r['path']}`'
          : '▶️ `${r['cmd'] ?? ''}`';
      b.writeln('${ok ? "✅" : "❌"} **stap ${r['step']}** $label');
      final out = (r['out'] ?? '').toString().trim();
      if (out.isNotEmpty) {
        b.writeln('```');
        b.writeln(out.length > 1500 ? '${out.substring(0, 1500)}…' : out);
        b.writeln('```');
      }
      final err = (r['err'] ?? '').toString().trim();
      if (err.isNotEmpty && !ok) {
        b.writeln('> ❌ ${err.split('\n').take(3).join('\n> ')}');
      }
    }
    final wd = run['workdir']?.toString();
    if (wd != null && wd.isNotEmpty) b.writeln('\nWerkmap: `$wd`');
    return b.toString();
  }

  Future<bool> _askPermission(Map<String, dynamic> plan) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.shield_outlined, color: Colors.amber),
          SizedBox(width: 8),
          Text('Toestemming nodig'),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${plan['summary'] ?? 'Plan'}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('De Mini-PC gaat dit nu doen:',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
              const SizedBox(height: 6),
              MarkdownBody(data: _stepsMd(plan), selectable: true),
              const SizedBox(height: 10),
              Text('Werkmap: ${plan['workdir'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white54, fontFamily: 'monospace')),
              const SizedBox(height: 6),
              const Text('Alleen dit plan wordt uitgevoerd. Het plan vervalt na 10 minuten.',
                  style: TextStyle(fontSize: 11, color: Colors.white60)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Afwijzen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Toestaan'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _agent(String goal) async {
    final ph = _ChatMsg('assistant', '🧠 Ik maak een plan…');
    setState(() => _msgs.add(ph));
    _toBottom();
    Map<String, dynamic> plan;
    try {
      plan = await _api.agentPlan(goal);
    } catch (e) {
      setState(() {
        _online = false;
        ph.text = '⚠️ **Plan mislukt** — ${_fout(e)}';
      });
      return;
    }
    if (!mounted) return;
    final base = StringBuffer()
      ..writeln('**Plan klaar:** ${plan['summary'] ?? ''}')
      ..writeln()
      ..write(_stepsMd(plan))
      ..writeln()
      ..writeln('_Werkmap: `${plan['workdir'] ?? ""}`_');
    setState(() => ph.text = base.toString());
    _toBottom();

    final go = await _askPermission(plan);
    if (!go) {
      setState(() => ph.text = '${base.toString()}\n\n❌ **Afgewezen** — er is niets uitgevoerd.');
      return;
    }
    final tick = '${base.toString()}\n\n⏳ **Ik voer het plan uit op de Mini-PC…**';
    setState(() => ph.text = tick);
    try {
      final run = await _api.agentRun(plan['id'].toString());
      setState(() {
        _online = true;
        ph.text = '${base.toString()}\n\n${_runMd(run)}';
      });
    } catch (e) {
      setState(() {
        ph.text = '${base.toString()}\n\n⚠️ **Uitvoeren mislukt** — ${_fout(e)}';
      });
    }
    _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            leading: ClipOval(
              child: Image.asset(
                'assets/logo.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const CircleAvatar(child: Text('🐺')),
              ),
            ),
            title: const Text(AppConfig.aiName,
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _online == null
                        ? Colors.grey
                        : (_online! ? Colors.greenAccent : Colors.redAccent),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_online == null
                    ? 'Verbinden…'
                    : (_online! ? 'Verbonden' : 'Offline')),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _msgs.length,
              itemBuilder: (ctx, i) {
                final m = _msgs[i];
                final me = m.role == 'user';
                return Align(
                  alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(ctx).size.width * 0.7),
                    decoration: BoxDecoration(
                      color: me
                          ? Colors.green.shade700
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (m.image != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(m.image!,
                                width: 180, fit: BoxFit.cover),
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (me)
                          Text(m.text)
                        else
                          MarkdownBody(
                            data: m.text,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet.fromTheme(
                                    Theme.of(ctx))
                                .copyWith(
                              p: const TextStyle(
                                  fontSize: 14, height: 1.35, color: Colors.white),
                              code: const TextStyle(
                                  fontSize: 12,
                                  backgroundColor: Colors.black54,
                                  color: Colors.greenAccent),
                              codeblockDecoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(6)),
                              blockquote: const TextStyle(color: Colors.white70),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_pendingImage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_pendingImage!,
                      width: 64, height: 64, fit: BoxFit.cover),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _pendingImage = null;
                    _pendingImagePath = null;
                  }),
                ),
                const Text('Afbeelding klaar om te sturen',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  tooltip: 'Afbeelding toevoegen',
                  onPressed: _busy ? null : _attach,
                ),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                        hintText: 'Vraag CyberWolf AI…',
                        border: OutlineInputBorder()),
                  ),
                ),
                IconButton(onPressed: _send, icon: const Icon(Icons.send)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: MadeBy(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
