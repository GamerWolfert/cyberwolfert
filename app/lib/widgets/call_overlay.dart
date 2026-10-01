import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';

/// AeroTalk-gesprek: alles over elke schermlaag heen (via main.dart).
/// - inkomend: balk bovenaan met aannemen/weigeren
/// - uitgaand/actief: volledig scherm met video, bediening en belduur
class CallOverlay extends StatefulWidget {
  const CallOverlay({super.key});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  final CallService _c = CallService.instance;
  final RTCVideoRenderer _local = RTCVideoRenderer();
  final RTCVideoRenderer _remote = RTCVideoRenderer();
  Timer? _tick;
  int _sec = 0;

  @override
  void initState() {
    super.initState();
    _local.initialize().then((_) => _sync());
    _remote.initialize().then((_) => _sync());
    _c.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final s = _c.startedAt;
      final n = s == null ? 0 : DateTime.now().difference(s).inSeconds;
      if (n != _sec) setState(() => _sec = n);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _c.removeListener(_changed);
    _local.dispose();
    _remote.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
    _sync();
  }

  void _sync() {
    try {
      final wantLocal = _c.screenOn && _c.localScreen != null
          ? _c.localScreen
          : _c.localStream;
      if (_local.srcObject != wantLocal) _local.srcObject = wantLocal;
      if (_remote.srcObject != _c.remoteStream) _remote.srcObject = _c.remoteStream;
    } catch (_) {}
  }

  String _duur() {
    final m = (_sec ~/ 60).toString().padLeft(2, '0');
    final s = (_sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final st = _c.status;
    if (st == CallStatus.off) return _foutmelding(context);
    if (st == CallStatus.incoming) return _incoming(context);
    if (st == CallStatus.outgoing) return _outgoing(context);
    return _active(context);
  }

  /// Kort meldingskaartje als er geen gesprek is maar wél een reden
  /// (bv. "is offline", "geweigerd", "verbinding verloren").
  Widget _foutmelding(BuildContext context) {
    final fout = _c.error;
    if (fout == null || fout.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Material(
            color: Colors.red.shade800,
            borderRadius: BorderRadius.circular(12),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(fout,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- inkomend
  Widget _incoming(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final videoCall = _c.kind != 'audio';
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: const Color(0xFF121812),
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: cs.primary,
                    child: Icon(
                      _c.kind == 'screen'
                          ? Icons.screen_share
                          : videoCall
                              ? Icons.videocam
                              : Icons.call,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_c.peerName.isEmpty ? 'Onbekend' : _c.peerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(
                          _c.kind == 'screen'
                              ? 'wil zijn/haar scherm delen'
                              : videoCall
                                  ? 'video-oproep'
                                  : 'audiogesprek',
                          style: const TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  _roundBtn(Icons.close, Colors.redAccent, () => _c.reject()),
                  const SizedBox(width: 8),
                  _roundBtn(Icons.call, Colors.greenAccent.shade400, () => _c.accept()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- uitgaand
  Widget _outgoing(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: const Color(0xFF121812),
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Bellen…',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: cs.primary)),
                        Text(
                          _c.statusText ?? '',
                          style: const TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  _roundBtn(Icons.call_end, Colors.redAccent, () => _c.hangup()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- actief
  Widget _active(BuildContext context) {
    final videoCall = _c.kind != 'audio' || _c.screenOn;
    final showLocal = _c.kind != 'audio';
    return Material(
      color: const Color(0xFF070B07),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (videoCall && _c.remoteStream != null)
              RTCVideoView(_remote,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        _c.peerName.isEmpty
                            ? '?'
                            : _c.peerName.characters.first.toUpperCase(),
                        style: const TextStyle(fontSize: 44, color: Colors.black),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(_c.peerName,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(_duur(),
                        style: const TextStyle(fontSize: 16, color: Colors.white70)),
                  ],
                ),
              ),
            // Lokale preview (hoek) bij video/scherm.
            if (showLocal && (_c.localStream != null || _c.screenOn))
              Positioned(
                right: 14,
                top: 14,
                child: Container(
                  width: 116,
                  height: 164,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 8)
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RTCVideoView(_local, mirror: !_c.screenOn),
                ),
              ),
            // Bovenbalk: naam + belduur.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent]),
                ),
                child: Column(
                  children: [
                    Text(
                      _c.statusText ?? _c.peerName,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    if (_c.startedAt != null)
                      Text(
                        _c.screenOn ? 'Scherm delen · ${_duur()}' : _duur(),
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                  ],
                ),
              ),
            ),
            // Onderbalk: bediening.
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ctrl(Icons.mic, Icons.mic_off, _c.micOn, () => _c.toggleMic()),
                  if (_c.kind != 'audio')
                    _ctrl(Icons.videocam, Icons.videocam_off, _c.camOn,
                        () => _c.toggleCam()),
                  _ctrl(Icons.screen_share, Icons.stop_screen_share, _c.screenOn,
                      () => _c.toggleScreen()),
                  _roundBtn(Icons.call_end, Colors.redAccent, () => _c.hangup(),
                      size: 30),
                ],
              ),
            ),
            if (_c.error != null)
              Positioned(
                bottom: 96,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(_c.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ctrl(IconData on, IconData off, bool active, VoidCallback fn) {
    return Material(
      color: active ? Colors.white12 : Colors.white24,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: fn,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(active ? on : off,
            color: active ? Colors.white : Colors.white38, size: 26),
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, Color color, VoidCallback fn, {double size = 24}) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: fn,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: Colors.black, size: size),
        ),
      ),
    );
  }
}
