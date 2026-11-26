import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'widgets.dart';
import 'screens/auth.dart';
import 'screens/friends.dart';
import 'screens/chats.dart';
import 'screens/profile.dart';
import 'screens/call.dart';

final navKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  runApp(const SbaiApp());
}

class SbaiApp extends StatelessWidget {
  const SbaiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navKey,
        title: 'SBAI Chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: kGreen, useMaterial3: true,
            appBarTheme: const AppBarTheme(backgroundColor: Colors.white, surfaceTintColor: Colors.white)),
        home: Api.token == null ? const LoginScreen() : const HomeScreen(),
      );
}

/// Global poller: new messages, incoming calls, friend requests.
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
  static void stop() { _t?.cancel(); _t = null; lastId = 0; }

  static Future<void> _run() async {
    if (_busy || Api.token == null) return;
    _busy = true;
    try {
      final r = await Api.get('poll', {'since_id': lastId});
      final msgs = r['messages'] as List;
      lastId = r['last_id'] as int;
      friendRequests.value = r['friend_requests'] as int;
      if (msgs.isNotEmpty) {
        messages.add(msgs);
        tick.value++;
        final myId = Api.me?['id'];
        for (final m in msgs) {
          if (m['sender_id'] != myId && m['conversation_id'] != openConversation && m['type'] != 'system') {
            final ctx = navKey.currentContext;
            if (ctx != null) {
              final txt = m['type'] == 'image' ? 'ส่งรูปภาพ' : m['type'] == 'sticker' ? 'ส่งสติกเกอร์' : m['content'];
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${m['sender_name']}: $txt'), duration: const Duration(seconds: 2)));
            }
          }
        }
      }
      for (final c in (r['incoming_calls'] as List)) {
        final id = c['id'] as int;
        if (_shownCalls.add(id) && !CallScreen.active) {
          navKey.currentState?.push(MaterialPageRoute(builder: (_) => CallScreen.incoming(
              callId: id, peerName: c['caller_name'], peerAvatar: c['caller_avatar'], video: c['call_type'] == 'video')));
        }
      }
    } on ApiError catch (e) {
      if (e.message == 'unauthorized') { stop(); await Api.clear();
        navKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false); }
    } catch (_) {} finally { _busy = false; }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int idx = 0;
  @override void initState() { super.initState(); Poller.start(); }
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
