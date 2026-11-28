import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../api.dart';
import '../widgets.dart';
import '../main.dart';
import 'call.dart';

const stickers = ['😀','😂','😍','🥰','😎','🤔','😭','😡','👍','👏','🙏','🎉','❤️','🔥','💯','👌'];
const kMineBubble = Color(0xFFFFC1DD);

String fmtSize(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
String fmtDur(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

class ChatScreen extends StatefulWidget {
  final int conversationId; final String title; final Map? peer; final bool isGroup;
  const ChatScreen({super.key, required this.conversationId, required this.title, this.peer, this.isGroup = false});
  @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final List<Map> msgs = []; final input = TextEditingController(); final scroll = ScrollController();
  StreamSubscription? sub; int peerRead = 0; bool showStickers = false; bool sending = false;
  late String title = widget.title;
  // voice recording
  final AudioRecorder rec = AudioRecorder();
  bool recording = false; int recSecs = 0; Timer? recTimer; String? recPath;
  int get myId => Api.me?['id'] ?? 0;

  @override
  void initState() {
    super.initState();
    Poller.openConversation = widget.conversationId;
    load();
    sub = Poller.messages.stream.listen((list) {
      bool changed = false;
      for (final m in list) {
        if (m['conversation_id'] != widget.conversationId) continue;
        if (m['type'] == 'deleted') { _markDeleted(int.tryParse('${m['content']}') ?? 0); changed = true; continue; }
        if (!msgs.any((x) => x['id'] == m['id'])) { msgs.add(Map.from(m)); changed = true; }
      }
      if (changed && mounted) { setState(() {}); markRead(); toBottom(); }
      refreshRead();
    });
  }
  @override
  void dispose() {
    sub?.cancel(); recTimer?.cancel(); rec.dispose(); VoicePlayer.stopAll();
    Poller.openConversation = null; super.dispose();
  }

  void _markDeleted(int id) {
    for (final x in msgs) { if (x['id'] == id) { x['deleted'] = 1; x['content'] = null; } }
  }
  Future<void> load() async {
    try {
      final r = await Api.get('messages', {'conversation_id': widget.conversationId, 'limit': 80});
      setState(() { msgs..clear()..addAll((r['messages'] as List).map((e) => Map.from(e))); _setRead(r['read_by']); });
      markRead(); toBottom();
    } catch (e) { if (mounted) toast(context, e); }
  }
  Future<void> loadOlder() async {
    if (msgs.isEmpty) return;
    final r = await Api.get('messages', {'conversation_id': widget.conversationId, 'before_id': msgs.first['id'], 'limit': 50});
    setState(() => msgs.insertAll(0, (r['messages'] as List).map((e) => Map.from(e))));
  }
  Future<void> refreshRead() async {
    try { final r = await Api.get('messages', {'conversation_id': widget.conversationId, 'after_id': 1 << 40, 'limit': 1}); if (mounted) setState(() => _setRead(r['read_by'])); } catch (_) {}
  }
  void _setRead(List rb) { if (rb.isNotEmpty) peerRead = rb.map((e) => e['last_read_message_id'] as int).reduce((a, b) => a < b ? a : b); }
  void markRead() => Api.post('mark_read', {'conversation_id': widget.conversationId}).catchError((_) => <String, dynamic>{});
  void toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent); });

  Future<void> _send(Future<Map<String, dynamic>> f) async {
    setState(() => sending = true);
    try { final r = await f; final m = Map.from(r['message']);
      if (!msgs.any((x) => x['id'] == m['id'])) setState(() => msgs.add(m)); toBottom();
    } catch (e) { if (mounted) toast(context, e); } finally { if (mounted) setState(() => sending = false); }
  }
  Map<String, String> get _cid => {'conversation_id': '${widget.conversationId}'};
  void sendText() { final t = input.text.trim(); if (t.isEmpty) return; input.clear();
    _send(Api.post('send_message', {'conversation_id': widget.conversationId, 'type': 'text', 'content': t})); }
  void sendSticker(String s) => _send(Api.post('send_message', {'conversation_id': widget.conversationId, 'type': 'sticker', 'content': s}));
  Future<void> sendImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
    if (x != null) _send(Api.upload('send_message', 'image', x.path, _cid));
  }
  Future<void> sendFile() async {
    final r = await FilePicker.platform.pickFiles(withData: false);
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    if (f.size > 25 * 1024 * 1024) { toast(context, 'ไฟล์ใหญ่เกินไป (สูงสุด 25MB)'); return; }
    _send(Api.upload('send_message', 'file', f.path!, _cid));
  }
  void showAttach() => showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Wrap(children: [
    ListTile(leading: const Icon(Icons.image_outlined, color: kPrimary), title: const Text('รูปภาพ'), onTap: () { Navigator.pop(c); sendImage(); }),
    ListTile(leading: const Icon(Icons.attach_file, color: kPrimary), title: const Text('ไฟล์ (สูงสุด 25MB)'), onTap: () { Navigator.pop(c); sendFile(); }),
  ])));

  // ---------- voice ----------
  Future<void> startRec() async {
    if (recording || sending) return;
    if (!await rec.hasPermission()) { if (mounted) toast(context, 'กรุณาอนุญาตการใช้ไมโครโฟน'); return; }
    final dir = await getTemporaryDirectory();
    recPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: recPath!);
    setState(() { recording = true; recSecs = 0; });
    recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => recSecs++);
      if (recSecs >= 300) stopRec(send: true);
    });
  }
  Future<void> stopRec({required bool send}) async {
    if (!recording) return;
    recTimer?.cancel();
    final path = await rec.stop();
    final secs = recSecs;
    setState(() => recording = false);
    if (!send || path == null) { if (path != null) { try { File(path).deleteSync(); } catch (_) {} } return; }
    if (secs < 1) { toast(context, 'กดค้างเพื่ออัดเสียง'); return; }
    _send(Api.upload('send_message', 'voice', path, {..._cid, 'duration': '$secs'}));
  }

  // ---------- unsend ----------
  bool _canUnsend(Map m) => m['sender_id'] == myId && (m['deleted'] ?? 0) == 0 &&
      ['text', 'image', 'sticker', 'file', 'voice'].contains(m['type']);
  Future<void> onLongPress(Map m) async {
    final isText = m['type'] == 'text' && (m['deleted'] ?? 0) == 0;
    final canDel = _canUnsend(m);
    if (!isText && !canDel) return;
    final a = await showModalBottomSheet<String>(context: context, builder: (c) => SafeArea(child: Wrap(children: [
      if (isText) ListTile(leading: const Icon(Icons.copy), title: const Text('คัดลอก'), onTap: () => Navigator.pop(c, 'copy')),
      if (canDel) ListTile(leading: const Icon(Icons.undo, color: Colors.red), title: const Text('ยกเลิกข้อความ (ลบสำหรับทุกคน)', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(c, 'unsend')),
    ])));
    if (!mounted || a == null) return;
    if (a == 'copy') {
      await Clipboard.setData(ClipboardData(text: '${m['content'] ?? ''}'));
      if (mounted) toast(context, 'คัดลอกแล้ว');
    } else if (a == 'unsend') {
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('ยกเลิกข้อความนี้?'), content: const Text('ข้อความจะถูกลบสำหรับทุกคนในแชท'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ไม่')),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('ยกเลิกข้อความ'))]));
      if (ok != true) return;
      try { await Api.post('delete_message', {'message_id': m['id']}); setState(() => _markDeleted(m['id'] as int)); }
      catch (e) { if (mounted) toast(context, e); }
    }
  }

  Future<void> openFile(Map m) async {
    final url = '${m['content']}';
    final name = '${m['file_name'] ?? 'file'}';
    toast(context, 'กำลังดาวน์โหลด $name ...');
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${m['id']}_${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}');
      if (!await f.exists()) {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 3));
        if (r.statusCode != 200) throw 'ดาวน์โหลดไม่สำเร็จ (${r.statusCode})';
        await f.writeAsBytes(r.bodyBytes);
      }
      final res = await OpenFilex.open(f.path);
      if (res.type != ResultType.done && mounted) toast(context, 'ไม่มีแอปที่เปิดไฟล์นี้ได้');
    } catch (e) { if (mounted) toast(context, e); }
  }

  Widget bubble(Map m) {
    if (m['type'] == 'system') return Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)), child: Text(m['content'] ?? '', style: const TextStyle(fontSize: 12))));
    if (m['type'] == 'deleted') return const SizedBox.shrink();
    final mine = m['sender_id'] == myId;
    final deleted = (m['deleted'] ?? 0) != 0;
    final maxW = MediaQuery.of(context).size.width * .7;
    BoxDecoration box() => BoxDecoration(color: mine ? kMineBubble : Colors.white, borderRadius: BorderRadius.circular(16));
    Widget content;
    if (deleted) {
      content = Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.block, size: 15, color: Colors.black45), const SizedBox(width: 6),
          Text(mine ? 'คุณยกเลิกข้อความแล้ว' : 'ข้อความถูกยกเลิกแล้ว', style: const TextStyle(color: Colors.black54, fontStyle: FontStyle.italic, fontSize: 13))]));
    } else {
      switch (m['type']) {
        case 'image': content = ClipRRect(borderRadius: BorderRadius.circular(12), child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(),
              body: Center(child: InteractiveViewer(child: Image.network(m['content'])))))),
            child: Image.network(m['content'], width: 200, fit: BoxFit.cover))); break;
        case 'sticker': content = Text(m['content'] ?? '', style: const TextStyle(fontSize: 56)); break;
        case 'call': content = Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.call, size: 18), const SizedBox(width: 6), Text(m['content'] ?? '')])); break;
        case 'file': content = InkWell(onTap: () => openFile(m), child: Container(constraints: BoxConstraints(maxWidth: maxW),
            padding: const EdgeInsets.all(10), decoration: box(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const CircleAvatar(radius: 20, backgroundColor: kPrimary, child: Icon(Icons.insert_drive_file, color: Colors.white, size: 20)),
              const SizedBox(width: 10),
              Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m['file_name'] ?? 'ไฟล์'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${fmtSize(m['file_size'] as int?)} · แตะเพื่อเปิด', style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ])),
            ]))); break;
        case 'voice': content = Container(decoration: box(), padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: VoicePlayer(url: '${m['content']}', duration: (m['duration'] as int?) ?? 0)); break;
        default: content = Container(constraints: BoxConstraints(maxWidth: maxW),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: box(),
            child: Text(m['content'] ?? '', style: const TextStyle(fontSize: 15)));
      }
    }
    content = GestureDetector(onLongPress: () => onLongPress(m), child: content);
    final meta = Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (mine && !deleted && (m['id'] as int) <= peerRead) const Text('อ่านแล้ว', style: TextStyle(fontSize: 10, color: Colors.black54)),
      Text(hhmm(m['created_at']), style: const TextStyle(fontSize: 10, color: Colors.black54)),
    ]);
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.end,
      children: mine ? [meta, const SizedBox(width: 4), Flexible(child: content)] : [
        Avatar(m['sender_avatar'], m['sender_name'] ?? '', size: 32), const SizedBox(width: 6),
        Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.isGroup) Text(m['sender_name'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.black54)), content])),
        const SizedBox(width: 4), meta]));
  }

  Widget inputBar() {
    if (recording) {
      return Row(children: [
        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'ยกเลิก', onPressed: () => stopRec(send: false)),
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14), const SizedBox(width: 6),
        Text('กำลังอัดเสียง ${fmtDur(recSecs)}', style: const TextStyle(fontSize: 15)),
        const Spacer(),
        IconButton(icon: const Icon(Icons.send, color: kPrimary), tooltip: 'ส่ง', onPressed: () => stopRec(send: true)),
      ]);
    }
    return Row(children: [
      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: sending ? null : showAttach),
      IconButton(icon: const Icon(Icons.emoji_emotions_outlined), onPressed: () => setState(() => showStickers = !showStickers)),
      Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => sendText(),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(hintText: 'Aa', border: InputBorder.none))),
      if (input.text.trim().isEmpty)
        IconButton(icon: const Icon(Icons.mic, color: kPrimary), tooltip: 'อัดข้อความเสียง', onPressed: sending ? null : startRec)
      else
        IconButton(icon: const Icon(Icons.send, color: kPrimary), onPressed: sending ? null : sendText),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EF),
      appBar: AppBar(title: Text(title), actions: [
        if (!widget.isGroup && peer != null) ...[
          IconButton(icon: const Icon(Icons.call), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
              CallScreen.outgoing(peerId: peer['id'], peerName: peer['display_name'], peerAvatar: peer['avatar_url'], video: false)))),
          IconButton(icon: const Icon(Icons.videocam), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
              CallScreen.outgoing(peerId: peer['id'], peerName: peer['display_name'], peerAvatar: peer['avatar_url'], video: true)))),
        ],
        PopupMenuButton<String>(onSelected: (v) async {
          if (v != 'del') return;
          final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
            title: const Text('ลบแชทนี้?'), content: const Text('ประวัติแชทจะถูกลบจากเครื่องของคุณ (อีกฝ่ายยังเห็นอยู่)'),
            actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ยกเลิก')),
                      FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(d, true), child: const Text('ลบแชท'))]));
          if (ok != true) return;
          try { await Api.post('delete_chat', {'conversation_id': widget.conversationId}); if (mounted) Navigator.pop(context); }
          catch (e) { if (mounted) toast(context, e); }
        }, itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('ลบแชท', style: TextStyle(color: Colors.red)))]),
        if (widget.isGroup) IconButton(icon: const Icon(Icons.info_outline), onPressed: () async {
            final n = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => GroupInfoScreen(widget.conversationId)));
            if (n != null && mounted) setState(() => title = n);
          }),
      ]),
      body: Column(children: [
        Expanded(child: NotificationListener<ScrollNotification>(
          onNotification: (n) { if (n.metrics.pixels <= 0 && n is ScrollEndNotification) loadOlder(); return false; },
          child: ListView.builder(controller: scroll, itemCount: msgs.length, itemBuilder: (_, i) => bubble(msgs[i])))),
        if (sending) const LinearProgressIndicator(minHeight: 2, color: kPrimary),
        if (showStickers && !recording) Container(color: Colors.white, height: 180, child: GridView.count(crossAxisCount: 8,
          children: [for (final s in stickers) InkWell(onTap: () => sendSticker(s), child: Center(child: Text(s, style: const TextStyle(fontSize: 30))))])),
        Container(color: Colors.white, child: SafeArea(top: false, child: inputBar())),
      ]),
    );
  }
}

