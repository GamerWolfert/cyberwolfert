import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

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

  Future<void> _pickAndUpload(SettingsProvider s) async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    setState(() => _uploading = true);
    try {
      final url = await s.api.uploadImage(img.path, img.name);
      await s.api.saveBackground('Eigen upload', 'image', url, true);
      await s.update(type: 'image', value: url);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      await s.update(type: 'image', value: img.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload mislukt, lokaal gebruikt.')));
        Navigator.pop(context);
      }
    }
    setState(() => _uploading = false);
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
      ],
    );
  }
}
