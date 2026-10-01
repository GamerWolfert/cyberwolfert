import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'api_service.dart';
import 'voice_platform.dart';

/// Fase van de Hey Nova-stemassistente.
enum NovaVoiceStatus {
  /// Microfoon uit.
  off,

  /// Luistert naar het wakewoord ("Hey Nova" / "Oke Nova").
  listening,

  /// Wakewoord gehoord: nu de vraag opnemen.
  heard,

  /// Vraag gesteld aan AeroNova AI (wacht op antwoord).
  asking,

  /// Antwoord wordt uitgesproken.
  speaking,
}

/// Hey Nova: luistert op het wakewoord, neemt je vraag op en laat AeroNova
/// antwoorden (getoond én uitgesproken). Werkt op Android, Windows, iOS,
/// macOS en de browser via speech_to_text + flutter_tts.
class NovaVoice extends ChangeNotifier {
  NovaVoice._();
  static final NovaVoice instance = NovaVoice._();

  static const _onKey = 'nova_voice_on';

  /// Varianten van het wakewoord, Nederlands en Engels. Ook kaal "nova"
  /// telt (de herkenner zet "hé nova" soms om in "nova" of "é nova").
  static final _wakeRe = RegExp(
    r'\b(?:(?:hey|hee|he|hoi|hallo|hello|oke|ok|okay|oh|joh|yo|aero)\s+)?nova\b',
    caseSensitive: false,
  );

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  NovaVoiceStatus _status = NovaVoiceStatus.off;
  bool _inited = false;
  bool _ttsReady = false;
  bool _awake = false;
  bool _processing = false;
  bool _restarting = false;
  bool _active = false; // eigen sessievlag (plugin denkt soms nog te luisteren)
  String _heard = '';
  String _question = '';
  String _answer = '';
  String _error = '';
  String _debug = '';
  Timer? _idleTimer;
  final List<Map<String, String>> _history = [];

  NovaVoiceStatus get status => _status;
  bool get enabled => _status != NovaVoiceStatus.off;

  /// Wat de microfoon nu oppikt (voor de UI).
  String get heard => _heard;

  /// De laatst gestelde vraag.
  String get question => _question;

  /// Het laatste antwoord van AeroNova.
  String get answer => _answer;

  /// Foutmelding (bijv. microfoon geweigerd), leeg als alles oké is.
  String get error => _error;

  /// Laatste gebeurtenis van de herkenner (diagnose in de kaart).
  String get debug => _debug;