/// Small play/pause widget for voice messages. Only one plays at a time.
class VoicePlayer extends StatefulWidget {
  final String url; final int duration;
  const VoicePlayer({super.key, required this.url, required this.duration});
  static final Set<_VoicePlayerState> _all = {};
  static void stopAll() { for (final s in _all.toList()) { s.stop(); } }
  @override State<VoicePlayer> createState() => _VoicePlayerState();
}
class _VoicePlayerState extends State<VoicePlayer> {
  final AudioPlayer p = AudioPlayer();
  bool playing = false; Duration pos = Duration.zero;
  final List<StreamSubscription> subs = [];
  @override
  void initState() {
    super.initState();
    VoicePlayer._all.add(this);
    subs.add(p.onPositionChanged.listen((d) { if (mounted) setState(() => pos = d); }));
    subs.add(p.onPlayerComplete.listen((_) { if (mounted) setState(() { playing = false; pos = Duration.zero; }); }));
  }
  @override
  void dispose() { VoicePlayer._all.remove(this); for (final s in subs) { s.cancel(); } p.dispose(); super.dispose(); }
  void stop() { p.stop(); if (mounted) setState(() { playing = false; pos = Duration.zero; }); }
  Future<void> toggle() async {
    try {
      if (playing) { await p.pause(); setState(() => playing = false); return; }
      for (final o in VoicePlayer._all.toList()) { if (o != this) o.stop(); }
      await p.play(UrlSource(widget.url));
      setState(() => playing = true);
    } catch (e) { if (mounted) toast(context, 'เล่นเสียงไม่ได้'); }
  }
  @override
  Widget build(BuildContext context) {
    final total = widget.duration > 0 ? widget.duration : 1;
    final shown = playing || pos > Duration.zero ? pos.inSeconds : widget.duration;
    return SizedBox(width: 190, child: Row(children: [
      IconButton(icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: kPrimary, size: 34), onPressed: toggle),
      Expanded(child: LinearProgressIndicator(value: (pos.inMilliseconds / 1000 / total).clamp(0.0, 1.0), color: kPrimary, backgroundColor: Colors.black12)),
      const SizedBox(width: 8),
      Text(fmtDur(shown), style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 6),
    ]));
  }
}

