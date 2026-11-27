import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../api.dart';
import '../widgets.dart';

/// 1:1 voice / video call using WebRTC; signaling via PHP polling.
class CallScreen extends StatefulWidget {
  static bool active = false;
  final bool outgoingCall, video; final int? peerId; final int? callId; final String peerName; final String? peerAvatar;
  const CallScreen.outgoing({super.key, required int this.peerId, required this.peerName, this.peerAvatar, required this.video})
      : outgoingCall = true, callId = null;
  const CallScreen.incoming({super.key, required int this.callId, required this.peerName, this.peerAvatar, required this.video})
      : outgoingCall = false, peerId = null;
  @override State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? pc; MediaStream? local;
  final localR = RTCVideoRenderer(), remoteR = RTCVideoRenderer();
  int? callId; String status = ''; Timer? poll, clock; bool ended = false, answered = false, muted = false, speaker = false;
  int seconds = 0; List iceServers = [];
  final List<RTCIceCandidate> pendingRemote = []; bool remoteSet = false;

  @override
  void initState() {
    super.initState();
    CallScreen.active = true;
    localR.initialize(); remoteR.initialize();
    speaker = widget.video;
    if (widget.outgoingCall) { status = 'กำลังโทร...'; _startOutgoing(); }
    else { callId = widget.callId; status = widget.video ? 'วิดีโอคอลเข้า' : 'สายเรียกเข้า'; _poll(); }
  }

