import 'package:flutter/material.dart';
import '../../services/recent_service.dart';
import '../app_logo.dart';

class RecentCard extends StatefulWidget {
  final void Function(String url) onOpen;
  const RecentCard({super.key, required this.onOpen});

  @override
  State<RecentCard> createState() => RecentCardState();
}

class RecentCardState extends State<RecentCard> {
  List<RecentItem> _items = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final items = await RecentService.load();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🕘 Recent geopend',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Wissen',
              onPressed: () async {
                await RecentService.clear();
                refresh();
              },
            ),
          ]),
          ..._items.map((e) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.history, size: 18, color: Color(0xFF29B6F6)),
                title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
                onTap: () => widget.onOpen(e.url),
              )),
        ],
      ),
    );
  }
}
