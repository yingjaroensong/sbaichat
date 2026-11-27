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
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SBAI Chat 💬'), actions: [
      IconButton(icon: const Icon(Icons.group_add), tooltip: 'สร้างกลุ่ม',
        onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen())); load(); }),
    ]),
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load, child: convs.isEmpty
      ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('ยังไม่มีแชท เริ่มจากหน้าเพื่อน')))])
      : ListView.separated(itemCount: convs.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
        itemBuilder: (_, i) {
          final c = convs[i]; final lm = c['last_message'];
          final name = c['name'] ?? '';
          return ListTile(
            leading: c['type'] == 'group' && (c['avatar_url'] == null)
              ? const CircleAvatar(radius: 22, backgroundColor: Color(0x22E6197A), child: Icon(Icons.groups, color: kPrimary))
              : Avatar(c['avatar_url'], name),
            title: Text(c['type'] == 'group' ? '$name (${c['member_count']})' : name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(lm?['content'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(hhmm(c['updated_at']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if ((c['unread'] ?? 0) > 0) Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(10)),
                child: Text('${c['unread']}', style: const TextStyle(color: Colors.white, fontSize: 12))),
            ]),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: c['id'], title: name, peer: c['peer'], isGroup: c['type'] == 'group')));
              load();
            });
        })),
  );
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