class GroupInfoScreen extends StatefulWidget {
  final int id; const GroupInfoScreen(this.id, {super.key});
  @override State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}
class _GroupInfoScreenState extends State<GroupInfoScreen> {
  Map? conv; bool uploading = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { final r = await Api.get('conversation', {'conversation_id': widget.id}); if (mounted) setState(() => conv = r['conversation']); }
  Future<void> changePhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (x == null) return;
    setState(() => uploading = true);
    try {
      await Api.upload('group_update', 'avatar', x.path, {'conversation_id': '${widget.id}'});
      await load();
      if (mounted) toast(context, 'เปลี่ยนรูปกลุ่มแล้ว');
    } catch (e) { if (mounted) toast(context, e); }
    finally { if (mounted) setState(() => uploading = false); }
  }
  Future<void> addMembers() async {
    final fr = (await Api.get('friends'))['friends'] as List;
    final memberIds = (conv!['members'] as List).map((m) => m['id']).toSet();
    final cand = fr.where((f) => !memberIds.contains(f['id'])).toList();
    final sel = <int>{};
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('เพิ่มสมาชิก'),
      content: SizedBox(width: 300, child: cand.isEmpty ? const Text('ไม่มีเพื่อนที่เพิ่มได้') : ListView(shrinkWrap: true, children: [
        for (final f in cand) CheckboxListTile(value: sel.contains(f['id']), title: Text(f['display_name']),
          onChanged: (v) => set(() => v! ? sel.add(f['id']) : sel.remove(f['id'])))])),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ยกเลิก')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('เพิ่ม'))])));
    if (ok == true && sel.isNotEmpty) { await Api.post('group_add', {'conversation_id': widget.id, 'user_ids': sel.toList()}); load(); }
  }
  Future<void> rename() async {
    final c = TextEditingController(text: conv!['name']);
    final n = await showDialog<String>(context: context, builder: (d) => AlertDialog(title: const Text('เปลี่ยนชื่อกลุ่ม'),
      content: TextField(controller: c), actions: [FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('บันทึก'))]));
    if (n != null && n.trim().isNotEmpty) { await Api.post('group_update', {'conversation_id': widget.id, 'name': n.trim()}); load(); }
  }
  Future<void> leave() async {
    await Api.post('group_leave', {'conversation_id': widget.id});
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (did, _) { if (!did) Navigator.pop(context, conv?['name'] as String?); },
    child: Scaffold(
    appBar: AppBar(title: const Text('ข้อมูลกลุ่ม')),
    body: conv == null ? const Center(child: CircularProgressIndicator()) : ListView(children: [
      const SizedBox(height: 20),
      Center(child: Stack(children: [
        conv!['avatar_url'] == null
          ? const CircleAvatar(radius: 56, backgroundColor: Color(0x22E6197A), child: Icon(Icons.groups, color: kPrimary, size: 56))
          : Avatar(conv!['avatar_url'], conv!['name'] ?? '', size: 112),
        Positioned(right: 0, bottom: 0, child: CircleAvatar(backgroundColor: kPrimary,
          child: uploading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : IconButton(icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20), tooltip: 'เปลี่ยนรูปกลุ่ม', onPressed: changePhoto))),
      ])),
      const SizedBox(height: 8),
      ListTile(title: Text(conv!['name'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        trailing: IconButton(icon: const Icon(Icons.edit), tooltip: 'เปลี่ยนชื่อกลุ่ม', onPressed: rename)),
      ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('เปลี่ยนรูปกลุ่ม'), onTap: uploading ? null : changePhoto),
      ListTile(leading: const Icon(Icons.person_add), title: const Text('เพิ่มสมาชิก'), onTap: addMembers),
      const Divider(),
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('สมาชิก (${(conv!['members'] as List).length})', style: const TextStyle(color: Colors.grey))),
      for (final m in conv!['members']) ListTile(leading: Avatar(m['avatar_url'], m['display_name']), title: Text(m['display_name']),
        trailing: m['role'] == 'admin' ? const Text('แอดมิน', style: TextStyle(color: kPrimary)) : null),
      const Divider(),
      ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('ออกจากกลุ่ม', style: TextStyle(color: Colors.red)), onTap: leave),
    ]),
  ));
}
