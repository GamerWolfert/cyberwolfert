import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../providers/auth_provider.dart';
import 'api_service.dart';
import 'local_notify.dart';
import 'sound_service.dart';
import 'voice_platform.dart';

enum CallStatus { off, outgoing, incoming, active, ended }

/// AeroTalk-gesprekken: WebRTC (audio/video/scherm delen) met signaling
/// via de WebSocket op /ws. EÃƒÂ©n exemplaar voor de hele app.
class CallService extends ChangeNotifier {
  CallService._();
  static final CallService instance = CallService._();

  CallStatus status = CallStatus.off;
  String? callId;
  int? peerId;
  String peerName = '';
  String kind = 'video'; // audio | video | screen
  bool isCaller = false;
  DateTime? startedAt;
  String? error;
  String? statusText;

  bool micOn = true;
  bool camOn = true;
  bool screenOn = false;

  MediaStream? localStream;
  MediaStream? remoteStream;
  MediaStream? _screen;
  MediaStream? get localScreen => _screen;
  Set<int> onlineUsers = {};
  final List<Map<String, dynamic>> missed = []; // ongelezen gemiste gesprekken

  WebSocketChannel? _ws;
  Timer? _retry;
  Timer? _ping;
  Timer? _ring; // belussen + trilling bij inkomend gesprek
  int _tries = 0;
  bool _wantWs = false;
  bool _opening = false;

  RTCPeerConnection? _pc;
  final List<Map<String, dynamic>> _pending = [];
  /// Pas signalen toepassen als de peerconnection ÃƒÂ©n onze eigen media
  /// toegevoegd zijn Ã¢â‚¬â€ anders wordt het antwoord zonder videosporen gemaakt
  /// en ziet de ander nooit beeld.
  bool _ready = false;
  /// True zolang wij een offer verstuurd hebben maar het antwoord nog niet
  /// binnen is (glare-bescherming bij gelijktijdige renegotiatie).
  bool _localOfferOut = false;
  MediaStream? _remote;

  bool get inCall =>
      status == CallStatus.outgoing ||
      status == CallStatus.incoming ||
      status == CallStatus.active;
  bool get isActive => status == CallStatus.active;

  void _notify() => notifyListeners();

  // ---------------------------------------------------------------- WebSocket
  Future<void> connect() async {
    _wantWs = true;
    await _open();
  }

  void disconnect() {
    _wantWs = false;
    _retry?.cancel();
    _ping?.cancel();
    _ws?.sink.close();
    _ws = null;
    if (inCall) _teardown('disconnect');
  }

