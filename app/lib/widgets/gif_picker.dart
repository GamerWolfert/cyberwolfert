import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/wolfsyn_service.dart';

/// AeroTalk GIF-kiezer (zoals Discord): tabs Gifs / Stickers / Emoji,
/// zoekveld, categorie-tegels en een raster met resultaten.
/// Geeft de gekozen URL (gif/sticker) of emoji-tekens terug, anders null.
Future<String?> showWolfGifPicker(BuildContext context) => showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => const _WolfGifPicker(),
    );

const List<String> _kCategories = [
  'hello',
  'lol',
  'love',
  'happy birthday',
  'cat',
  'dancing',
  'omg',
  'yes',
];

const String _kEmojis =
    '😀 😃 😄 😁 😆 😅 😂 🤣 🥲 ☺️ 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 🤪 🤨 🧐 🤓 😎 🥸 🤩 🥳 😏 😒 😞 😔 😟 😕 🙁 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 🤭 🤫 😶 😐 😑 😬 🙄 😯 😴 🤤 😪 😮 😇 🥱 😴 🤒 🤕 🤢 🤮 🥴 🥵 🥶 🥸 😈 👿 👹 👺 🤡 💩 👻 💀 ☠️ 👽 👾 🤖 🎃 😺 😸 😻 😼 😽 🙀 😾 😿 😽 🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵 🐔 🐧 🐦 🐤 🐣 🦆 🦅 🦉 🦇 🚀 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐜 🪰 🪲 🐢 🐍 🐙 🦑 🦀 🐡 🐠 🐟 🐬 🐳 🦈 🐋 🐊 ⚽ 🏀 🎾 🏐 🏑 🏒 ⛳ 🎣 🎱 🎳 🎮 🎲 🎯 🎤 🎧 🎸 🎹 🎺 🎻 🕺 💃 🎂 🎈 🎁 🎉 🎊 🏆 🥇 🥈 🥉 🏅 🕐 🕑 🕒 🕓 🕔 🕕 🕖 🕗 🕘 🕙 🕚 🕛 ⏰ ⏱️ ⏲️ 🔥 ✨ 🎄 🎅 ⭐ 🌟 💫 ⚡ 💥 ❄️ 🌈 ☀️ 🌙 ☁️ ⛅ 🌧️ ⛈️ 🌬️ 🌊 💧 🍔 🍟 🍕 🌭 🥪 🌮 🌯 🥙 🥗 🍜 🍛 🍚 🍣 🍱 🥟 🍰 🍪 🍩 🍦 🍨 🍫 🍬 🍭 🍯 🥛 ☕ 🍵 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🧊 ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ✅ ❌ ⭕ ❗ ❓ 💯 🔔 🔕 🚫 💢 ⚠️ 🚸 🚧 🚦 🛑 🆗 🆕 🆒 🆓 🆑 ♿ 🚹 🚺 🚻 🚼 🛗 🚪 🔞 📵 🚭 📳 📴 🔀 🔁 🔂 ▶️ ⏸️ ⏹️ ⏺️ ⏭️ ⏮️ ⤵️ ⤴️ 🔚 🔜 🔛 📶 📡 🔋 🔌 💡 🔦 🔒 🔓 🔑 🔨 ⚙️ 🔧 🔩 🔪 🗡️ 🔫 🛡️ 💉 🩹 🩺 🧬 🔬 🔭 💣 🔥 💯 🆗 👍 👎 👌 🤌 🤏 ✌️ 🤞 🫶 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ ✋ 🤚 🖐️ 🖖 👋 🤝 🙏 💪 🦾 ✍️ 💅 👏 🙌 👐 🤲 🫡 🫰';

class _WolfGifPicker extends StatefulWidget {
  const _WolfGifPicker();

  @override
  State<_WolfGifPicker> createState() => _WolfGifPickerState();
}

class _WolfGifPickerState extends State<_WolfGifPicker> {
  final _api = WolfSynService();
  final _search = TextEditingController();
  int _tab = 0; // 0 = gifs, 1 = stickers, 2 = emoji
  String? _query; // null = tegel-overzicht
  String _title = '';
  List<dynamic> _results = [];
  bool _busy = false;
  String? _error;
  final Map<String, String> _previews = {};
  List<String> _favs = [];

  static const _favKey = 'wolfsyn_favorites';

  @override
  void initState() {
    super.initState();
    _loadFavs();
    _loadHome();
  }

