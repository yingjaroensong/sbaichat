import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';
import '../main.dart';
import 'chat.dart';
import 'call.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override State<FriendsScreen> createState() => _FriendsScreenState();
}
class _FriendsScreenState extends State<FriendsScreen> {
  List friends = [], incoming = [];
  bool loading = true;
  @override void initState() { super.initState(); load(); Poller.friendRequests.addListener(load); }
  @override void dispose() { Poller.friendRequests.removeListener(load); super.dispose(); }

  Future<void> load() async {
    try {
      final a = await Api.get('friends'); final b = await Api.get('friend_requests');
      if (mounted) setState(() { friends = a['friends']; incoming = b['incoming']; loading = false; });
    } catch (e) { if (mounted) setState(() => loading = false); }
  }
  Future<void> respond(int id, bool ok) async {
    try { await Api.post('friend_respond', {'request_id': id, 'accept': ok ? 1 : 0}); load(); } catch (e) { toast(context, e); }
  }
  void openFriend(Map f) => showModalBottomSheet(context: context, builder: (_) => FriendSheet(f, onChanged: load));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('เพื่อน (${friends.length})'), actions: [
      IconButton(icon: const Icon(Icons.person_add_alt_1), tooltip: 'เพิ่มเพื่อน',
        onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddFriendScreen())); load(); }),
    ]),
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load, child: ListView(children: [
      ListTile(leading: Avatar(Api.me?['avatar_url'], Api.me?['display_name'] ?? '', size: 56),
        title: Text(Api.me?['display_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        subtitle: Text(Api.me?['status_msg'] ?? '@${Api.me?['username']}')),
      if (incoming.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('คำขอเป็นเพื่อน', style: TextStyle(color: Colors.grey))),
        for (final r in incoming) ListTile(
          leading: Avatar(r['user']['avatar_url'], r['user']['display_name']),
          title: Text(r['user']['display_name']), subtitle: Text('@${r['user']['username']}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.check_circle, color: kPrimary), onPressed: () => respond(r['request_id'], true)),
            IconButton(icon: const Icon(Icons.cancel, color: Colors.grey), onPressed: () => respond(r['request_id'], false)),
          ])),
      ],
      const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('เพื่อน', style: TextStyle(color: Colors.grey))),
      if (friends.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('ยังไม่มีเพื่อน กดปุ่ม + ด้านบนเพื่อเพิ่มเพื่อน'))),
      for (final f in friends) ListTile(
        leading: Avatar(f['avatar_url'], f['display_name']),
        title: Text(f['display_name']), subtitle: f['status_msg'] != null ? Text(f['status_msg']) : null,
        onTap: () => openFriend(f)),
    ])),
  );
}

class FriendSheet extends StatelessWidget {
  final Map f; final VoidCallback? onChanged;
  const FriendSheet(this.f, {super.key, this.onChanged});
  @override
  Widget build(BuildContext context) {
    Future<void> chat() async {
      try {
        final r = await Api.post('open_direct', {'user_id': f['id']});
        if (!context.mounted) return;
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: r['conversation_id'], title: f['display_name'], peer: f)));
      } catch (e) { toast(context, e); }
    }
    Future<void> act(String action, String question, String done) async {
      final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text(question),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ยกเลิก')),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(d, true), child: const Text('ยืนยัน'))]));
      if (ok != true || !context.mounted) return;
      try {
        await Api.post(action, {'user_id': f['id']});
        if (!context.mounted) return;
        toast(context, done);
        Navigator.pop(context);
        onChanged?.call();
      } catch (e) { if (context.mounted) toast(context, e); }
    }
    void call(bool video) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen.outgoing(peerId: f['id'], peerName: f['display_name'], peerAvatar: f['avatar_url'], video: video)));
    }
    return Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Avatar(f['avatar_url'], f['display_name'], size: 96),
      const SizedBox(height: 12),
      Text(f['display_name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      if (f['status_msg'] != null) Text(f['status_msg'], style: const TextStyle(color: Colors.grey)),
      if (fmtLastSeen(f['last_seen']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
        child: Text(fmtLastSeen(f['last_seen']), style: const TextStyle(color: kPrimary, fontSize: 12))),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _btn(Icons.chat_bubble, 'แชท', chat),
        _btn(Icons.call, 'โทร', () => call(false)),
        _btn(Icons.videocam, 'วิดีโอคอล', () => call(true)),
      ]),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton.icon(icon: const Icon(Icons.person_remove_outlined, color: Colors.grey), label: const Text('ลบเพื่อน', style: TextStyle(color: Colors.grey)),
          onPressed: () => act('friend_remove', 'ลบ ${f['display_name']} ออกจากเพื่อน?', 'ลบเพื่อนแล้ว')),
        TextButton.icon(icon: const Icon(Icons.block, color: Colors.red), label: const Text('บล็อก', style: TextStyle(color: Colors.red)),
          onPressed: () => act('block_user', 'บล็อก ${f['display_name']}? (จะแชทและโทรหาคุณไม่ได้)', 'บล็อกแล้ว')),
      ]),
    ]));
  }
  Widget _btn(IconData i, String t, VoidCallback onTap) => InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(8),
      child: Column(children: [Icon(i, color: kPrimary, size: 32), const SizedBox(height: 4), Text(t)])));
}

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});
  @override State<AddFriendScreen> createState() => _AddFriendScreenState();
}
class _AddFriendScreenState extends State<AddFriendScreen> {
  final q = TextEditingController(); List results = []; bool busy = false;
  Future<void> search() async {
    setState(() => busy = true);
    try { final r = await Api.get('search_users', {'q': q.text.trim()}); setState(() => results = r['users']); }
    catch (e) { toast(context, e); } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> add(Map u) async {
    try { final r = await Api.post('friend_request', {'user_id': u['id']});
      toast(context, r['status'] == 'accepted' ? 'เป็นเพื่อนกันแล้ว' : 'ส่งคำขอแล้ว'); search(); } catch (e) { toast(context, e); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('เพิ่มเพื่อน')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(controller: q, onSubmitted: (_) => search(),
        decoration: InputDecoration(hintText: 'ค้นหาด้วย username หรือชื่อ', border: const OutlineInputBorder(),
          suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: search)))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('ID ของคุณ: @${Api.me?['username']}', style: const TextStyle(color: Colors.grey))),
      if (busy) const LinearProgressIndicator(),
      Expanded(child: ListView(children: [
        for (final u in results) ListTile(
          leading: Avatar(u['avatar_url'], u['display_name']),
          title: Text(u['display_name']), subtitle: Text('@${u['username']}'),
          trailing: switch (u['friend_status']) {
            'accepted' => const Text('เพื่อน', style: TextStyle(color: kPrimary)),
            'pending' => u['request_from_me'] == true ? const Text('รอตอบรับ') :
                FilledButton(onPressed: () => add(u), child: const Text('ยอมรับ')),
            'blocked' => const Text('บล็อกแล้ว', style: TextStyle(color: Colors.grey)),
            'unavailable' => const Text('เพิ่มไม่ได้', style: TextStyle(color: Colors.grey)),
            _ => FilledButton(style: FilledButton.styleFrom(backgroundColor: kPrimary), onPressed: () => add(u), child: const Text('เพิ่ม')),
          }),
      ])),
    ]),
  );
}
