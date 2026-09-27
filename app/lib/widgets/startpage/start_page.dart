import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/quicklinks_service.dart';
import '../app_logo.dart';
import '../made_by.dart';
import '../wolfpulse_searchbar.dart';
import 'clock_card.dart';
import 'weather_card.dart';
import 'quick_links_panel.dart';
import 'recent_card.dart';
import 'night_scape.dart';

/// WolfPulse-startpagina: nachtwolf-achtergrond, links snelle links,
/// midden logo + zoeken + tegels, rechts klok + echt weer.
class StartPage extends StatefulWidget {
  final void Function(String url) onOpenUrl;
  const StartPage({super.key, required this.onOpenUrl});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  List<QuickLink> _links = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final links = await QuickLinksService.load();
    if (mounted) setState(() => _links = links);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final customImage = settings.backgroundType == 'image' &&
        (settings.backgroundValue.startsWith('http://') ||
            settings.backgroundValue.startsWith('https://'));

    final content = LayoutBuilder(
      builder: (ctx, c) {
        final wide = c.maxWidth > 950;
        if (wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 280,
                  child: Column(children: [
                    QuickLinksPanel(onOpen: widget.onOpenUrl),
                    const SizedBox(height: 12),
                    RecentCard(onOpen: widget.onOpenUrl),
                  ]),
                ),
                Expanded(child: _center()),
                const SizedBox(
                  width: 280,
                  child: Column(children: [
                    ClockCard(),
                    SizedBox(height: 12),
                    WeatherCard(),
                    SizedBox(height: 12),
                    GlassCard(
                      child: Text(
                        'Tip: typ "download" om de apps-zip te krijgen.',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _center(),
            const SizedBox(height: 12),
            if (c.maxWidth > 600)
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ClockCard()),
                  SizedBox(width: 12),
                  Expanded(child: WeatherCard()),
                ],
              )
            else ...[
              const ClockCard(),
              const SizedBox(height: 12),
              const WeatherCard(),
            ],
            const SizedBox(height: 12),
            QuickLinksPanel(onOpen: widget.onOpenUrl),
            const SizedBox(height: 12),
            RecentCard(onOpen: widget.onOpenUrl),
            const SizedBox(height: 16),
            const MadeBy(),
          ]),
        );
      },
    );
    // Alleen de standaard-look (nachtlandschap/foto) als de gebruiker
    // NIETS heeft gekozen. Eigen kleur/thema/afbeelding blijft zichtbaar
    // via de settings-laag erachter.
    final isDefault = settings.backgroundType == 'color' &&
        (settings.backgroundValue == '#0B1020' ||
            settings.backgroundValue.isEmpty);
    if (customImage || !isDefault) return content;
    // Foto-achtergrond (assets/night_bg.jpg) bovenop het geschilderde
    // nachtwolf-landschap; ontbreekt de foto, dan zie je het schilderwerk.
    return Stack(
      fit: StackFit.expand,
      children: [
        const NightScape(child: SizedBox.expand()),
        Positioned.fill(
          child: Image.asset(
            'assets/night_bg.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        content,
      ],
    );
  }

  Widget _center() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        const AppLogo(size: 200),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: WolfPulseSearchBar(onOpenUrl: widget.onOpenUrl, showTitle: false),
        ),
        const SizedBox(height: 20),
        QuickTiles(links: _links, onOpen: widget.onOpenUrl),
        const SizedBox(height: 16),
        const MadeBy(),
        const SizedBox(height: 8),
      ],
    );
  }
}
