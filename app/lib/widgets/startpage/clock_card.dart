import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/tz.dart';
import '../app_logo.dart';

/// Klok-kaart: echte systeemtijd, live. Default Europe/Amsterdam, kiesbaar.
class ClockCard extends StatefulWidget {
  const ClockCard({super.key});

  @override
  State<ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<ClockCard> {
  TzZone _zone = TzZone.amsterdam;
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = _zone.now());
    });
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final zone = TzZone.byId(p.getString('tz_zone'));
    if (mounted) {
      setState(() {
        _zone = zone;
        _now = zone.now();
      });
    }
  }

  Future<void> _pick(TzZone z) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tz_zone', z.id);
    setState(() {
      _zone = z;
      _now = z.now();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(TzZone.hhmm(_now),
                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
                ),
                Text(TzZone.datumLang(_now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.white70)),
              ],
            ),
          ),
          PopupMenuButton<TzZone>(
            tooltip: 'Tijdzone',
            icon: const Icon(Icons.public, color: Colors.white70),
            onSelected: _pick,
            itemBuilder: (_) => TzZone.zones
                .map((z) => PopupMenuItem(
                      value: z,
                      child: Row(children: [
                        if (z.id == _zone.id)
                          const Icon(Icons.check, size: 16),
                        if (z.id == _zone.id) const SizedBox(width: 6),
                        Text(z.label),
                      ]),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
