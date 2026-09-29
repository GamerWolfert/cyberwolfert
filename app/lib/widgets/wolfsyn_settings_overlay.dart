import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/wolfsyn_service.dart';

/// Instellingen-overlay zoals Discord: links het navigatiemenu met
/// zoekveld en profiel, rechts de pagina met de instellingen.
Future<void> showWolfSettings(BuildContext context, {VoidCallback? onChanged}) =>
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _WolfSettings(onChanged: onChanged),
    );

const _cBg = Color(0xFF000000);
const _cLeft = Color(0xFF1E1F22);
const _cRight = Color(0xFF313338);
const _cInput = Color(0xFF111214);
const _cHover = Color(0xFF35373C);
const _cText = Color(0xFFDBDEE1);
const _cMuted = Color(0xFF949BA4);
const _cBlue = Color(0xFF5865F2);

class _Nav {
  final String id;
  final String label;
  final IconData icon;
  final String? section;
  const _Nav(this.id, this.label, this.icon, [this.section]);
}

const List<_Nav> _nav = [
  _Nav('account', 'Account', Icons.person_outline),
  _Nav('privacy', 'Data en privacy', Icons.shield_outlined),
  _Nav('perms', 'Berichtmachtigingen', Icons.mail_outline),
  _Nav('notif', 'Meldingen', Icons.notifications_none),
  _Nav('nitro', 'Nitro', Icons.workspace_premium_outlined, 'Facturatie'),
  _Nav('boost', 'Serverboost', Icons.bolt_outlined, 'Facturatie'),
  _Nav('subs', 'Abonnementen', Icons.autorenew, 'Facturatie'),
  _Nav('gifts', 'Cadeau-inventaris', Icons.card_giftcard, 'Facturatie'),
  _Nav('billing', 'Facturatie', Icons.receipt_long_outlined, 'Facturatie'),
  _Nav('voice', 'Spraak en video', Icons.mic_none, 'Ervaring'),
  _Nav('display', 'Weergave', Icons.palette_outlined, 'Ervaring'),
  _Nav('a11y', 'Toegankelijkheid', Icons.accessibility_new, 'Ervaring'),
  _Nav('system', 'Systeem', Icons.desktop_windows_outlined, 'Ervaring'),
  _Nav('lang', 'Taal en tijd', Icons.translate, 'Ervaring'),
  _Nav('games', 'Geregistreerde games', Icons.sports_esports_outlined, 'Games en apps'),
  _Nav('activity', 'Activiteitenprivacy', Icons.visibility_outlined, 'Games en apps'),
  _Nav('overlay', 'Game-overlay', Icons.layers_outlined, 'Games en apps'),
  _Nav('apps', 'Gekoppelde apps', Icons.apps_outlined, 'Games en apps'),
];

class _WolfSettings extends StatefulWidget {
  final VoidCallback? onChanged;
  const _WolfSettings({this.onChanged});

  @override
  State<_WolfSettings> createState() => _WolfSettingsState();
}

class _WolfSettingsState extends State<_WolfSettings> {
  final _wolf = WolfSynService();
  final _filter = TextEditingController();
  String _sel = 'account';
  Map<String, dynamic>? _profile;
  bool _busy = true;
  final _naamC = TextEditingController();
  final _bioC = TextEditingController();
  bool _fieldsFilled = false;

  @override
  void dispose() {
    _naamC.dispose();
    _bioC.dispose();
    _filter.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadToggles();
  }

  static const _toggleIds = [
    'notif_sound', 'notif_vibrate', 'notif_push', 'notif_friends',
    'sys_start', 'sys_tray', 'sys_accel',
    'priv_log', 'priv_stats', 'priv_media',
    'perm_gifs', 'perm_preview', 'perm_files',
    'a11y_text', 'a11y_motion', 'a11y_contrast',
    'voice_noise', 'voice_echo', 'voice_hd',
    'disp_chatbg', 'disp_compact',
  ];