  Future<void> _open() async {
    if (_opening || _ws != null || !_wantWs) return;
    _opening = true;
    try {
      final token = await AuthStore.get();
      if (token == null) {
        _opening = false;
        return;
      }
      await ApiService().resolveBase();
      final base = ApiService().base;
      var wsBase = base.replaceFirst(RegExp(r'^http'), 'ws').replaceFirst(RegExp(r'/api$'), '');
      final uri = Uri.parse('$wsBase/ws?token=${Uri.encodeQueryComponent(token)}');
      final ch = WebSocketChannel.connect(uri);
      _ws = ch;
      _tries = 0;
      _startPing();
      ch.stream.listen(
        (raw) {
          try {
            _on(jsonDecode(raw as String) as Map<String, dynamic>);
          } catch (_) {}
        },
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _ws = null;
      _scheduleRetry();
    }
    _opening = false;
  }

  void _onClosed() {
    _ws = null;
    _ping?.cancel();
    if (inCall) {
      error = 'Verbinding verloren';
      _teardown('disconnect');
    }
    _scheduleRetry();
  }

  /// Eigen houd-levend ping (WebSocketChannel heeft geen ingebouwde).
  void _startPing() {
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 25), (_) {
      _send({'t': 'ping'});
    });
  }

  void _scheduleRetry() {
    if (!_wantWs) return;
    _retry?.cancel();
    _tries = min(_tries + 1, 5);
    _retry = Timer(Duration(seconds: _tries), () => _open());
  }

  void _send(Map<String, dynamic> m) {
    final ws = _ws;
    if (ws == null) return;
    try {
      ws.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  Future<void> _on(Map<String, dynamic> m) async {
    switch (m['t']) {
      case 'hello':
      case 'online':
        final u = m['users'] ?? m['online'];
        if (u is List) onlineUsers = u.map((e) => (e as num).toInt()).toSet();
        _notify();
        break;
      case 'ringing':
        callId = m['call']?.toString();
        peerId = (m['to'] as num?)?.toInt();
        status = CallStatus.outgoing;
        statusText = 'BellenÃ¢â‚¬Â¦';
        _notify();
        break;
      case 'incoming':
        if (inCall) {
          _send({'t': 'reject', 'call': m['call']}); // bezet
          break;
        }
        callId = m['call']?.toString();
        peerId = (m['from'] as num?)?.toInt();
        peerName = (m['fromName'] ?? '').toString();
        kind = (m['kind'] ?? 'video').toString();
        isCaller = false;
        status = CallStatus.incoming;
        statusText = 'Inkomend gesprek';
        error = null;
        _notify();
        _startRinging();
        // Ook als de app op de achtergrond draait: melding met volledig
        // scherm (bel-intent) zodat het toestel oplicht als een echte oproep.
        LocalNotify.show(
          peerName.isEmpty ? 'AeroTalk' : peerName,
          kind == 'screen'
              ? 'Inkomend verzoek om scherm te delen'
              : kind == 'audio'
                  ? 'Inkomend audiogesprek'
                  : 'Inkomend videogesprek',
          call: true,
          id: LocalNotify.callId,
        );
        break;
      case 'accepted':
        status = CallStatus.active;
        startedAt = DateTime.now();
        statusText = null;
        _notify();
        if (isCaller) {
          _setupCaller();
        } else {
          _setupCallee();
        }
        break;
      case 'signal':
        _onSignal(m['data'] as Map<String, dynamic>? ?? const {});
        break;
      case 'ended':
        final reden = (m['reason'] ?? '').toString();
        if (status != CallStatus.off) {
          status = CallStatus.ended;
          _stopRinging();
          if (reden == 'rejected') {
            error = 'Geweigerd door ${peerName.isEmpty ? 'de ander' : peerName}';
          } else if (reden == 'missed') {
            error = 'Niet opgenomen';
          } else if (reden == 'disconnect') {
            error = 'Verbinding verloren';
          } else if (reden == 'busy') {
            error = 'Bezig in een ander gesprek';
          } else {
            error = null;
          }
          await _teardown(reden);
          status = CallStatus.off;
          callId = null;
          _notify();
          Timer(const Duration(seconds: 4), () {
            if (status == CallStatus.off && error != null) {
              error = null;
              _notify();
            }
          });
        }
        break;
      case 'error':
        final e = (m['error'] ?? '').toString();
        if (e == 'offline') {
          error = '${peerName.isEmpty ? 'De ander' : peerName} is offline';
          status = CallStatus.off;
          await _teardown('error');
        } else if (e == 'busy') {
          error = 'Bezig in een ander gesprek';
          status = CallStatus.off;
          await _teardown('error');
        } else if (e == 'auth_required') {
          _wantWs = false;
          error = 'Opnieuw inloggen nodig';
        }
        _notify();
        break;
    }
  }

  // ------------------------------------------------------------------ WebRTC
  Future<RTCPeerConnection> _peer() async {
    // Unified-plan (de standaard): addStream is hier uitgeschakeld in
    // libwebrtc, dus werken we met addTrack. Plan-b forceren leverde bij
    // beide partijen een SDP zonder media op -> elkaars camera nooit zien.
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']}
      ],
    });
    // Eigen stream-object voor de remote tracks: unified-plan levert op web
    // soms een lege streams-lijst, dan bouwen we de stream zelf.
    try {
      _remote = await createLocalMediaStream('remote');
    } catch (_) {}
    pc.onIceCandidate = (c) {
      _send({
        't': 'signal',
        'call': callId,
        'data': {
          'type': 'ice',
          'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}
        }
      });
    };
    pc.onAddStream = (s) {
      if (s.getTracks().isEmpty) return;
      remoteStream = s;
      _notify();
    };
    pc.onTrack = (e) {
      final track = e.track;
      final streams = e.streams;
      if (streams.isNotEmpty) {
        remoteStream = streams[0];
      } else {
        final r = _remote;
        if (r != null) {
          final bestaat = r.getTracks().any((t) => t.id == track.id);
          if (!bestaat) r.addTrack(track);
          remoteStream = r;
        }
      }
      track.onEnded = () {
        try {
          remoteStream?.removeTrack(track);
        } catch (_) {}
        if ((remoteStream?.getTracks().length ?? 0) == 0) remoteStream = null;
        _notify();
      };
      _notify();
    };
    pc.onConnectionState = (st) {
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          st == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        error = 'Verbinding met ${peerName.isEmpty ? 'de ander' : peerName} verbroken';
        _teardown('disconnect');
        status = CallStatus.off;
        callId = null;
        _notify();
      }
    };
    return pc;
  }

  Future<MediaStream> _media({required bool video}) async {
    final s = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user', 'width': {'ideal': 640}, 'height': {'ideal': 480}} : false,
    });
    localStream = s;
    for (final t in s.getVideoTracks()) {
      t.enabled = camOn;
    }
    for (final t in s.getAudioTracks()) {
      t.enabled = micOn;
    }
    return s;
  }

  /// Lokale tracks toevoegen (unified-plan): addTrack i.p.v. het oude addStream.
  Future<void> _addStream(RTCPeerConnection pc, MediaStream? s) async {
    if (s == null) return;
    for (final t in s.getTracks()) {
      try {
        await pc.addTrack(t, s);
      } catch (e) {
        _log('addTrack ${t.kind} mislukt: $e');
      }
    }
  }

  Future<void> _removeStream(RTCPeerConnection pc, MediaStream? s) async {
    if (s == null) return;
    final ids = s.getTracks().map((t) => t.id).toSet();
    try {
      final senders = await pc.getSenders();
      for (final send in senders) {
        final t = send.track;
        if (t != null && ids.contains(t.id)) {
          try {
            await pc.removeTrack(send);
          } catch (e) {
            _log('removeTrack mislukt: $e');
          }
        }
      }
    } catch (e) {
      _log('getSenders mislukt: $e');
    }
  }

  void _log(String m) {
    // Silently weggooien is waarom bellen onbruikbaar leek: altijd zichtbaar.
    debugPrint('[calls] $m');
  }

  Future<void> _setupCaller() async {
    try {
      // Alleen bij video gaat de camera aan; scherm-delen deelt de schermstream.
      final wantVideo = kind == 'video';
      final media = await _media(video: wantVideo); // 1) media vÃƒÂ³ÃƒÂ³r de peer
      final pc = await _peer();
      await _addStream(pc, media);
      await _addStream(pc, _screen); // scherm al open vÃƒÂ³ÃƒÂ³r het gesprek
      _pc = pc;
      final offer = await pc.createOffer({});
      await pc.setLocalDescription(offer);
      _ready = true;
      _localOfferOut = true;
      _send({'t': 'signal', 'call': callId, 'data': {'type': 'offer', 'sdp': offer.sdp}});
      await _flushPending();
    } catch (e) {
      _log('caller-setup mislukt: $e');
      error = 'Gesprek starten mislukt';
      hangup();
    }
  }

  Future<void> _setupCallee() async {
    try {
      // Alleen bij video gaat de camera aan; scherm-delen deelt de schermstream.
      final wantVideo = kind == 'video';
      final media = await _media(video: wantVideo); // 1) media vÃƒÂ³ÃƒÂ³r de peer
      final pc = await _peer();
      await _addStream(pc, media);
      _pc = pc;
      _ready = true;
      await _flushPending();
    } catch (e) {
      _log('callee-setup mislukt: $e');
      error = 'Camera/microfoon niet beschikbaar';
      _rejectNu();
    }
  }

  /// Weigeren, ook als de status al omgezet is (accept() loopt vooruit).
  void _rejectNu() {
    _send({'t': 'reject', 'call': callId});
    _stopRinging();
    status = CallStatus.off;
    callId = null;
    _notify();
  }

  /// Signalen strikt ÃƒÂ©ÃƒÂ©n voor ÃƒÂ©ÃƒÂ©n afhandelen (anders kan een offer en een
  /// tegelijkertijd renegotiatie-offer elkaar omver werpen).
  Future<void> _sigQueue = Future.value();
  Future<void> _enqueue(Future<void> Function() fn) {
    _sigQueue = _sigQueue.then((_) => fn()).catchError((e) => _log('signaal mislukt: $e'));
    return _sigQueue;
  }

  Future<void> _flushPending() async {
    if (_pc == null) return;
    final wacht = [..._pending];
    _pending.clear();
    for (final m in wacht) {
      await _enqueue(() => _applySignal(_pc!, m));
    }
  }

  Future<void> _onSignal(Map<String, dynamic> data) async {
    if (!_ready || _pc == null) {
      _pending.add(data);
      return;
    }
    await _enqueue(() => _applySignal(_pc!, data));
  }

  Future<void> _applySignal(RTCPeerConnection pc, Map<String, dynamic> data) async {
    final type = (data['type'] ?? '').toString();
    try {
      if (type == 'offer') {
        // Glare: we hebben zelf een offer openstaan -> eerst rollback,
        // anders faalt setRemoteDescription stil en komt er nooit beeld.
        if (_localOfferOut) {
          try {
            await pc.setRemoteDescription(RTCSessionDescription(null, 'rollback'));
          } catch (e) {
            _log('rollback mislukt: $e');
          }
          _localOfferOut = false;
        }
        await pc.setRemoteDescription(RTCSessionDescription(data['sdp'], 'offer'));
        final answer = await pc.createAnswer({});
        await pc.setLocalDescription(answer);
        _send({'t': 'signal', 'call': callId, 'data': {'type': 'answer', 'sdp': answer.sdp}});
      } else if (type == 'answer') {
        await pc.setRemoteDescription(RTCSessionDescription(data['sdp'], 'answer'));
        _localOfferOut = false;
      } else if (type == 'ice') {
        final c = data['candidate'];
        if (c is Map) {
          await pc.addCandidate(RTCIceCandidate(
            c['candidate']?.toString() ?? '',
            c['sdpMid']?.toString(),
            (c['sdpMLineIndex'] as num?)?.toInt(),
          ));
        }
      }
    } catch (e) {
      _log('$type verwerken mislukt: $e');
    }
  }

  // ------------------------------------------------------------------ acties
  Future<void> invite(int toUid, String k) async {
    if (inCall) return;
    error = null;
    kind = k;
    isCaller = true;
    peerId = toUid;
    status = CallStatus.outgoing;
    statusText = 'VerbindenÃ¢â‚¬Â¦';
    _notify();
    await connect();
    if (_ws == null) {
      status = CallStatus.off;
      error = 'Geen verbinding met de server';
      _notify();
      return;
    }
    if (k == 'screen') {
      // Schermen delen als eerste: eigen scherm eerst openen.
      try {
        await startScreenShare(previewOnly: true);
      } catch (_) {}
    }
    _send({'t': 'invite', 'to': toUid, 'kind': k == 'screen' ? 'video' : k});
  }

  Future<void> accept() async {
    if (status != CallStatus.incoming) return;
    status = CallStatus.active;
    startedAt = DateTime.now();
    error = null;
    statusText = null;
    _stopRinging();
    _notify();
    _send({'t': 'accept', 'call': callId});
    try {
      await Helper.ensureAudioSession();
      if (!kIsWeb) await Helper.setSpeakerphoneOn(kind != 'audio');
    } catch (_) {}
  }

  void reject() {
    if (status != CallStatus.incoming) return;
    _send({'t': 'reject', 'call': callId});
    _stopRinging();
    status = CallStatus.off;
    callId = null;
    _notify();
  }

  Future<void> hangup() async {
    if (callId == null) return;
    _send({'t': 'hangup', 'call': callId});
    _stopRinging();
    await _teardown('hangup');
    status = CallStatus.off;
    callId = null;
    _notify();
  }

  /// Belussen + trilling zolang er niet opgenomen wordt.
  void _startRinging() {
    _stopRinging();
    SoundService.startCallRing();
    VoicePlatform.ringVibrate();
    _ring = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (status != CallStatus.incoming) {
        _stopRinging();
        return;
      }
      VoicePlatform.ringVibrate();
    });
  }

  void _stopRinging() {
    if (_ring == null) {
      // Toch nog de melding weghalen (bijv. bij een directe 'ended').
      LocalNotify.cancel(LocalNotify.callId);
      return;
    }
    _ring?.cancel();
    _ring = null;
    SoundService.stopCallRing();
    LocalNotify.cancel(LocalNotify.callId);
  }

  Future<void> _teardown(String reason) async {
    _stopRinging();
    _ready = false;
    _pending.clear();
    _remote = null;
    final pc = _pc;
    _pc = null;
    try {
      await pc?.close();
      await pc?.dispose();
    } catch (_) {}
    for (final s in [localStream, _screen]) {
      try {
        for (final t in s?.getTracks() ?? <MediaStreamTrack>[]) {
          t.stop();
        }
        await s?.dispose();
      } catch (_) {}
    }
    localStream = null;
    _screen = null;
    remoteStream = null;
    screenOn = false;
    camOn = true;
    micOn = true;
  }

  Future<void> toggleMic() async {
    micOn = !micOn;
    for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = micOn;
    }
    _notify();
  }

  Future<void> toggleCam() async {
    camOn = !camOn;
    for (final t in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = camOn;
    }
    _notify();
  }

  /// Scherm delen tijdens een gesprek (of als preview vÃƒÂ³ÃƒÂ³r het gesprek).
  Future<void> startScreenShare({bool previewOnly = false}) async {
    final s = await navigator.mediaDevices.getDisplayMedia({
      'audio': false,
      'video': {'width': {'ideal': 1280}, 'height': {'ideal': 720}},
    });
    _screen = s;
    screenOn = true;
    for (final t in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = false;
    }
    final pc = _pc;
    if (pc != null && _ready) {
      await _addStream(pc, s);
      try {
        final offer = await pc.createOffer({});
        await pc.setLocalDescription(offer);
        _localOfferOut = true;
        _send({'t': 'signal', 'call': callId, 'data': {'type': 'offer', 'sdp': offer.sdp}});
      } catch (e) {
        _log('renegotiatie (scherm aan) mislukt: $e');
      }
    }
    s.getVideoTracks().firstOrNull?.onEnded = () {
      stopScreenShare();
    };
    _notify();
    if (previewOnly) return;
  }

  Future<void> stopScreenShare() async {
    final s = _screen;
    _screen = null;
    screenOn = false;
    final pc = _pc;
    if (pc != null && s != null) {
      try {
        await _removeStream(pc, s);
        final offer = await pc.createOffer({});
        await pc.setLocalDescription(offer);
        _localOfferOut = true;
        _send({'t': 'signal', 'call': callId, 'data': {'type': 'offer', 'sdp': offer.sdp}});
      } catch (e) {
        _log('renegotiatie (scherm uit) mislukt: $e');
      }
    }
    for (final t in s?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    try {
      await s?.dispose();
    } catch (_) {}
    for (final t in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = camOn;
    }
    _notify();
  }

  Future<void> toggleScreen() async {
    if (screenOn) {
      await stopScreenShare();
    } else {
      try {
        await startScreenShare();
      } catch (_) {
        error = 'Schermdelen niet toegestaan';
        _notify();
      }
    }
  }

  // -------------------------------------------------------- gemiste gesprekken
  /// Ophalen uit de backend (laatste 40) Ã¢â‚¬â€ voor de DM-inbox en belbel.
  Future<void> loadMissed() async {
    try {
      final rows = await ApiService().apiGet('/wolfsyn/calls');
      missed
        ..clear()
        ..addAll((rows as List)
            .where((r) => r is Map && r['gemist'] == true)
            .cast<Map<String, dynamic>>());
      _notify();
    } catch (_) {}
  }

  int missedFor(int uid) => missed.where((m) => (m['partner'] is Map ? (m['partner']['id'] as num?)?.toInt() : null) == uid).length;
}
