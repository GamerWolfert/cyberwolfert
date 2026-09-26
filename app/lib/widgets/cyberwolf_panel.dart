import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import 'made_by.dart';

/// CyberWolf AI-zijpaneel: tekst + afbeeldingen, groene eigen ballonnen.
class _ChatMsg {
  final String role;
  final String text;
  final Uint8List? image;
  const _ChatMsg(this.role, this.text, [this.image]);
}

class CyberWolfPanel extends StatefulWidget {
  const CyberWolfPanel({super.key});

  @override
  State<CyberWolfPanel> createState() => _CyberWolfPanelState();
}

class _CyberWolfPanelState extends State<CyberWolfPanel> {
  final _ctrl = TextEditingController();
  final _api = ApiService();
  final List<_ChatMsg> _msgs = const [
    _ChatMsg('assistant', 'Hoi! Ik ben CyberWolf AI 🐺. Waar kan ik je mee helpen?')
  ].toList();
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
    } catch (_) {
      setState(() {
        _online = false;
        _msgs.add(const _ChatMsg('assistant',
            'CyberWolf AI is offline. Controleer of de backend draait en probeer het opnieuw.'));
      });
    }
    setState(() => _busy = false);
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
                        Text(m.text),
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
