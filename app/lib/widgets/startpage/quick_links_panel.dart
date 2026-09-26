import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../services/quicklinks_service.dart';
import '../app_logo.dart';

class BrandIcon extends StatelessWidget {
  final QuickLink link;
  final double size;
  const BrandIcon({super.key, required this.link, this.size = 22});

  @override
  Widget build(BuildContext context) {
    if (link.svg == null) {
      return Text(link.emoji, style: TextStyle(fontSize: size));
    }
    return SvgPicture.asset(
      link.svg!,
      width: size,
      height: size,
      placeholderBuilder: (_) =>
          Text(link.emoji, style: TextStyle(fontSize: size)),
    );
  }
}

class QuickLinksPanel extends StatefulWidget {
  final void Function(String url) onOpen;
  const QuickLinksPanel({super.key, required this.onOpen});

  @override
  State<QuickLinksPanel> createState() => _QuickLinksPanelState();
}

class _QuickLinksPanelState extends State<QuickLinksPanel> {
  List<QuickLink> _links = [];

  @override
  void initState() {
    super.initState();
    QuickLinksService.load().then((l) {
      if (mounted) setState(() => _links = l);
    });
  }

  Future<void> _save() => QuickLinksService.save(_links);

  Future<void> _addDialog() async {
    final naam = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Link toevoegen'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: naam, decoration: const InputDecoration(labelText: 'Naam')),
          TextField(controller: url, decoration: const InputDecoration(labelText: 'URL (bv. voorbeeld.nl)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Toevoegen')),
        ],
      ),
    );
    if (ok == true && naam.text.trim().isNotEmpty && url.text.trim().isNotEmpty) {
      var u = url.text.trim();
      if (!u.startsWith('http')) u = 'https://$u';
      setState(() => _links.add(QuickLink(naam.text.trim(), u, '🔗')));
      await _save();
    }
  }

  Future<void> _remove(QuickLink l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('"${l.naam}" verwijderen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Behouden')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Verwijderen')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _links.remove(l));
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('⚡ Snelle links',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: 'Link toevoegen',
              onPressed: _addDialog,
            ),
          ]),
          const SizedBox(height: 4),
          ..._links.map((l) => InkWell(
                onTap: () => widget.onOpen(l.url),
                onLongPress: () => _remove(l),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    BrandIcon(link: l, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.naam)),
                    const Icon(Icons.arrow_forward, size: 16, color: Color(0xFF29B6F6)),
                  ]),
                ),
              )),
        ],
      ),
    );
  }
}

class QuickTiles extends StatelessWidget {
  final List<QuickLink> links;
  final void Function(String url) onOpen;
  const QuickTiles({super.key, required this.links, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final shown = links.take(6).toList();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: shown
          .map((l) => InkWell(
                onTap: () => onOpen(l.url),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 86,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1428).withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFF29B6F6).withValues(alpha: 0.25)),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    BrandIcon(link: l, size: 28),
                    const SizedBox(height: 6),
                    Text(l.naam,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ))
          .toList(),
    );
  }
}