  Future<void> _loadToggles() async {
    try {
      final p = await SharedPreferences.getInstance();
      final vals = <String, bool>{};
      for (final id in _toggleIds) {
        final v = p.getBool('ws_$id');
        if (v != null) vals[id] = v;
      }
      if (mounted && vals.isNotEmpty) setState(() => _toggles.addAll(vals));
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final p = await _wolf.profile();
      if (mounted) {
        setState(() {
          _profile = p;
          if (!_fieldsFilled) {
            _naamC.text = (p['display_name'] ?? '').toString();
            _bioC.text = (p['bio'] ?? '').toString();
            _fieldsFilled = true;
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<_Nav> get _visible {
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty) return _nav;
    return _nav.where((n) => n.label.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 700;
    _narrow = narrow;
    return Dialog(
      backgroundColor: _cBg,
      insetPadding: EdgeInsets.fromLTRB(
          narrow ? 6 : 48, narrow ? 6 : 56, narrow ? 6 : 48, narrow ? 6 : 64),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            SizedBox(width: narrow ? 168 : 300, child: _left()),
            Expanded(child: _right()),
          ],
        ),
      ),
    );
  }

  bool _narrow = false;

  // ---------------------------------------------------------------- links
  Widget _left() {
    final auth = context.watch<AuthProvider>();
    final items = _visible;
    return Container(
      color: _cLeft,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 14),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _cHover,
                backgroundImage: (_profile?['avatar'] ?? '').toString().isNotEmpty
                    ? NetworkImage(_profile!['avatar'].toString())
                    : null,
                child: (_profile?['avatar'] ?? '').toString().isEmpty
                    ? Text(auth.naam.isNotEmpty
                        ? auth.naam.characters.first.toUpperCase()
                        : '?')
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (_profile?['display_name'] ?? auth.naam).toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _sel = 'account'),
                      child: const Text(
                        'Profielen bewerken ✏️',
                        style: TextStyle(color: _cMuted, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: _cText, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Zoeken',
              hintStyle: const TextStyle(color: _cMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 16, color: _cMuted),
              isDense: true,
              filled: true,
              fillColor: _cInput,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (items[i].section != null &&
                      (i == 0 || items[i - 1].section != items[i].section)) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: Text(items[i].section!,
                          style: const TextStyle(
                              color: _cMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                  _navItem(items[i]),
                ],
              ],
            ),
          ),
          const Divider(color: _cHover, height: 18),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _confirmLogout,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Row(children: const [
                Icon(Icons.logout, size: 16, color: Color(0xFFF23F43)),
                SizedBox(width: 10),
                Text('Afmelden',
                    style: TextStyle(color: Color(0xFFF23F43), fontSize: 13.5)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(_Nav n) {
    final on = _sel == n.id;
    return Material(
      color: on ? _cHover : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _sel = n.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(children: [
            Icon(n.icon, size: 16, color: on ? Colors.white : _cMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(n.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      color: on ? Colors.white : _cText,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
            ),
          ]),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- rechts
  Widget _right() {
    final title = _nav.firstWhere((n) => n.id == _sel).label;
    return Container(
      color: _cRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 12),
            child: Row(children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 22, color: _cMuted),
                tooltip: 'Sluiten (Esc)',
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          const Divider(color: _cHover, height: 1),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                        _narrow ? 16 : 40, 24, _narrow ? 16 : 40, 40),
                    children: [_page(_sel)],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _page(String id) {
    switch (id) {
      case 'account':
        return _accountPage();
      case 'notif':
        return _simplePage('Meldingen', 'Kies wanneer WolfSyn je lastigvalt.', [
          _toggle('notif_sound', 'Berichtgeluid',
              'Speel een geluid af bij een nieuw bericht.', true),
          _toggle('notif_vibrate', 'Trillen', 'Vibratie bij binnenkomend bericht.', true),
          _toggle('notif_push', 'Pushmeldingen',
              'Ook meldingen als de app op de achtergrond draait.', false),
          _toggle('notif_friends', 'Alleen van vrienden',
              'Meldingen alleen tonen voor vriendschapsverzoeken en vrienden.', false),
        ]);
      case 'display':
        return _displayPage();
      case 'system':
        return _simplePage('Systeem', 'Algemene instellingen van de app.', [
          _toggle('sys_start', 'CyberWolfert automatisch openen',
              'Start de app zodra je de computer opstart.', false),
          _toggle('sys_tray', 'Minimaliseren naar systeembalk',
              'Door op X te klikken wordt de app geminimaliseerd in plaats van afgesloten.', true),
          _toggle('sys_accel', 'Hardwareversnelling inschakelen',
              'Gebruik de GPU om soepel te laten draaien. Schakel uit bij haperingen.', false),
          if (!(_toggles['sys_accel'] ?? false))
            _banner(Colors.amber.shade900, Icons.warning_amber_rounded,
                'Hardwareversnelling is uitgeschakeld. Dit vermindert de prestaties en beeldkwaliteit.'),
          const SizedBox(height: 18),
          const _H('Sneltoetsen'),
          _infoRow('Zoeken openen', 'Ctrl + /'),
          _infoRow('Bericht versturen', 'Enter'),
          _infoRow('Overzicht sluiten', 'Esc'),
        ]);
      case 'privacy':
        return _simplePage('Data en privacy', 'Jij bepaalt wat er wordt bewaard.', [
          _toggle('priv_log', 'Lokale logboeken',
              'Bewaar een log van foutmeldingen op dit apparaat.', true),
          _toggle('priv_stats', 'Anonieme statistieken',
              'Helpt om WolfSyn te verbeteren — zonder je berichten.', false),
          _toggle('priv_media', 'Media automatisch laden',
              'Afbeeldingen en GIF’s direct tonen in chats.', true),
        ]);
      case 'perms':
        return _simplePage('Berichtmachtigingen', 'Bepaal wat er in je chats gebeurt.', [
          _toggle('perm_gifs', 'GIF’s automatisch afspelen',
              'GIF’s in berichten direct animeren.', true),
          _toggle('perm_preview', 'Links als voorbeeld',
              'Toon een preview bij gedeelde links.', true),
          _toggle('perm_files', 'Bestanden van iedereen',
              'Ontvang bestanden van alle leden (anders alleen vrienden).', false),
        ]);
      case 'a11y':
        return _simplePage('Toegankelijkheid', 'Maak WolfSyn comfortabeler.', [
          _toggle('a11y_text', 'Grotere tekst', 'Vergroot de tekst in chats.', false),
          _toggle('a11y_motion', 'Minder beweging', 'Schakel overbodige animaties uit.', false),
          _toggle('a11y_contrast', 'Hoger contrast', 'Duidelijkere kleuren en randen.', false),
        ]);
      case 'lang':
        return _simplePage('Taal en tijd', 'Hoe WolfSyn zich uitdrukt.', [
          _infoRow('Taal', 'Nederlands'),
          _infoRow('Tijdzone', 'Europe/Amsterdam (UTC+02:00)'),
          _infoRow('Datumformaat', 'dd-mm-jjjj'),
          _infoRow('Tijdsnotatie', '24-uurs'),
          const SizedBox(height: 16),
          _banner(const Color(0xFF1E3A5F), Icons.info_outline,
              'Wil je een andere taal? Stuur een bericht in #wolf-logs.'),
        ]);
      case 'voice':
        return _simplePage('Spraak en video', 'Instellingen voor bellen en streamen.', [
          _toggle('voice_noise', 'Ruisonderdrukking', 'Filter achtergrondgeluid weg.', true),
          _toggle('voice_echo', 'Echo-onderdrukking', 'Voorkom dat je jezelf hoort.', true),
          _toggle('voice_hd', 'Videokwaliteit in HD', 'Meer data, beter beeld.', false),
          const SizedBox(height: 16),
          _infoRow('Microfoon', 'Systeemstandaard'),
          _infoRow('Luidspreker', 'Systeemstandaard'),
        ]);
      case 'games':
      case 'activity':
      case 'overlay':
      case 'apps':
        return _pageUnter(id);
      default:
        return _pageUnter(id);
    }
  }

  Widget _pageUnter(String id) {
    final n = _nav.firstWhere((x) => x.id == id);
    final soon = <String, String>{
      'nitro': 'Nitro is het betaalde lidmaatschap van WolfSyn — binnenkort beschikbaar.',
      'boost': 'Boost je favoriete servers zodra boosts live gaan. Je boost telt nu al mee.',
      'subs': 'Abonnementen verschijnen hier zodra er iets te abonneren valt.',
      'gifts': 'Cadeau-inventaris: hier belanden cadeaus die je krijgt of geeft.',
      'billing': 'Facturatie en betaalmethodes worden hier beheerd.',
      'games': 'WolfSyn ziet straks welke games je speelt — koppel je accounts in de browser.',
      'activity': 'Bepaal wie je activiteit mag zien.',
      'overlay': 'De game-overlay toont chats bovenop je game.',
      'apps': 'Gekoppelde apps en integraties staan hier.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _H('Binnenkort'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _cLeft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cHover),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n.label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(soon[id] ?? 'Deze pagina is nog in ontwikkeling.',
                  style: const TextStyle(color: _cMuted, fontSize: 13.5)),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- pagina's
  Widget _simplePage(String title, String sub, List<Widget> kids) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _H(title),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: _cMuted, fontSize: 13.5)),
          const SizedBox(height: 18),
          ...kids,
        ],
      );

  final Map<String, bool> _toggles = {};

  Widget _toggle(String pref, String title, String desc, bool def) {
    final on = _toggles[pref] ?? def;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _cText, fontSize: 14.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(desc, style: const TextStyle(color: _cMuted, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: on,
            activeThumbColor: Colors.white,
            activeTrackColor: _cBlue,
            onChanged: (v) async {
              setState(() => _toggles[pref] = v);
              try {
                final p = await SharedPreferences.getInstance();
                await p.setBool('ws_$pref', v);
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(color: _cMuted, fontSize: 13.5))),
          Text(v, style: const TextStyle(color: _cText, fontSize: 13.5)),
        ]),
      );

  Widget _banner(Color c, IconData i, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c),
        ),
        child: Row(children: [
          Icon(i, size: 18, color: Colors.amber.shade200),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: _cText, fontSize: 12.5))),
        ]),
      );

  Widget _displayPage() {
    final s = context.watch<SettingsProvider>();
    final themes = [
      ['dark', 'Donker'],
      ['light', 'Licht'],
      ['system', 'Systeem'],
    ];
    final accents = ['#E63946', '#5865F2', '#29B6F6', '#43B581', '#FAA61A', '#EB459E'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _H('Weergave'),
        const SizedBox(height: 4),
        const Text('Hoe WolfSyn eruitziet.',
            style: TextStyle(color: _cMuted, fontSize: 13.5)),
        const SizedBox(height: 20),
        const Text('Thema',
            style: TextStyle(
                color: _cText, fontSize: 14.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: themes.map((t) {
            final on = s.theme == t[0];
            return ChoiceChip(
              label: Text(t[1]),
              selected: on,
              selectedColor: _cBlue,
              labelStyle:
                  TextStyle(color: on ? Colors.white : _cText, fontSize: 13),
              backgroundColor: _cLeft,
              onSelected: (_) => s.update(theme: t[0]),
            );
          }).toList(),
        ),
        const SizedBox(height: 22),
        const Text('Accentkleur',
            style: TextStyle(
                color: _cText, fontSize: 14.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: accents.map((h) {
            final on = s.accentColor.toUpperCase() == h.toUpperCase();
            return GestureDetector(
              onTap: () => s.update(accent: h),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color(int.parse('FF${h.substring(1)}', radix: 16)),
                  shape: BoxShape.circle,
                  border: on
                      ? Border.all(color: Colors.white, width: 2.5)
                      : null,
                ),
                child: on ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 22),
        _toggle('disp_chatbg', 'Chatachtergrond opmaken',
            'Gebruik de themakleur achter berichten.', true),
        _toggle('disp_compact', 'Compacte weergave',
            'Minder witruimte tussen berichten.', false),
      ],
    );
  }

  Widget _accountPage() {
    final auth = context.watch<AuthProvider>();
    final naam = _naamC;
    final bio = _bioC;
    final avatar = (_profile?['avatar'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _H('Mijn account'),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _cLeft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cHover),
          ),
          child: Column(
            children: [
              Container(
                height: 74,
                decoration: const BoxDecoration(
                  color: _cBlue,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -34),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: _cHover,
                        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                        child: avatar.isEmpty
                            ? Text(auth.naam.isNotEmpty
                                ? auth.naam.characters.first.toUpperCase()
                                : '?',
                                style: const TextStyle(fontSize: 26))
                            : null,
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -8),
                      child: Column(
                        children: [
                          Text((_profile?['display_name'] ?? auth.naam).toString(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('@${auth.user?['username'] ?? ''}',
                              style:
                                  const TextStyle(color: _cMuted, fontSize: 13)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _pill(Icons.photo_camera_outlined, 'Wijzig foto', _pickAvatar),
                          _pill(Icons.edit_outlined, 'Profiel bewerken', () {}),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _H('Profiel'),
        const SizedBox(height: 12),
        TextField(
          controller: naam,
          style: const TextStyle(color: _cText),
          decoration: _inp('WolfSyn-naam'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: bio,
          maxLines: 3,
          style: const TextStyle(color: _cText),
          decoration: _inp('Bio'),
        ),
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _cBlue),
          onPressed: () async {
            try {
              await _wolf.saveProfile(
                  displayName: naam.text.trim(), bio: bio.text.trim());
              await _load();
              widget.onChanged?.call();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profiel opgeslagen.')));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text(e.toString().replaceFirst('Exception: ', ''))));
              }
            }
          },
          child: const Text('Opslaan'),
        ),
        const SizedBox(height: 26),
        const _H('Accountgegevens'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cLeft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cHover),
          ),
          child: Column(
            children: [
              _infoRow('Gebruikersnaam', '${auth.user?['username'] ?? ''}'),
              _infoRow('E-mail', '${auth.user?['email'] ?? '—'}'),
              _infoRow('Telefoonnummer', 'Niet toegevoegd'),
              const Divider(color: _cHover, height: 20),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Wachtwoord',
                          style: TextStyle(
                              color: _cText,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 3),
                      Text('Laatst gewijzigd onbekend',
                          style: TextStyle(color: _cMuted, fontSize: 12.5)),
                    ],
                  )),
                  OutlinedButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Wachtwoord wijzigen doe je via de browser-accountpagina.'))),
                    child: const Text('Wijzigen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inp(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _cMuted),
        filled: true,
        fillColor: _cInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _cHover),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _cHover),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _cBlue),
        ),
      );

  Widget _pill(IconData i, String t, VoidCallback on) => OutlinedButton.icon(
        onPressed: on,
        icon: Icon(i, size: 15),
        label: Text(t, style: const TextStyle(fontSize: 12.5)),
      );

  Future<void> _pickAvatar() async {
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (img == null) return;
      await _wolf.uploadAvatar(img.path, img.name);
      await _load();
      widget.onChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profielfoto bijgewerkt.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cRight,
        title: const Text('Afmelden?', style: TextStyle(color: Colors.white)),
        content: const Text('Je moet daarna opnieuw inloggen om WolfSyn te gebruiken.',
            style: TextStyle(color: _cText)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF23F43)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Afmelden'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final auth = context.read<AuthProvider>();
    Navigator.pop(context);
    await auth.logout();
  }
}

/// Grote sectiekop rechtsboven op een instellingenpagina.
class _H extends StatelessWidget {
  final String t;
  const _H(this.t);

  @override
  Widget build(BuildContext context) => Text(t,
      style: const TextStyle(
          color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600));
}
