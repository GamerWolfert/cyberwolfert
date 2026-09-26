import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Echt weer via Open-Meteo (gratis, geen key). Live locatie of handmatige stad.
class City {
  final String name;
  final String country;
  final double lat;
  final double lon;
  const City(this.name, this.country, this.lat, this.lon);

  static const List<City> presets = [
    City('Amsterdam', 'Nederland', 52.37, 4.90),
    City('Rotterdam', 'Nederland', 51.92, 4.48),
    City('Utrecht', 'Nederland', 52.09, 5.12),
    City('Eindhoven', 'Nederland', 51.44, 5.48),
    City('Groningen', 'Nederland', 53.22, 6.57),
    City('Maastricht', 'Nederland', 50.85, 5.69),
    City('Brussel', 'België', 50.85, 4.35),
    City('Berlijn', 'Duitsland', 52.52, 13.41),
    City('Londen', 'VK', 51.51, -0.13),
    City('New York', 'VS', 40.71, -74.01),
    City('Tokio', 'Japan', 35.68, 139.69),
    City('Sydney', 'Australië', -33.87, 151.21),
  ];

  static City byName(String? name) =>
      presets.firstWhere((c) => c.name == name, orElse: () => presets.first);
}

class Weather {
  final double temp;
  final String beschrijving;
  final IconData icoon;
  const Weather(this.temp, this.beschrijving, this.icoon);
}

class WeatherService {
  static const _cityKey = 'wx_city';
  static const _modeKey = 'wx_mode';

  static Future<String> savedCity() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_cityKey) ?? 'Amsterdam';
  }

  static Future<void> saveCity(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_cityKey, name);
  }

  static Future<String> savedMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_modeKey) ?? 'live';
  }

  static Future<void> saveMode(String mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_modeKey, mode);
  }

  static Future<Weather?> fetch(City city) =>
      fetchByCoords(city.lat, city.lon);

  static Future<Weather?> fetchByCoords(double lat, double lon) async {
    try {
      final uri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
          '&current=temperature_2m,weather_code&timezone=auto');
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final cur = (jsonDecode(r.body) as Map)['current'] as Map?;
      if (cur == null) return null;
      final code = (cur['weather_code'] as num?)?.toInt() ?? -1;
      return Weather(
        (cur['temperature_2m'] as num?)?.toDouble() ?? 0,
        _beschrijving(code),
        _icoon(code),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> placeName(double lat, double lon) async {
    try {
      final uri = Uri.parse(
          'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lon&localityLanguage=nl');
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return 'Live locatie';
      final j = jsonDecode(r.body) as Map;
      final city = (j['city'] ?? j['locality'] ?? '') as String;
      final country = (j['countryName'] ?? '') as String;
      if (city.isEmpty) return 'Live locatie';
      return country.isEmpty ? city : '$city, $country';
    } catch (_) {
      return 'Live locatie';
    }
  }

  static String _beschrijving(int c) {
    if (c == 0) return 'Onbewolkt';
    if (c == 1) return 'Overwegend helder';
    if (c == 2) return 'Licht bewolkt';
    if (c == 3) return 'Bewolkt';
    if (c == 45 || c == 48) return 'Mist';
    if (c >= 51 && c <= 57) return 'Motregen';
    if (c >= 61 && c <= 67) return 'Regen';
    if (c >= 71 && c <= 77) return 'Sneeuw';
    if (c >= 80 && c <= 82) return 'Buien';
    if (c == 95) return 'Onweer';
    if (c == 96 || c == 99) return 'Onweer met hagel';
    return '—';
  }

  static IconData _icoon(int c) {
    if (c <= 1) return Icons.wb_sunny;
    if (c == 2) return Icons.cloudy_snowing;
    if (c == 3) return Icons.cloud;
    if (c == 45 || c == 48) return Icons.foggy;
    if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return Icons.water_drop;
    if (c >= 71 && c <= 77) return Icons.snowing;
    if (c >= 95) return Icons.thunderstorm;
    return Icons.cloud;
  }
}
