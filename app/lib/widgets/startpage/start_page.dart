import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../app_logo.dart';
import '../made_by.dart';
import '../wolfpulse_searchbar.dart';
import 'app_tiles.dart';
import 'clock_card.dart';
import 'weather_card.dart';
import 'quick_links_panel.dart';
import 'recent_card.dart';
import 'night_scape.dart';

/// AeroSeek-startpagina: nachtwolf-achtergrond, links snelle links,
/// midden logo + zoeken + tegels, rechts klok + echt weer.
class StartPage extends StatefulWidget {
  final void Function(String url) onOpenUrl;

  /// Aanroep van de tegels met ingebouwde apps
  /// (search / ai / chat / mail / downloads / settings).
  final void Function(String id)? onApp;
  const StartPage({super.key, required this.onOpenUrl, this.onApp});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
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
        (settings.backgroundValue == '#050805' ||
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
        // Zoekmachine-logo groot boven de zoekbalk (zoals in het ontwerp).
        const SeekLogo(size: 210),
        const SizedBox(height: 10),
        Text(
          'F A S T   ·   S A F E   ·   U N L I M I T E D',
          style: TextStyle(
              fontSize: 13,
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: WolfPulseSearchBar(onOpenUrl: widget.onOpenUrl, showTitle: false),
        ),
        const SizedBox(height: 22),
        AppTiles(onAction: (id) => widget.onApp?.call(id)),
        const SizedBox(height: 20),
        const BrandStrip(),
        const SizedBox(height: 16),
        const MadeBy(),
        const SizedBox(height: 8),
      ],
    );
  }
}
