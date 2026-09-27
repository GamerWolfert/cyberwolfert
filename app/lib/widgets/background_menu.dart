import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/sound_service.dart';

/// Menu om achtergrond aan te passen (opgeslagen per gebruiker op de backend).
class BackgroundMenu extends StatefulWidget {
  const BackgroundMenu({super.key});

  static const presetColors = ['#0B1020', '#1A1A2E', '#16213E', '#0F3460', '#E63946', '#2A9D8F'];
  static const presetThemes = ['wolf-dark', 'pulse-red', 'midnight'];

  @override
  State<BackgroundMenu> createState() => _BackgroundMenuState();
}

class _BackgroundMenuState extends State<BackgroundMenu> {
  bool _uploading = false;
  bool _sound = true;

  @override
  void initState() {
    super.initState();
    SoundService.enabled().then((v) {
      if (mounted) setState(() => _sound = v);
    });
  }

  Future<void> _pickAndUpload(SettingsProvider s) async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    setState(() => _uploading = true);
    try {
      try {
        final url = await s.api.uploadImage(img.path, img.name);
        await s.api.saveBackground('Eigen upload', 'image', url, true);
        await s.update(type: 'image', value: url);
      } catch (_) {
        // Backend onbereikbaar: gebruik lokaal pad zodat de UI nooit vastloopt
        try {
          await s.update(type: 'image', value: img.path);
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Backend onbereikbaar: achtergrond alleen op dit apparaat gezet.')));
        }
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    return ListView(
      shrinkWrap: true,
      children: [
        const ListTile(title: Text('Achtergrond aanpassen', style: TextStyle(fontWeight: FontWeight.bold))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Kleuren')),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: BackgroundMenu.presetColors.map((c) => GestureDetector(
              onTap: () => s.update(type: 'color', value: c),
              child: CircleAvatar(
                  backgroundColor: Color(int.parse('FF${c.replaceAll('#', '')}', radix: 16)), radius: 22),
            )).toList(),
          ),
        ),
        ListTile(
          leading: _uploading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.image),
          title: Text(_uploading ? 'Uploaden…' : 'Eigen afbeelding uploaden'),
          onTap: _uploading ? null : () => _pickAndUpload(s),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Thema's")),
        ...BackgroundMenu.presetThemes.map((t) => ListTile(
          leading: const Icon(Icons.palette),
          title: Text(t),
          trailing: s.backgroundValue == t ? const Icon(Icons.check) : null,
          onTap: () => s.update(type: 'theme', value: t),
        )),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.volume_up),
          title: const Text('Startsound'),
          value: _sound,
          onChanged: (v) async {
            await SoundService.setEnabled(v);
            if (!mounted) return;
            setState(() => _sound = v);
          },
        ),
        ListTile(
          leading: const Icon(Icons.audio_file),
          title: const Text('Eigen startsound (mp3)'),
          subtitle: FutureBuilder<String?>(
            future: SoundService.customPath(),
            builder: (ctx, snap) => Text(
              (snap.data != null && snap.data!.isNotEmpty)
                  ? 'Eigen: startsound.mp3'
                  : 'Standaard: yippee',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.upload_file, size: 20),
                tooltip: 'Eigen mp3 kiezen',
                onPressed: () async {
                  final name = await SoundService.pickCustom();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(name == null
                          ? 'Geen bestand gekozen.'
                          : 'Startsound ingesteld: $name')));
                  setState(() {});
                },
              ),
              IconButton(
                icon: const Icon(Icons.restart_alt, size: 20),
                tooltip: 'Terug naar standaard',
                onPressed: () async {
                  await SoundService.clearCustom();
                  if (!mounted) return;
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
