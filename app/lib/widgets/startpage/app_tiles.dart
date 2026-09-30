import 'package:flutter/material.dart';
import '../../config/constants.dart';

class _AppTile {
  final IconData icon;
  final String label;
  final String sub;
  final String id;
  const _AppTile(this.icon, this.label, this.sub, this.id);
}

const List<_AppTile> _kApps = [
  _AppTile(Icons.search, 'AeroSeek', 'Zoeken', 'search'),
  _AppTile(Icons.smart_toy, 'AeroNova AI', 'Assistent', 'ai'),
  _AppTile(Icons.groups, 'AeroTalk', 'Community', 'chat'),
  _AppTile(Icons.mail, 'Mail', 'E-mail', 'mail'),
  _AppTile(Icons.download, 'Downloads', 'Bestanden', 'downloads'),
  _AppTile(Icons.settings, 'Instellingen', 'Uiterlijk', 'settings'),
];

/// Tegels voor de ingebouwde apps, met icoon + naam + korte omschrijving
/// zodat duidelijk is wat wat is.
class AppTiles extends StatelessWidget {
  final void Function(String id) onAction;
  const AppTiles({super.key, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: _kApps.map((a) {
        return Tooltip(
          message: '${a.label} — ${a.sub}',
          child: InkWell(
            onTap: () => onAction(a.id),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 118,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0A120A).withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
                boxShadow: [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.16),
                      blurRadius: 14,
                      spreadRadius: 1),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(a.icon, size: 26, color: accent),
                const SizedBox(height: 7),
                Text(a.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(a.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10.5, color: Colors.white.withValues(alpha: 0.55))),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Merkregel onderaan de startpagina (zoals in de referentie).
class BrandStrip extends StatelessWidget {
  const BrandStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontSize: 12,
        letterSpacing: 4,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.55));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 46, height: 1, color: const Color(0xFF3CFF5C)),
      const SizedBox(width: 12),
      Text('BETER · SNELLER · VRIJER', style: style),
      const SizedBox(width: 12),
      Container(width: 46, height: 1, color: const Color(0xFF3CFF5C)),
    ]);
  }
}

/// Kleine merkregel met de app-namen erin.
class AppStrip extends StatelessWidget {
  const AppStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: const [
        _pill('AeroSeek', Icons.search),
        _pill(AppConfig.aiName, Icons.smart_toy),
        _pill('AeroTalk', Icons.groups),
        _pill('Mail', Icons.mail),
      ],
    );
  }
}

class _pill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _pill(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: accent),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
      ]),
    );
  }
}
