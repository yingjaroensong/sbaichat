import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'widgets.dart';
import 'background.dart';
import 'updater.dart';
import 'screens/auth.dart';
import 'screens/friends.dart';
import 'screens/chats.dart';
import 'screens/chat.dart';
import 'screens/profile.dart';
import 'screens/call.dart';

final navKey = GlobalKey<NavigatorState>();
String? pendingPayload;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  await initNotifications(onTap: openFromPayload);
  final d = await notif.getNotificationAppLaunchDetails();
  if (d?.didNotificationLaunchApp == true) pendingPayload = d!.notificationResponse?.payload;
  runApp(const SbaiApp());
}

/// Opens the chat / incoming call that a notification points to.
void openFromPayload(String? p) {
  if (p == null || Api.token == null) return;
  Map j;
  try { j = jsonDecode(p); } catch (_) { return; }
  final nav = navKey.currentState;
  if (nav == null) { pendingPayload = p; return; }
  if (j['call'] != null) {
    if (CallScreen.active) return;
    nav.push(MaterialPageRoute(builder: (_) => CallScreen.incoming(
        callId: j['call'], peerName: (j['name'] ?? '').toString(), peerAvatar: j['avatar'], video: j['video'] == true)));
  } else if (j['c'] != null) {
    if (Poller.openConversation == j['c']) return;
    final g = j['g'] == true;
    nav.push(MaterialPageRoute(builder: (_) => ChatScreen(conversationId: j['c'], title: (j['t'] ?? '').toString(), isGroup: g,
        peer: g ? null : {'id': j['pid'], 'display_name': j['t'], 'avatar_url': j['avatar']})));
  }
}

class SbaiApp extends StatelessWidget {
  const SbaiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navKey,
        title: 'SBAI Chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: kPrimary, useMaterial3: true,
            appBarTheme: const AppBarTheme(backgroundColor: Colors.white, surfaceTintColor: Colors.white)),
        home: Api.token == null ? const LoginScreen() : const HomeScreen(),
      );
}

/// Foreground poller: new messages, incoming calls, friend requests.
class Poller {
  static Timer? _t;
  static int lastId = 0;
  static int? openConversation;
  static final messages = StreamController<List<dynamic>>.broadcast();
  static final ValueNotifier<int> friendRequests = ValueNotifier(0);
  static final ValueNotifier<int> tick = ValueNotifier(0);
  static final Set<int> _shownCalls = {};
  static bool _busy = false;

  static void start() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 3), (_) => _run());
    _run();
  }
  static void stop() { _t?.cancel(); _t = null; }

  static Future<void> _run() async {
    if (_busy || Api.token == null) return;
    _busy = true;
    try {
      final r = await Api.get('poll', {'since_id': lastId});
      (await SharedPreferences.getInstance()).setInt('fg_ts', DateTime.now().millisecondsSinceEpoch);
      final msgs = r['messages'] as List;
      lastId = r['last_id'] as int;
      friendRequests.value = r['friend_requests'] as int;
      if (msgs.isNotEmpty) {
        messages.add(msgs);
        tick.value++;
        final myId = Api.me?['id'];
        for (final m in msgs) {
          if (m['sender_id'] != myId && m['conversation_id'] != openConversation && m['type'] != 'system' && m['type'] != 'deleted' && m['type'] != 'edited' && m['muted'] != 1) {
            final ctx = navKey.currentContext;
            if (ctx != null) {
              final txt = switch (m['type']) { 'image' => 'ส่งรูปภาพ', 'sticker' => 'ส่งสติกเกอร์', 'file' => 'ส่งไฟล์ ${m['file_name'] ?? ''}', 'voice' => 'ส่งข้อความเสียง', _ => m['content'] };
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${m['sender_name']}: $txt'), duration: const Duration(seconds: 2)));
            }
          }
        }
      }
      for (final c in (r['incoming_calls'] as List)) {
        final id = c['id'] as int;
        if (_shownCalls.add(id) && !CallScreen.active) {
          notif.cancel(100000 + id);
          navKey.currentState?.push(MaterialPageRoute(builder: (_) => CallScreen.incoming(
              callId: id, peerName: c['caller_name'], peerAvatar: c['caller_avatar'], video: c['call_type'] == 'video')));
        }
      }
    } on ApiError catch (e) {
      if (e.message == 'unauthorized') {
        stop(); lastId = 0; stopBackgroundService(); await Api.clear();
        navKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      }
    } catch (_) {} finally { _busy = false; }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int idx = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Poller.start();
    _setup();
  }
  Future<void> _setup() async {
    try { await requestNotificationPermission(); } catch (_) {}
    try { await initBackgroundService(); } catch (_) {}
    Future.delayed(const Duration(seconds: 2), () { if (mounted) Updater.check(context); });
    if (pendingPayload != null) {
      final x = pendingPayload; pendingPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => openFromPayload(x));
    }
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('battery_tip') ?? false) && mounted) {
      await p.setBool('battery_tip', true);
      if (!mounted) return;
      showDialog(context: context, builder: (c) => AlertDialog(
        title: const Text('เปิดให้แจ้งเตือนทำงานตลอด'),
        content: const Text('เพื่อให้แจ้งเตือนเด้งแม้ปิดแอป:\n\n'
            '1. ไปที่ ตั้งค่า > แอป > SBAI Chat > แบตเตอรี่\n'
            '2. เลือก "ไม่จำกัด" (Unrestricted)\n'
            '3. Xiaomi/Oppo/Vivo: เปิด "เริ่มอัตโนมัติ" (Autostart) ด้วย\n\n'
            'แอปจะแสดงแจ้งเตือน "กำลังรอข้อความใหม่" ค้างไว้ เป็นเรื่องปกติ'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('เข้าใจแล้ว'))]));
    }
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) async {
    if (s == AppLifecycleState.resumed) {
      Poller.start();
      if (mounted) Updater.check(context);
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.detached) {
      Poller.stop();
      (await SharedPreferences.getInstance()).setInt('fg_ts', 0);
    }
  }
  @override
  Widget build(BuildContext context) {
    final pages = [const FriendsScreen(), const ChatsScreen(), const ProfileScreen()];
    return Scaffold(
      body: pages[idx],
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: Poller.friendRequests,
        builder: (_, n, __) => NavigationBar(
          selectedIndex: idx, onDestinationSelected: (i) => setState(() => idx = i),
          destinations: [
            NavigationDestination(icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.people_outline)), label: 'เพื่อน'),
            const NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'แชท'),
            const NavigationDestination(icon: Icon(Icons.person_outline), label: 'โปรไฟล์'),
          ],
        ),
      ),
    );
  }
}
