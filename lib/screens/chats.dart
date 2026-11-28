import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';
import '../main.dart';
import 'chat.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override State<ChatsScreen> createState() => _ChatsScreenState();
}
class _ChatsScreenState extends State<ChatsScreen> {
  List convs = []; bool loading = true;
  @override void initState() { super.initState(); load(); Poller.tick.addListener(load); }
  @override void dispose() { Poller.tick.removeListener(load); super.dispose(); }
  Future<void> load() async {
    try { final r = await Api.get('conversations'); if (mounted) setState(() { convs = r['conversations']; loading = false; }); }
    catch (_) { if (mounted) setState(() => loading = false); }
  }
  Future<void> deleteChat(Map c) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('ลบแชทนี้?'),
      content: Text('ประวัติแชท "${c['name'] ?? ''}" จะถูกลบจากเครื่องของคุณ (อีกฝ่ายยังเห็นอยู่)'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ยกเลิก')),
                FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(d, true), child: const Text('ลบแชท'))]));
    if (ok != true) return;
    try { await Api.post('delete_chat', {'conversation_id': c['id']}); setState(() => convs.removeWhere((x) => x['id'] == c['id'])); if (mounted) toast(context, 'ลบแชทแล้ว'); }
    catch (e) { if (mounted) toast(context, e); }
  }
  Future<void> setPref(Map c, String k, int v) async {
    try { await Api.post('set_chat_pref', {'conversation_id': c['id'], k: v}); await load(); }
    catch (e) { if (mounted) toast(context, e); }
  }
  void options(Map c) {
    final pinned = (c['pinned'] ?? 0) == 1, muted = (c['muted'] ?? 0) == 1;
    showModalBottomSheet(context: context, builder: (s) => SafeArea(child: Wrap(children: [
      ListTile(leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin), title: Text(pinned ? 'เลิกปักหมุด' : 'ปักหมุดแชท'),
        onTap: () { Navigator.pop(s); setPref(c, 'pinned', pinned ? 0 : 1); }),
      ListTile(leading: Icon(muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
        title: Text(muted ? 'เปิดเสียงแจ้งเตือน' : 'ปิดเสียงแจ้งเตือน'),
        onTap: () { Navigator.pop(s); setPref(c, 'muted', muted ? 0 : 1); }),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('ลบแชท', style: TextStyle(color: Colors.red)),
        onTap: () { Navigator.pop(s); deleteChat(c); }),
    ])));
  }
  Future<void> open(Map c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: c['id'], title: c['name'] ?? '', peer: c['peer'], isGroup: c['type'] == 'group')));
    load();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SBAI Chat 💬'), actions: [
      IconButton(icon: const Icon(Icons.search), tooltip: 'ค้นหา',
        onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatSearchScreen(convs: convs))); load(); }),
      IconButton(icon: const Icon(Icons.group_add), tooltip: 'สร้างกลุ่ม',
        onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen())); load(); }),
    ]),
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load, child: convs.isEmpty
      ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('ยังไม่มีแชท เริ่มจากหน้าเพื่อน')))])
      : ListView.separated(itemCount: convs.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
        itemBuilder: (_, i) {
          final c = convs[i]; final lm = c['last_message'];
          final name = c['name'] ?? '';
          final pinned = (c['pinned'] ?? 0) == 1, muted = (c['muted'] ?? 0) == 1;
          return ListTile(
            tileColor: pinned ? const Color(0xFFFFF5FA) : null,
            leading: c['type'] == 'group' && (c['avatar_url'] == null)
              ? const CircleAvatar(radius: 22, backgroundColor: Color(0x22E6197A), child: Icon(Icons.groups, color: kPrimary))
              : Avatar(c['avatar_url'], name),
            title: Row(children: [
              if (pinned) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.push_pin, size: 14, color: kPrimary)),
              Flexible(child: Text(c['type'] == 'group' ? '$name (${c['member_count']})' : name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (muted) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.notifications_off, size: 14, color: Colors.grey)),
            ]),
            subtitle: Text(lm?['content'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(hhmm(c['updated_at']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if ((c['unread'] ?? 0) > 0) Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: muted ? Colors.grey : kPrimary, borderRadius: BorderRadius.circular(10)),
                child: Text('${c['unread']}', style: const TextStyle(color: Colors.white, fontSize: 12))),
            ]),
            onLongPress: () => options(c),
            onTap: () => open(c));
        })),
  );
}