  Future<void> _media() async {
    local = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': widget.video ? {'facingMode': 'user'} : false});
    localR.srcObject = local;
    pc = await createPeerConnection({'iceServers': iceServers, 'sdpSemantics': 'unified-plan'});
    for (final t in local!.getTracks()) { await pc!.addTrack(t, local!); }
    pc!.onIceCandidate = (c) { if (c.candidate != null) _signal('candidate', {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}); };
    pc!.onTrack = (e) { if (e.streams.isNotEmpty) setState(() => remoteR.srcObject = e.streams[0]); };
    pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) { _startClock(); }
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) { setState(() => status = 'เชื่อมต่อไม่สำเร็จ'); _hangup(); }
    };
    Helper.setSpeakerphoneOn(speaker);
  }

  Future<void> _startOutgoing() async {
    try {
      final r = await Api.post('call_start', {'user_id': widget.peerId, 'call_type': widget.video ? 'video' : 'voice'});
      callId = r['call_id']; iceServers = r['ice_servers'];
      await _media();
      final offer = await pc!.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': widget.video});
      await pc!.setLocalDescription(offer);
      await _signal('offer', {'sdp': offer.sdp, 'type': offer.type});
      _poll();
    } catch (e) { setState(() => status = e.toString()); await Future.delayed(const Duration(seconds: 2)); _close(); }
  }

  Future<void> _answer() async {
    setState(() { answered = true; status = 'กำลังเชื่อมต่อ...'; });
    try {
      final r = await Api.post('call_answer', {'call_id': callId, 'accept': 1});
      iceServers = r['ice_servers'];
      await _media();
    } catch (e) { toast(context, e); _close(); }
  }
  Future<void> _reject() async { try { await Api.post('call_answer', {'call_id': callId, 'accept': 0}); } catch (_) {} _close(); }

  Future<void> _signal(String type, Map payload) =>
      Api.post('call_signal', {'call_id': callId, 'signal_type': type, 'payload': jsonEncode(payload)}).catchError((_) => <String, dynamic>{});

  void _poll() { poll?.cancel(); poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _tick()); }
  final List<Map> _queued = []; bool _busy = false;
  Future<void> _tick() async {
    if (callId == null || ended || _busy) return;
    _busy = true;
    try {
      final r = await Api.get('call_poll', {'call_id': callId});
      final st = r['status'];
      if (widget.outgoingCall && st == 'accepted' && !answered) setState(() { answered = true; status = 'กำลังเชื่อมต่อ...'; });
      if (st == 'rejected') { setState(() => status = 'ปลายสายปฏิเสธ'); return _endSoon(); }
      if (st == 'missed') { setState(() => status = 'ไม่มีผู้รับสาย'); return _endSoon(); }
      if (st == 'ended') { setState(() => status = 'วางสายแล้ว'); return _endSoon(); }
      _queued.addAll((r['signals'] as List).map((e) => Map.from(e)));
      if (pc != null) { while (_queued.isNotEmpty) { await _handle(_queued.removeAt(0)); } }
    } catch (_) {} finally { _busy = false; }
  }
  Future<void> _handle(Map s) async {
    final type = s['signal_type'];
    if (type == 'hangup') { setState(() => status = 'วางสายแล้ว'); return _endSoon(); }
    final p = jsonDecode(s['payload'] ?? '{}');
    if (type == 'offer') {
      await pc!.setRemoteDescription(RTCSessionDescription(p['sdp'], p['type']));
      remoteSet = true; await _flush();
      final ans = await pc!.createAnswer();
      await pc!.setLocalDescription(ans);
      await _signal('answer', {'sdp': ans.sdp, 'type': ans.type});
    } else if (type == 'answer') {
      await pc!.setRemoteDescription(RTCSessionDescription(p['sdp'], p['type']));
      remoteSet = true; await _flush();
    } else if (type == 'candidate') {
      final c = RTCIceCandidate(p['candidate'], p['sdpMid'], p['sdpMLineIndex']);
      if (remoteSet) { await pc!.addCandidate(c); } else { pendingRemote.add(c); }
    }
  }
  Future<void> _flush() async { for (final c in pendingRemote) { await pc!.addCandidate(c); } pendingRemote.clear(); }

  void _startClock() { if (clock != null) return; clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {
    seconds++; status = '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'; })); }

  Future<void> _hangup() async { if (callId != null && !ended) { try { await Api.post('call_end', {'call_id': callId}); } catch (_) {} } _close(); }
  void _endSoon() { if (ended) return; ended = true; Future.delayed(const Duration(milliseconds: 1500), _close); }
  void _close() { ended = true; if (mounted && Navigator.canPop(context)) Navigator.pop(context); }

  @override
  void dispose() {
    CallScreen.active = false;
    poll?.cancel(); clock?.cancel();
    if (!ended && callId != null) { Api.post('call_end', {'call_id': callId}).catchError((_) => <String, dynamic>{}); }
    local?.getTracks().forEach((t) => t.stop()); local?.dispose(); pc?.close();
    localR.dispose(); remoteR.dispose();
    super.dispose();
  }

  Widget _round(IconData i, Color c, VoidCallback f, {String? label}) => Column(mainAxisSize: MainAxisSize.min, children: [
    RawMaterialButton(onPressed: f, fillColor: c, shape: const CircleBorder(), padding: const EdgeInsets.all(18), child: Icon(i, color: Colors.white, size: 30)),
    if (label != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(label, style: const TextStyle(color: Colors.white))),
  ]);

  @override
  Widget build(BuildContext context) {
    final ringingIn = !widget.outgoingCall && !answered;
    return PopScope(canPop: false, child: Scaffold(backgroundColor: const Color(0xFF1E2A33), body: Stack(children: [
      if (widget.video && remoteR.srcObject != null) Positioned.fill(child: RTCVideoView(remoteR, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
      if (widget.video && local != null) Positioned(right: 16, top: 48, width: 110, height: 160,
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: RTCVideoView(localR, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))),
      SafeArea(child: Column(children: [
        const SizedBox(height: 60),
        if (!(widget.video && remoteR.srcObject != null)) ...[
          Avatar(widget.peerAvatar, widget.peerName, size: 120), const SizedBox(height: 16),
        ],
        Text(widget.peerName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(status, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const Spacer(),
        if (ringingIn) Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _round(Icons.call_end, Colors.red, _reject, label: 'ปฏิเสธ'),
          _round(widget.video ? Icons.videocam : Icons.call, kCallGreen, _answer, label: 'รับสาย'),
        ]) else Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _round(muted ? Icons.mic_off : Icons.mic, Colors.white24, () { muted = !muted; local?.getAudioTracks().forEach((t) => t.enabled = !muted); setState(() {}); }),
          _round(Icons.call_end, Colors.red, _hangup),
          if (widget.video) _round(Icons.cameraswitch, Colors.white24, () { final t = local?.getVideoTracks(); if (t != null && t.isNotEmpty) Helper.switchCamera(t.first); })
          else _round(speaker ? Icons.volume_up : Icons.hearing, Colors.white24, () { speaker = !speaker; Helper.setSpeakerphoneOn(speaker); setState(() {}); }),
        ]),
        const SizedBox(height: 48),
      ])),
    ])));
  }
}
