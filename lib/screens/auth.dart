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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: Column(children: [
      const Icon(Icons.chat_rounded, size: 80, color: kPrimary),
      const Text('SBAI Chat', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: kPrimary)),
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
      const SizedBox(height: 16),
      TextButton.icon(onPressed: () => Updater.check(context, manual: true),
        icon: const Icon(Icons.system_update, size: 18),
        label: Text('ตรวจสอบอัปเดต ($kVersionName)', style: const TextStyle(color: Colors.grey))),
    ])))),
  );
}
