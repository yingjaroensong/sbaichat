import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';
import '../main.dart';
import '../updater.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final u = TextEditingController(), p = TextEditingController(), n = TextEditingController();
  bool register = false, busy = false;

  @override
  void initState() {
    super.initState();
    // check for a new version even before login
    Future.delayed(const Duration(seconds: 1), () { if (mounted) Updater.check(context); });
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      final r = register
          ? await Api.post('register', {'username': u.text.trim(), 'password': p.text, 'display_name': n.text.trim()})
          : await Api.post('login', {'username': u.text.trim(), 'password': p.text});
      await Api.save(r['token'], Map<String, dynamic>.from(r['user']));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } catch (e) { if (mounted) toast(context, e); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> forgot() async {
    final uc = TextEditingController(text: u.text.trim());
    final user = await showDialog<String>(context: context, builder: (d) => AlertDialog(
      title: const Text('ลืมรหัสผ่าน'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('ระบบจะส่งรหัสยืนยัน 6 หลักไปที่อีเมลกู้คืนที่ตั้งไว้ในหน้าโปรไฟล์', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        TextField(controller: uc, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('ยกเลิก')),
                FilledButton(onPressed: () => Navigator.pop(d, uc.text.trim()), child: const Text('ส่งรหัส'))]));
    if (user == null || user.isEmpty || !mounted) return;
    try { final r = await Api.post('forgot_$kPw', {'username': user}); if (mounted) toast(context, '${r['message']}'); }
    catch (e) { if (mounted) toast(context, e); return; }
    final cc = TextEditingController(), pc = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('ตั้งรหัสผ่านใหม่'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: cc, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'รหัสยืนยันจากอีเมล')),
        TextField(controller: pc, obscureText: true, decoration: const InputDecoration(labelText: 'รหัสผ่านใหม่ (6 ตัวขึ้นไป)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ยกเลิก')),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('ยืนยัน'))]));
    if (ok != true) return;
    try {
      await Api.post('reset_$kPw', {'username': user, 'code': cc.text.trim(), 'new_$kPw': pc.text});
      u.text = user; p.clear();
      if (mounted) toast(context, 'ตั้งรหัสผ่านใหม่แล้ว กรุณาเข้าสู่ระบบ');
    } catch (e) { if (mounted) toast(context, e); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: Column(children: [
      ClipRRect(borderRadius: BorderRadius.circular(32),
        child: Image.asset('assets/images/logo.png', width: 160, height: 160, fit: BoxFit.cover)),
      const SizedBox(height: 28),
      TextField(controller: u, decoration: const InputDecoration(labelText: 'Username (a-z, 0-9)', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      if (register) ...[
        TextField(controller: n, decoration: const InputDecoration(labelText: 'ชื่อที่แสดง', border: OutlineInputBorder())),
        const SizedBox(height: 12),
      ],
      TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'รหัสผ่าน (6 ตัวขึ้นไป)', border: OutlineInputBorder())),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, height: 50, child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: kPrimary),
        onPressed: busy ? null : submit,
        child: busy ? const CircularProgressIndicator(color: Colors.white) : Text(register ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ', style: const TextStyle(fontSize: 17)))),
      TextButton(onPressed: () => setState(() => register = !register),
        child: Text(register ? 'มีบัญชีแล้ว? เข้าสู่ระบบ' : 'ยังไม่มีบัญชี? สมัครสมาชิก')),
      if (!register) TextButton(onPressed: forgot, child: const Text('ลืมรหัสผ่าน?', style: TextStyle(color: Colors.grey))),
      const SizedBox(height: 16),
      TextButton.icon(onPressed: () => Updater.check(context, manual: true),
        icon: const Icon(Icons.system_update, size: 18),
        label: Text('ตรวจสอบอัปเดต ($kVersionName)', style: const TextStyle(color: Colors.grey))),
    ])))),
  );
}
