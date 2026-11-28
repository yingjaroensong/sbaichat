import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';
import 'call.dart';

class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});
  @override State<BlockedScreen> createState() => _BlockedScreenState();
}
class _BlockedScreenState extends State<BlockedScreen> {
  List users = []; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { final r = await Api.get('blocked_list'); if (mounted) setState(() { users = r['users']; loading = false; }); }
    catch (e) { if (mounted) { setState(() => loading = false); toast(context, e); } }
  }
  Future<void> unblock(Map u) async {
    try { await Api.post('unblock_user', {'user_id': u['id']}); if (mounted) toast(context, 'เลิกบล็อก ${u['display_name']} แล้ว (เพิ่มเพื่อนใหม่ได้)'); load(); }
    catch (e) { if (mounted) toast(context, e); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('รายชื่อที่บล็อก')),
    body: loading ? const Center(child: CircularProgressIndicator())
      : users.isEmpty ? const Center(child: Text('ไม่มีรายชื่อที่บล็อก', style: TextStyle(color: Colors.grey)))
      : ListView(children: [
          for (final u in users) ListTile(leading: Avatar(u['avatar_url'], u['display_name']), title: Text(u['display_name']),
            subtitle: Text('@${u['username']}'), trailing: OutlinedButton(onPressed: () => unblock(u), child: const Text('เลิกบล็อก'))),
        ]),
  );
}

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});
  @override State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}
class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List calls = []; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { final r = await Api.get('call_history'); if (mounted) setState(() { calls = r['calls']; loading = false; }); }
    catch (e) { if (mounted) { setState(() => loading = false); toast(context, e); } }
  }
  String label(Map c) {
    final kind = c['call_type'] == 'video' ? 'วิดีโอคอล' : 'โทรเสียง';
    switch (c['status']) {
      case 'missed': return '$kind · ${c['outgoing'] == true ? 'ไม่มีผู้รับสาย' : 'สายที่ไม่ได้รับ'}';
      case 'rejected': return '$kind · ปฏิเสธสาย';
      case 'ended':
        final a = DateTime.tryParse('${c['started_at']}'.replaceFirst(' ', 'T'));
        final b = DateTime.tryParse('${c['ended_at']}'.replaceFirst(' ', 'T'));
        if (a != null && b != null) { final s = b.difference(a).inSeconds; return '$kind · ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}'; }
        return kind;
      default: return kind;
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ประวัติการโทร')),
    body: loading ? const Center(child: CircularProgressIndicator())
      : calls.isEmpty ? const Center(child: Text('ยังไม่มีประวัติการโทร', style: TextStyle(color: Colors.grey)))
      : RefreshIndicator(onRefresh: load, child: ListView.separated(itemCount: calls.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (_, i) {
            final c = calls[i]; final p = c['peer'] ?? {};
            final missed = c['status'] == 'missed' || c['status'] == 'rejected';
            final out = c['outgoing'] == true;
            return ListTile(
              leading: Avatar(p['avatar_url'], '${p['display_name'] ?? ''}'),
              title: Text('${p['display_name'] ?? ''}', style: TextStyle(color: missed && !out ? Colors.red : null)),
              subtitle: Row(children: [
                Icon(out ? Icons.call_made : (missed ? Icons.call_missed : Icons.call_received), size: 14, color: missed ? Colors.red : Colors.green),
                const SizedBox(width: 4),
                Flexible(child: Text('${label(c)} · ${fmtDateTime(c['started_at'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              ]),
              trailing: IconButton(icon: Icon(c['call_type'] == 'video' ? Icons.videocam : Icons.call, color: kPrimary),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen.outgoing(
                    peerId: p['id'], peerName: '${p['display_name'] ?? ''}', peerAvatar: p['avatar_url'], video: c['call_type'] == 'video')))),
            );
          })),
  );
}
