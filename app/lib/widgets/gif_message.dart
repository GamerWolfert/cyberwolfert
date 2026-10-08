import 'package:flutter/material.dart';

final _gifRe = RegExp(r'https?://[^\s]+?\.(?:gif|webp)', caseSensitive: false);

/// Berichttekst waarin GIF-URL's als echte animatie worden getoond
/// (rest blijft gewone tekst).
class GifBody extends StatelessWidget {
  final String body;
  final TextStyle? style;
  const GifBody(this.body, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final matches = _gifRe.allMatches(body).toList();
    if (matches.isEmpty) return Text(body, style: style);

    final kids = <Widget>[];
    var pos = 0;
    for (final m in matches) {
      final before = body.substring(pos, m.start).trim();
      if (before.isNotEmpty) kids.add(Text(before, style: style));
      kids.add(_GifView(m.group(0)!));
      pos = m.end;
    }
    final after = body.substring(pos).trim();
    if (after.isNotEmpty) kids.add(Text(after, style: style));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: kids,
    );
  }
}

class _GifView extends StatelessWidget {
  final String url;
  const _GifView(this.url);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 260),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          // Nooit een kaal plaatje: nette kaart met link naar de bron.
          errorBuilder: (_, __, ___) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF0E140E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gif_box_outlined,
                    size: 17, color: Colors.white38),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    'GIF niet beschikbaar — tik om te openen',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.75)),
                  ),
                ),
              ],
            ),
          ),
          loadingBuilder: (c, child, p) => p == null
              ? child
              : Container(
                  width: 180,
                  height: 140,
                  color: Colors.white10,
                  alignment: Alignment.center,
                  child: const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
        ),
      ),
    );
  }
}
