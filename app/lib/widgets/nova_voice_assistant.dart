import 'package:flutter/material.dart';

import '../services/nova_voice.dart';
import '../services/update_service.dart';

/// Zwevende Hey Nova-knop (linksonder) met een statuskaart erboven:
/// wakewoord aan/uit, live-getranscribeerde vraag, antwoord en foutmelding.
/// Werkt op elk scherm (via de builder in main.dart).
class NovaVoiceAssistant extends StatefulWidget {
  const NovaVoiceAssistant({super.key});

  @override
  State<NovaVoiceAssistant> createState() => _NovaVoiceAssistantState();
}

class _NovaVoiceAssistantState extends State<NovaVoiceAssistant> {
  final NovaVoice _nova = NovaVoice.instance;
  bool _cardOpen = false;
  bool _manual = false; // kaart handmatig opengezet (diagnose)

  @override
  void initState() {
    super.initState();
    _nova.addListener(_changed);
  }

  @override
  void dispose() {
    _nova.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    // Kaart automatisch openen zodra er iets te melden valt, sluiten als
    // alles klaar is en de microfoon weer luistert.
    final s = _nova.status;
    if (!_cardOpen &&
        (s == NovaVoiceStatus.asking ||
            s == NovaVoiceStatus.speaking ||
            s == NovaVoiceStatus.heard ||
            _nova.heard.isNotEmpty ||
            _nova.answer.isNotEmpty ||
            _nova.error.isNotEmpty)) {
      _cardOpen = true;
    }
    if (_cardOpen &&
        !_manual &&
        s == NovaVoiceStatus.listening &&
        _nova.answer.isEmpty &&
        _nova.error.isEmpty &&
        _nova.heard.isEmpty) {
      _cardOpen = false;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _nova.status;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_cardOpen) _card(context, cs),
              const SizedBox(height: 10),
              _micButton(context, cs, s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _micButton(BuildContext context, ColorScheme cs, NovaVoiceStatus s) {
    final on = _nova.enabled;
    final busy = s == NovaVoiceStatus.asking || s == NovaVoiceStatus.speaking;
    return Material(
      color: on ? cs.primary : cs.surfaceContainerHighest,
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        // Tikken: aan/uit. Lang ingedrukt houden: diagnosetekst tonen.
        onTap: busy ? null : _nova.toggle,
        onLongPress: () => setState(() {
          _manual = !_cardOpen;
          _cardOpen = !_cardOpen;
        }),
        child: Tooltip(
          message: 'Hey Nova aan/uit — lang ingedrukt houden = diagnose',
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: busy
                ? SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: on ? cs.onPrimary : cs.primary,
                    ),
                  )
                : Icon(
                    on ? Icons.mic : Icons.mic_none,
                    size: 26,
                    color: on ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, ColorScheme cs) {
    final s = _nova.status;
    String title;
    Widget body;
    if (_nova.error.isNotEmpty) {
      title = 'Hey Nova';
      body = Text(_nova.error, style: const TextStyle(fontSize: 13));
    } else if (s == NovaVoiceStatus.asking) {
      title = 'AeroNova denkt na…';
      body = Text(_nova.question,
          style: const TextStyle(fontSize: 13, color: Colors.white70));
    } else if (s == NovaVoiceStatus.speaking) {
      title = 'AeroNova antwoordt';
      body = Text(_nova.answer,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13));
    } else if (s == NovaVoiceStatus.heard) {
      title = 'Ik luister…';
      body = Text(
        _nova.heard.isEmpty ? 'Zeg je vraag' : _nova.heard,
        style: const TextStyle(fontSize: 13, color: Colors.white70),
      );
    } else if (_nova.answer.isNotEmpty) {
      title = _nova.question;
      body = Text(_nova.answer,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13));
    } else {
      title = 'Hey Nova';
      body = const Text('Zeg "Hey Nova" of "Oke Nova" om te beginnen.',
          style: TextStyle(fontSize: 13, color: Colors.white70));
    }

    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            body,
            if (_nova.enabled)
              // Diagnose: welke build, of de achtergronddienst draait en wat
              // de herkenner de laatste keer deed (belangrijk bij storing).
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'build ${UpdateService.currentBuild} · '
                  'dienst ${_nova.serviceRunning ? "aan" : "UIT"} · '
                  'mic ${_nova.debug.isEmpty ? '—' : _nova.debug}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: Colors.white38),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 17),
                tooltip: 'Sluiten',
                onPressed: () {
                  _nova.clear();
                  _manual = false;
                  setState(() => _cardOpen = false);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
