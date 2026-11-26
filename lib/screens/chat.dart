import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../widgets.dart';
import '../main.dart';
import 'call.dart';

const stickers = ['😀','😂','😍','🥰','😎','🤔','😭','😡','👍','👏','🙏','🎉','❤️','🔥','💯','👌'];

class ChatScreen extends StatefulWidget {
  final int conversationId; final String title; final Map? peer; final bool isGroup;
  const ChatScreen({super.key, required this.conversationId, required this.title, this.peer, this.isGroup = false});
  @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final List<Map> msgs = []; final input = TextEditingController(); final scroll = ScrollController();
  StreamSubscription? sub; int peerRead = 0; bool showStickers = false; bool sending = false;
  int get myId => Api.me?['id'] ?? 0;

  @override
  void initState() {
    super.initState();
    Poller.openConversation = widget.conversationId;
    load();
    sub = Poller.messages.stream.listen((list) {
      final mine = list.where((m) => m['conversation_id'] == widget.conversationId && !msgs.any((x) => x['id'] == m['id'])).toList();
      if (mine.isNotEmpty) { setState(() => msgs.addAll(mine.map((e) => Map.from(e)))); markRead(); toBottom(); }
      refreshRead();
    });
  }
  @override void dispose() { sub?.cancel(); Poller.openConversation = null; super.dispose(); }

