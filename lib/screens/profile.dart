import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../widgets.dart';
import '../main.dart';
import 'auth.dart';
import '../background.dart';
import '../updater.dart';
import 'more.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends State<ProfileScreen> {
  Map get me => Api.me ?? {};
  String? email;
  @override
  void initState() {
    super.initState();
    Api.get('me').then((r) { if (mounted) setState(() => email = r['user']['email'] as String?); }).catchError((_) {});
  }
  Future<void> setEmail() async {
    final c = TextEditingController(text: email ?? '');
    final v = await showDialog<String>(context: context, builder: (d) => AlertDialog(title: const Text('อีเมลกู้คืนรหัสผ่าน'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('ใช้รับรหัสยืนยันเมื่อลืมรหัสผ่าน', style: TextStyle(fontSize: 13, color: Colors.grey)),
        TextField(controller: c, keyboardType: TextInputType.emailAddress, autofocus: true, decoration: const InputDecoration(hintText: 'name@example.com')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('ยกเลิก')),
                FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('บันทึก'))]));
    if (v == null) return;
    try { final r = await Api.post('set_email', {'email': v}); if (mounted) { setState(() => email = r['email'] as String?); toast(context, 'บันทึกอีเมลแล้ว'); } }
    catch (e) { if (mounted) toast(context, e); }
  }
  Future<void> changePw() async {
    final o = TextEditingController(), n = TextEditingController(), c = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('เปลี่ยนรหัสผ่าน'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: o, obscureText: true, decoration: const InputDecoration(labelText: 'รหัสผ่านเดิม')),
        TextField(controller: n, obscureText: true, decoration: const InputDecoration(labelText: 'รหัสผ่านใหม่ (6 ตัวขึ้นไป)')),
        TextField(controller: c, obscureText: true, decoration: const InputDecoration(labelText: 'ยืนยันรหัสผ่านใหม่')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ยกเลิก')),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('เปลี่ยน'))]));
    if (ok != true) return;
    if (n.text.length < 6) { if (mounted) toast(context, 'รหัสผ่านใหม่ต้องยาวอย่างน้อย 6 ตัว'); return; }
    if (n.text != c.text) { if (mounted) toast(context, 'รหัสผ่านใหม่ไม่ตรงกัน'); return; }
    try { await Api.post('change_$kPw', {'old_$kPw': o.text, 'new_$kPw': n.text}); if (mounted) toast(context, 'เปลี่ยนรหัสผ่านแล้ว'); }
    catch (e) { if (mounted) toast(context, e); }
  }
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
    Poller.stop(); Poller.lastId = 0; stopBackgroundService(); await Api.clear();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('โปรไฟล์')),
    body: ListView(children: [
      const SizedBox(height: 24),
      Center(child: Stack(children: [
        Avatar(me['avatar_url'], me['display_name'] ?? '', size: 120),
        Positioned(right: 0, bottom: 0, child: CircleAvatar(backgroundColor: kPrimary,
          child: IconButton(icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20), onPressed: pickAvatar))),
      ])),
      const SizedBox(height: 16),
      ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('ชื่อที่แสดง'), subtitle: Text(me['display_name'] ?? ''),
        trailing: const Icon(Icons.edit), onTap: () => edit('display_name', 'เปลี่ยนชื่อโปรไฟล์')),
      ListTile(leading: const Icon(Icons.chat_outlined), title: const Text('ข้อความสถานะ'), subtitle: Text(me['status_msg'] ?? '-'),
        trailing: const Icon(Icons.edit), onTap: () => edit('status_msg', 'ข้อความสถานะ')),
      ListTile(leading: const Icon(Icons.alternate_email), title: const Text('ID (ให้เพื่อนค้นหา)'), subtitle: Text('@${me['username']}')),
      ListTile(leading: const Icon(Icons.email_outlined), title: const Text('อีเมลกู้คืนรหัสผ่าน'),
        subtitle: Text(email ?? 'ยังไม่ได้ตั้ง (ใช้ตอนลืมรหัสผ่าน)'), trailing: const Icon(Icons.edit), onTap: setEmail),
      const Divider(),
      ListTile(leading: const Icon(Icons.lock_outline), title: const Text('เปลี่ยนรหัสผ่าน'), onTap: changePw),
      ListTile(leading: const Icon(Icons.history), title: const Text('ประวัติการโทร'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallHistoryScreen()))),
      ListTile(leading: const Icon(Icons.block), title: const Text('รายชื่อที่บล็อก'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedScreen()))),
      const Divider(),
      ListTile(leading: const Icon(Icons.system_update), title: const Text('ตรวจสอบอัปเดต'),
        subtitle: const Text('เวอร์ชัน $kVersionName'), onTap: () => Updater.check(context, manual: true)),
      ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('ออกจากระบบ', style: TextStyle(color: Colors.red)), onTap: logout),
    ]),
  );
}