  Future<void> _loadFavs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_favKey);
      if (raw != null && mounted) {
        setState(() => _favs = (jsonDecode(raw) as List).cast<String>());
      }
    } catch (_) {}
  }

  Future<void> _saveFavs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_favKey, jsonEncode(_favs));
    } catch (_) {}
  }

  Future<void> _loadHome() async {
    setState(() {
      _query = null;
      _title = '';
      _busy = true;
      _error = null;
    });
    try {
      final trending = await _api.gifs('');
      if (!mounted) return;
      setState(() {
        _results = trending;
        if (trending.isNotEmpty) {
          _previews['trending'] =
              ((trending.first as Map)['url'] ?? '').toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Previews voor de categorie-tegels (achtergrond, niet blokkerend).
    for (final c in _kCategories) {
      if (_previews.containsKey(c)) continue;
      () async {
        try {
          final items = await _api.gifs(c);
          if (items.isNotEmpty && mounted) {
            setState(() =>
                _previews[c] = ((items.first as Map)['url'] ?? '').toString());
          }
        } catch (_) {}
      }();
    }
  }

  Future<void> _search2(String q, {String? title}) async {
    final term = q.trim();
    if (term.isEmpty) return;
    setState(() {
      _query = term;
      _title = title ?? term;
      _busy = true;
      _error = null;
    });
    try {
      final items = term == 'trending' ? await _api.gifs('') : await _api.gifs(term);
      if (!mounted) return;
      setState(() => _results = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String label, String q) async {
    _search.text = q == 'trending' ? '' : q;
    await _search2(q, title: label);
  }

  void _picked(String url) {
    _favs.remove(url);
    _favs.insert(0, url);
    if (_favs.length > 40) _favs = _favs.sublist(0, 40);
    _saveFavs();
    Navigator.pop(context, url);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1E1F22);
    const pill = Color(0xFF2B2D31);
    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  _tabBtn('Gifs', 0, pill),
                  const SizedBox(width: 6),
                  _tabBtn('Stickers', 1, pill),
                  const SizedBox(width: 6),
                  _tabBtn('Emoji', 2, pill),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (_tab < 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: TextField(
                  controller: _search,
                  onSubmitted: (_) => _search2(_search.text),
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _tab == 1 ? 'Zoek stickers…' : 'Zoeken in Klipy',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white54),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 18, color: Colors.white54),
                      onPressed: () => _search2(_search.text),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF111214),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3F4147)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF5865F2), width: 1.6),
                    ),
                  ),
                ),
              ),
            if (_tab == 2)
              const _EmojiPane()
            else
              Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_query == null) return _tiles();
    return _resultsGrid();
  }

  Widget _tabBtn(String label, int i, Color pill) {
    final on = _tab == i;
    return GestureDetector(
      onTap: () {
        setState(() => _tab = i);
        if (i == 0) {
          _loadHome();
        } else if (i == 1) {
          _search2('sticker', title: 'Stickers');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? pill : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: on ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _sectionBar(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back, size: 18, color: Colors.white70),
              onPressed: _tab == 0
                  ? _loadHome
                  : () => _search2('sticker', title: 'Stickers')),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _tiles() {
    if (_busy) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              TextButton(onPressed: _loadHome, child: const Text('Opnieuw')),
            ],
          ),
        ),
      );
    }

    final tiles = <Widget>[
      _tile(
        label: 'Favorieten',
        url: _favs.isNotEmpty ? _favs.first : null,
        color: const Color(0xFF4B57D6),
        onTap: () => setState(() {
          _query = '';
          _title = 'Favorieten';
          _results = _favs.map((u) => {'url': u, 'title': 'favoriet'}).toList();
        }),
      ),
      _tile(
        label: "Trending GIF's",
        url: _previews['trending'],
        icon: Icons.trending_up,
        onTap: () => _open("Trending GIF's", 'trending'),
      ),
      for (final c in _kCategories) _tile(label: c, url: _previews[c], onTap: () => _open(c, c)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: tiles,
    );
  }

  Widget _tile(
      {required String label,
      String? url,
      Color? color,
      IconData? icon,
      required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && url.isNotEmpty)
              Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 480,
                errorBuilder: (_, __, ___) =>
                    Container(color: color ?? const Color(0xFF2B2D31)),
                loadingBuilder: (c, child, p) => p == null
                    ? child
                    : Container(
                        color: color ?? const Color(0xFF2B2D31),
                        alignment: Alignment.center,
                        child: const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              Container(color: color ?? const Color(0xFF2B2D31)),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.34),
                    Colors.black.withValues(alpha: 0.52),
                  ],
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 17, color: Colors.white),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsGrid() {
    if (_busy) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final header = _sectionBar(_title);
    if (_results.isEmpty) {
      return Column(children: [
        header,
        Expanded(
          child: Center(
            child: Text(
              (_query ?? '').isEmpty
                  ? 'Nog geen favorieten. Kies eerst een GIF.'
                  : 'Niets gevonden voor "${_query!}".',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
      ]);
    }
    return Column(children: [
      header,
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.25,
          ),
          itemCount: _results.length,
          itemBuilder: (ctx, i) {
            final g = _results[i] as Map<String, dynamic>;
            final url = (g['url'] ?? '').toString();
            final title = (g['title'] ?? '').toString();
            return Tooltip(
              message: title,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _picked(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        cacheWidth: 320,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF2B2D31),
                          alignment: Alignment.center,
                          child: const Icon(Icons.gif_box, color: Colors.white38),
                        ),
                        loadingBuilder: (c, child, p) => p == null
                            ? child
                            : Container(
                                color: const Color(0xFF2B2D31),
                                alignment: Alignment.center,
                                child: const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black54],
                          ),
                        ),
                      ),
                      if (title.isNotEmpty)
                        Positioned(
                          left: 6,
                          bottom: 4,
                          right: 6,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _EmojiPane extends StatelessWidget {
  const _EmojiPane();

  @override
  Widget build(BuildContext context) {
    final all = _kEmojis.split(' ').where((e) => e.isNotEmpty).toList();
    return Expanded(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Vaak gebruikt',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70)),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 9,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: all.length,
              itemBuilder: (ctx, i) => InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => Navigator.pop(ctx, all[i]),
                child:
                    Center(child: Text(all[i], style: const TextStyle(fontSize: 22))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