  /// Of de assistente bij het openen van de app automatisch moet starten.
  Future<bool> shouldAutoStart() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_onKey) ?? false;
  }

  /// Wakewoord-modus aan (vraagt zo nodig microfoontoegang) of uit.
  Future<void> toggle() async {
    if (enabled) {
      await stop();
    } else {
      await start();
    }
  }

  Future<void> start() async {
    if (enabled) return;
    _error = '';
    if (!_inited) {
      // initialize() vraagt op Android/iOS meteen de microfoontoegang.
      bool ok = false;
      try {
        ok = await _stt.initialize(onStatus: _onStatus, onError: _onError);
      } catch (_) {
        ok = false;
      }
      _inited = true;
      if (!ok) {
        _error =
            'Spraakherkenning is niet beschikbaar of geweigerd. Sta de microfoon toe om Hey Nova te gebruiken.';
        _setStatus(NovaVoiceStatus.off);
        return;
      }
    }
    await _prepareTts();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_onKey, true);
    // App "wakker" houden zodat Hey Nova ook na het minimaliseren blijft
    // werken (foreground service met microfoontoegang, Android).
    await VoicePlatform.keepAlive(on: true);
    _setStatus(NovaVoiceStatus.listening);
    _note('gestart');
    _listen();
  }

  Future<void> stop() async {
    _idleTimer?.cancel();
    _awake = false;
    _processing = false;
    _restarting = false;
    _active = false;
    _heard = '';
    _question = '';
    try {
      await _stt.cancel();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    await VoicePlatform.keepAlive(on: false);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_onKey, false);
    _setStatus(NovaVoiceStatus.off);
  }

  /// Wissen van het laatste antwoord (UI-knop).
  void clear() {
    _answer = '';
    _question = '';
    _heard = '';
    notifyListeners();
  }

  // --- luisteren -----------------------------------------------------------

  void _listen() {
    if (!enabled || _processing || _active) return;
    _active = true;
    try {
      _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 6),
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
        ),
      );
      _note('luistert');
    } catch (_) {
      _active = false;
      _scheduleRestart();
    }
  }

  /// Na elke sessie opnieuw gaan luisteren (één herstart tegelijk).
  /// Ruimt eerst een eventuele "half-dode" sessie van de plugin op.
  void _scheduleRestart({int delayMs = 350}) {
    if (!enabled || _processing || _restarting) return;
    _restarting = true;
    Timer(Duration(milliseconds: delayMs), () {
      _restarting = false;
      if (!enabled || _processing) return;
      if (_active || _stt.isListening) {
        try {
          _stt.cancel();
        } catch (_) {}
        _active = false;
      }
      _listen();
    });
  }

  void _onStatus(String s) {
    if (s == 'listening') {
      _active = true;
      return;
    }
    if (s != 'notListening' && s != 'done' && s != 'cancelled') return;
    _active = false;
    if (_processing) return;
    _note('sessie $s');
    // Sessie voorbij: als de vraag al opgenomen is, die nu verwerken.
    if (_awake && _heard.trim().isNotEmpty) {
      _submit(_heard);
      return;
    }
    _scheduleRestart();
  }

  void _onError(dynamic err) {
    final code = '${err?.errorCode ?? ''}';
    _active = false;
    _note('fout $code');
    if (code == 'error_permission') {
      _error = 'Microfoontoegang geweigerd.';
      _awake = false;
      _processing = false;
      _setStatus(NovaVoiceStatus.off);
      return;
    }
    if (_processing) return;
    // Geen gedetecteerde spraak of tijdelijke fout: gewoon opnieuw proberen.
    _scheduleRestart(
        delayMs: code == 'error_speech_timeout' ? 500 : 350);
  }

  /// Tekst uit het resultaat (sommige toestellen vullen alleen `alternates`).
  static String _textOf(SpeechRecognitionResult r) {
    var t = r.recognizedWords.trim();
    if (t.isEmpty) {
      for (final a in r.alternates) {
        final s = a.recognizedWords.trim();
        if (s.isNotEmpty) {
          t = s;
          break;
        }
      }
    }
    return t;
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!enabled || _processing) return;
    final text = _textOf(r);
    if (text.isEmpty) return;
    _note('gehoord: $text');
    final norm = _norm(text);

    if (!_awake) {
      final m = _wakeRe.firstMatch(norm);
      if (m == null) return;
      _awake = true;
      _setStatus(NovaVoiceStatus.heard);
      VoicePlatform.vibrate(120); // korte trilbevestiging: "ik hoor je"
      final rest = norm.substring(m.end).trim();
      _heard = rest;
      notifyListeners();
      _idleTimer?.cancel();
      if (rest.isNotEmpty && r.finalResult) {
        _submit(rest);
        return;
      }
      // Wacht op de vraag; na 8 seconden stilte terug naar wakewoord.
      _idleTimer = Timer(const Duration(seconds: 8), () {
        if (_awake && !_processing) {
          _awake = false;
          _heard = '';
          _setStatus(NovaVoiceStatus.listening);
          _scheduleRestart();
        }
      });
      return;
    }

    // Wakewoord al gehoord: de tekst is (een deel van) de vraag.
    var q = norm;
    final m = _wakeRe.firstMatch(q);
    if (m != null) q = q.substring(m.end).trim();
    if (q.isEmpty) return;
    _heard = q;
    _idleTimer?.cancel();
    notifyListeners();
    if (r.finalResult) _submit(q);
  }

  // --- vraag stellen -------------------------------------------------------

  Future<void> _submit(String question) async {
    final q = question.trim();
    if (q.isEmpty || _processing) return;
    _processing = true;
    _question = q;
    _heard = q;
    _setStatus(NovaVoiceStatus.asking);
    try {
      await _stt.cancel();
    } catch (_) {}

    try {
      final text = (await ApiService().askAi(q, List.of(_history))).trim();
      if (text.isEmpty) throw Exception('leeg antwoord');
      _answer = text;
      _error = '';
      _history.add({'role': 'user', 'content': q});
      _history.add({'role': 'assistant', 'content': text});
      if (_history.length > 8) _history.removeRange(0, _history.length - 8);
      notifyListeners();
      await _speak(text);
    } catch (_) {
      _error = 'AeroNova is nu niet bereikbaar. Probeer het straks opnieuw.';
    } finally {
      _processing = false;
      _awake = false;
      _heard = '';
      if (enabled) {
        _setStatus(NovaVoiceStatus.listening);
        // Even wachten na het uitspreken: de microfoon pikkt anders het
        // eigen antwoord weer op.
        _scheduleRestart(delayMs: 800);
      } else {
        _setStatus(NovaVoiceStatus.off);
      }
    }
  }

  // --- uitspreken ----------------------------------------------------------

  Future<void> _prepareTts() async {
    if (_ttsReady) return;
    try {
      await _tts.setSpeechRate(0.48);
      for (final lang in ['nl_NL', 'nl_BE', 'en_US']) {
        try {
          await _tts.setLanguage(lang);
          break;
        } catch (_) {}
      }
      _ttsReady = true;
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    _setStatus(NovaVoiceStatus.speaking);
    try {
      await _prepareTts();
      await _tts.awaitSpeakCompletion(true);
      await _tts.speak(_speakable(text));
    } catch (_) {
      // Uitspreken lukt niet (bijv. geen spraakpakket): antwoord blijft tonen.
    }
  }

  /// Markdown wegwerken zodat de spraak geen sterretjes en kopjes leest.
  static String _speakable(String s) {
    var t = s
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' code ')
        .replaceAll(RegExp(r'`([^`]*)`'), r'$1')
        .replaceAll(RegExp(r'#+\s*'), '')
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')
        .replaceAll(RegExp(r'_([^_]+)_'), r'$1')
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
        .replaceAll('|', ', ');
    if (t.length > 900) t = '${t.substring(0, 900)}…';
    return t.trim();
  }

  // --- hulp ---------------------------------------------------------------

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Laatste gebeurtenis bewaren (kleine regel in de kaart, voor diagnosen).
  void _note(String s) {
    _debug = s;
  }

  void _setStatus(NovaVoiceStatus s) {
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}