class ChatSearchScreen extends StatefulWidget {
  final List convs;
  const ChatSearchScreen({super.key, required this.convs});
  @override State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}
class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final q = TextEditingController(); List results = []; bool busy = false; Timer? deb;
  String get term => q.text.trim().toLowerCase();
  @override void dispose() { deb?.cancel(); super.dispose(); }
  void onChanged(String _) { setState(() {}); deb?.cancel(); deb = Timer(const Duration(milliseconds: 500), search); }
  Future<void> search() async {
    if (term.length < 2) { setState(() => results = []); return; }
    setState(() => busy = true);
    try { final r = await Api.get('search_messages', {'q': q.text.trim()}); if (mounted) setState(() => results = r['results']); }
    catch (e) { if (mounted) toast(context, e); } finally { if (mounted) setState(() => busy = false); }
  }
  void open(int id, String title, Map? peer, bool group) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: id, title: title, peer: peer, isGroup: group)));
  Widget header(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(t, style: const TextStyle(color: Colors.grey)));
  @override
  Widget build(BuildContext context) {
    final rooms = term.isEmpty ? [] : widget.convs.where((c) => '${c['name'] ?? ''}'.toLowerCase().contains(term)).toList();
    return Scaffold(
      appBar: AppBar(title: TextField(controller: q, autofocus: true, onChanged: onChanged, onSubmitted: (_) => search(),
        decoration: const InputDecoration(hintText: 'ค้นหาแชทหรือข้อความ', border: InputBorder.none))),
      body: ListView(children: [
        if (busy) const LinearProgressIndicator(color: kPrimary),
        if (term.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('พิมพ์ชื่อแชท หรือข้อความที่ต้องการค้นหา', style: TextStyle(color: Colors.grey)))),
        if (rooms.isNotEmpty) header('แชท (${rooms.length})'),
        for (final c in rooms) ListTile(leading: Avatar(c['avatar_url'], '${c['name'] ?? ''}'), title: Text('${c['name'] ?? ''}'),
          onTap: () => open(c['id'], '${c['name'] ?? ''}', c['peer'], c['type'] == 'group')),
        if (term.length >= 2) header('ข้อความ (${results.length})'),
        for (final r in results) ListTile(
          leading: const Icon(Icons.chat_bubble_outline, color: kPrimary),
          title: Text('${r['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${r['sender_name'] ?? ''}: ${r['content'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text(fmtDateTime(r['created_at']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          onTap: () => open(r['conversation_id'], '${r['title'] ?? ''}', r['peer'], r['conv_type'] == 'group')),
      ]),
    );
  }
}

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}
class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final name = TextEditingController(); List friends = []; final Set<int> sel = {};
  @override void initState() { super.initState(); Api.get('friends').then((r) => setState(() => friends = r['friends'])); }
  Future<void> create() async {
    if (name.text.trim().isEmpty) { toast(context, 'กรุณาตั้งชื่อกลุ่ม'); return; }
    try {
      final r = await Api.post('create_group', {'name': name.text.trim(), 'member_ids': sel.toList()});
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: r['conversation_id'], title: name.text.trim(), isGroup: true)));
    } catch (e) { toast(context, e); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('สร้างกลุ่ม'), actions: [TextButton(onPressed: create, child: Text('สร้าง (${sel.length})'))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(controller: name, decoration: const InputDecoration(labelText: 'ชื่อกลุ่ม', border: OutlineInputBorder()))),
      Expanded(child: ListView(children: [
        for (final f in friends) CheckboxListTile(value: sel.contains(f['id']),
          onChanged: (v) => setState(() => v! ? sel.add(f['id']) : sel.remove(f['id'])),
          secondary: Avatar(f['avatar_url'], f['display_name']), title: Text(f['display_name'])),
      ])),
    ]),
  );
}
