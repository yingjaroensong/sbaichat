import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../widgets.dart';
import '../main.dart';
import 'auth.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends State<ProfileScreen> {
  Map get me => Api.me ?? {};
  Future<void> _apply(Map<String, dynamic> r) async { await Api.save(Api.token!, Map<String, dynamic>.from(r['user'])); setState(() {}); }

  Future<void> pickAvatar() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (x == null) return;
    try { await _apply(await Api.upload('upload_avatar', 'avatar', x.path)); if (mounted) toast(context, 'เปลี่ยนรูปโปรไฟล์แล้ว'); } catch (e) { toast(context, e); }
  }
  Future<void> edit(String field, String label) async {
    final c = TextEditingController(text: me[field] ?? '');
    final v = await showDialog<String>(context: context, builder: (d) => AlertDialog(title: Text(label),
      content: TextField(controller: c, autofocus: true, maxLength: field == 'display_name' ? 100 : 255),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('ยกเลิก')),
                FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('บันทึก'))]));
    if (v == null) return;
    try { await _apply(await Api.post('update_profile', {field: v.trim()})); } catch (e) { toast(context, e); }
  }
  Future<void> logout() async {
    try { await Api.post('logout'); } catch (_) {}
    Poller.stop(); await Api.clear();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('โปรไฟล์')),
    body: ListView(children: [
      const SizedBox(height: 24),
      Center(child: Stack(children: [
        Avatar(me['avatar_url'], me['display_name'] ?? '', size: 120),
        Positioned(right: 0, bottom: 0, child: CircleAvatar(backgroundColor: kGreen,
          child: IconButton(icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20), onPressed: pickAvatar))),
      ])),
      const SizedBox(height: 16),
      ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('ชื่อที่แสดง'), subtitle: Text(me['display_name'] ?? ''),
        trailing: const Icon(Icons.edit), onTap: () => edit('display_name', 'เปลี่ยนชื่อโปรไฟล์')),
      ListTile(leading: const Icon(Icons.chat_outlined), title: const Text('ข้อความสถานะ'), subtitle: Text(me['status_msg'] ?? '-'),
        trailing: const Icon(Icons.edit), onTap: () => edit('status_msg', 'ข้อความสถานะ')),
      ListTile(leading: const Icon(Icons.alternate_email), title: const Text('ID (ให้เพื่อนค้นหา)'), subtitle: Text('@${me['username']}')),
      const Divider(),
      ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('ออกจากระบบ', style: TextStyle(color: Colors.red)), onTap: logout),
    ]),
  );
}