  Future<void> load() async {
    try {
      final r = await Api.get('messages', {'conversation_id': widget.conversationId, 'limit': 80});
      setState(() { msgs..clear()..addAll((r['messages'] as List).map((e) => Map.from(e))); _setRead(r['read_by']); });
      markRead(); toBottom();
    } catch (e) { toast(context, e); }
  }
  Future<void> loadOlder() async {
    if (msgs.isEmpty) return;
    final r = await Api.get('messages', {'conversation_id': widget.conversationId, 'before_id': msgs.first['id'], 'limit': 50});
    setState(() => msgs.insertAll(0, (r['messages'] as List).map((e) => Map.from(e))));
  }
  Future<void> refreshRead() async {
    try { final r = await Api.get('messages', {'conversation_id': widget.conversationId, 'after_id': 1 << 40, 'limit': 1}); setState(() => _setRead(r['read_by'])); } catch (_) {}
  }
  void _setRead(List rb) { if (rb.isNotEmpty) peerRead = rb.map((e) => e['last_read_message_id'] as int).reduce((a, b) => a < b ? a : b); }
  void markRead() => Api.post('mark_read', {'conversation_id': widget.conversationId}).catchError((_) => <String, dynamic>{});
  void toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent); });

  Future<void> _send(Future<Map<String, dynamic>> f) async {
    setState(() => sending = true);
    try { final r = await f; final m = Map.from(r['message']);
      if (!msgs.any((x) => x['id'] == m['id'])) setState(() => msgs.add(m)); toBottom();
    } catch (e) { toast(context, e); } finally { if (mounted) setState(() => sending = false); }
  }
  void sendText() { final t = input.text.trim(); if (t.isEmpty) return; input.clear();
    _send(Api.post('send_message', {'conversation_id': widget.conversationId, 'type': 'text', 'content': t})); }
  void sendSticker(String s) => _send(Api.post('send_message', {'conversation_id': widget.conversationId, 'type': 'sticker', 'content': s}));
  Future<void> sendImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
    if (x != null) _send(Api.upload('send_message', 'image', x.path, {'conversation_id': '${widget.conversationId}'}));
  }

  Widget bubble(Map m) {
    if (m['type'] == 'system') return Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)), child: Text(m['content'] ?? '', style: const TextStyle(fontSize: 12))));
    final mine = m['sender_id'] == myId;
    Widget content;
    switch (m['type']) {
      case 'image': content = ClipRRect(borderRadius: BorderRadius.circular(12), child: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(),
            body: Center(child: InteractiveViewer(child: Image.network(m['content'])))))),
          child: Image.network(m['content'], width: 200, fit: BoxFit.cover))); break;
      case 'sticker': content = Text(m['content'] ?? '', style: const TextStyle(fontSize: 56)); break;
      case 'call': content = Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.call, size: 18), const SizedBox(width: 6), Text(m['content'] ?? '')])); break;
      default: content = Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .7),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: mine ? const Color(0xFF8DE055) : Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Text(m['content'] ?? '', style: const TextStyle(fontSize: 15)));
    }
    final meta = Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (mine && (m['id'] as int) <= peerRead) const Text('อ่านแล้ว', style: TextStyle(fontSize: 10, color: Colors.black54)),
      Text(hhmm(m['created_at']), style: const TextStyle(fontSize: 10, color: Colors.black54)),
    ]);
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.end,
      children: mine ? [meta, const SizedBox(width: 4), content] : [
        Avatar(m['sender_avatar'], m['sender_name'] ?? '', size: 32), const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.isGroup) Text(m['sender_name'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.black54)), content]),
        const SizedBox(width: 4), meta]));
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    return Scaffold(
      backgroundColor: const Color(0xFF8CABD8),
      appBar: AppBar(title: Text(widget.title), actions: [
        if (!widget.isGroup && peer != null) ...[
          IconButton(icon: const Icon(Icons.call), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
              CallScreen.outgoing(peerId: peer['id'], peerName: peer['display_name'], peerAvatar: peer['avatar_url'], video: false)))),
          IconButton(icon: const Icon(Icons.videocam), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
              CallScreen.outgoing(peerId: peer['id'], peerName: peer['display_name'], peerAvatar: peer['avatar_url'], video: true)))),
        ],
        if (widget.isGroup) IconButton(icon: const Icon(Icons.info_outline), onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => GroupInfoScreen(widget.conversationId)))),
      ]),
      body: Column(children: [
        Expanded(child: NotificationListener<ScrollNotification>(
          onNotification: (n) { if (n.metrics.pixels <= 0 && n is ScrollEndNotification) loadOlder(); return false; },
          child: ListView.builder(controller: scroll, itemCount: msgs.length, itemBuilder: (_, i) => bubble(msgs[i])))),
        if (showStickers) Container(color: Colors.white, height: 180, child: GridView.count(crossAxisCount: 8,
          children: [for (final s in stickers) InkWell(onTap: () => sendSticker(s), child: Center(child: Text(s, style: const TextStyle(fontSize: 30))))])),
        Container(color: Colors.white, child: SafeArea(top: false, child: Row(children: [
          IconButton(icon: const Icon(Icons.image_outlined), onPressed: sending ? null : sendImage),
          IconButton(icon: const Icon(Icons.emoji_emotions_outlined), onPressed: () => setState(() => showStickers = !showStickers)),
          Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => sendText(),
            decoration: const InputDecoration(hintText: 'Aa', border: InputBorder.none))),
          IconButton(icon: const Icon(Icons.send, color: kGreen), onPressed: sending ? null : sendText),
        ]))),
      ]),
    );
  }
}

class GroupInfoScreen extends StatefulWidget {
  final int id; const GroupInfoScreen(this.id, {super.key});
  @override State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}
class _GroupInfoScreenState extends State<GroupInfoScreen> {
  Map? conv;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { final r = await Api.get('conversation', {'conversation_id': widget.id}); setState(() => conv = r['conversation']); }
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ข้อมูลกลุ่ม')),
    body: conv == null ? const Center(child: CircularProgressIndicator()) : ListView(children: [
      ListTile(leading: const Icon(Icons.groups, color: kGreen, size: 40), title: Text(conv!['name'] ?? '', style: const TextStyle(fontSize: 20)),
        trailing: IconButton(icon: const Icon(Icons.edit), onPressed: rename)),
      ListTile(leading: const Icon(Icons.person_add), title: const Text('เพิ่มสมาชิก'), onTap: addMembers),
      const Divider(),
      for (final m in conv!['members']) ListTile(leading: Avatar(m['avatar_url'], m['display_name']), title: Text(m['display_name']),
        trailing: m['role'] == 'admin' ? const Text('แอดมิน', style: TextStyle(color: kGreen)) : null),
      const Divider(),
      ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('ออกจากกลุ่ม', style: TextStyle(color: Colors.red)), onTap: leave),
    ]),
  );
}
