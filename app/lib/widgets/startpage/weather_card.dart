import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/weather_service.dart';
import '../app_logo.dart';

/// Weer-kaart: live locatie (toestemming-flow) of handmatige stad.
class WeatherCard extends StatefulWidget {
  const WeatherCard({super.key});

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  String _mode = 'live';
  City _city = City.presets.first;
  String _placeLabel = '';
  Weather? _weather;
  bool _busy = true;
  String? _denied;
  StreamSubscription<Position>? _sub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _mode = await WeatherService.savedMode();
    if (_mode == 'live') {
      await _startLive(first: true);
    } else {
      final name = await WeatherService.savedCity();
      _city = City.byName(name);
      final w = await WeatherService.fetch(_city);
      if (mounted) {
        setState(() {
          _weather = w;
          _busy = false;
        });
      }
    }
  }

  Future<void> _startLive({bool first = false}) async {
    if (!first && mounted) setState(() => _busy = true);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      if (mounted) {
        setState(() {
          _busy = false;
          _denied = 'Geen locatie beschikbaar: er is geen toestemming gegeven.';
        });
      }
      return;
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _busy = false;
          _denied = 'Geen locatie beschikbaar: toestemming is permanent geweigerd. Zet hem aan in de instellingen of kies handmatig.';
        });
      }
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
      await _updateFor(pos);
      await _sub?.cancel();
      _sub = Geolocator.getPositionStream(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low, distanceFilter: 500),
      ).listen(_updateFor);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _denied = 'Locatie ophalen mislukt. Probeer opnieuw of kies handmatig.';
        });
      }
    }
  }

  Future<void> _updateFor(Position pos) async {
    final results = await Future.wait([
      WeatherService.fetchByCoords(pos.latitude, pos.longitude),
      WeatherService.placeName(pos.latitude, pos.longitude),
    ]);
    if (mounted) {
      setState(() {
        _weather = results[0] as Weather?;
        _placeLabel = results[1] as String;
        _busy = false;
        _denied = null;
      });
    }
  }

  Future<void> _toManual(City c) async {
    await _sub?.cancel();
    await WeatherService.saveMode('manual');
    await WeatherService.saveCity(c.name);
    if (mounted) setState(() => _busy = true);
    final w = await WeatherService.fetch(c);
    if (mounted) {
      setState(() {
        _mode = 'manual';
        _city = c;
        _weather = w;
        _busy = false;
        _denied = null;
      });
    }
  }

  Future<void> _toLive() async {
    await WeatherService.saveMode('live');
    if (mounted) setState(() => _mode = 'live');
    await _startLive();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_mode == 'live' ? Icons.my_location : Icons.list,
                size: 14, color: Colors.white54),
            const SizedBox(width: 6),
            Text(_mode == 'live' ? 'Live locatie' : 'Handmatig',
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: 'Weerbron',
              icon: const Icon(Icons.expand_more, size: 18, color: Colors.white70),
              onSelected: (v) async {
                if (v == '__live__') {
                  await _toLive();
                } else {
                  await _toManual(City.byName(v));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: '__live__', child: Text('📍 Live locatie')),
                ...City.presets.map((c) => PopupMenuItem(
                    value: c.name, child: Text('${c.name} (${c.country})'))),
              ],
            ),
          ]),
          const SizedBox(height: 4),
          if (_busy)
            const SizedBox(
                height: 64, child: Center(child: CircularProgressIndicator()))
          else if (_denied != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_denied!,
                    style: const TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _startLive,
                  icon: const Icon(Icons.location_on, size: 16),
                  label: const Text('Geef toestemming'),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(children: [
                    Icon(_weather?.icoon ?? Icons.cloud,
                        size: 40, color: const Color(0xFF29B6F6)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _weather == null
                                    ? '—'
                                    : '${_weather!.temp.toStringAsFixed(0)}°C',
                                style: const TextStyle(
                                    fontSize: 30, fontWeight: FontWeight.w800)),
                            Text(_weather?.beschrijving ?? 'Geen weerdata',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.white70)),
                          ]),
                    ),
                  ]),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(children: [
                      const Icon(Icons.location_on,
                          size: 14, color: Colors.white54),
                      Flexible(
                        child: Text(
                            _mode == 'live' ? _placeLabel : _city.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ]),
                    if (_mode == 'manual')
                      Text(_city.country,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54)),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}
