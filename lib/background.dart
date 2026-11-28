import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart' show kBase;

final FlutterLocalNotificationsPlugin notif = FlutterLocalNotificationsPlugin();

const chService = AndroidNotificationChannel('sbai_service', 'SBAI Chat ทำงานเบื้องหลัง',
    description: 'ใช้รอรับข้อความใหม่', importance: Importance.low, showBadge: false);
const chMsg = AndroidNotificationChannel('sbai_msg', 'ข้อความใหม่', importance: Importance.high);
const chCall = AndroidNotificationChannel('sbai_call', 'สายเรียกเข้า', importance: Importance.max);

const msgDetails = NotificationDetails(android: AndroidNotificationDetails('sbai_msg', 'ข้อความใหม่',
    importance: Importance.high, priority: Priority.high, category: AndroidNotificationCategory.message));
const callDetails = NotificationDetails(android: AndroidNotificationDetails('sbai_call', 'สายเรียกเข้า',
    importance: Importance.max, priority: Priority.max, category: AndroidNotificationCategory.call,
    fullScreenIntent: true, ongoing: true, autoCancel: true, timeoutAfter: 45000));

Future<void> initNotifications({void Function(String?)? onTap}) async {
  await notif.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload));
  final a = notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  for (final c in [chService, chMsg, chCall]) {
    await a?.createNotificationChannel(c);
  }
}

Future<void> requestNotificationPermission() async {
  final a = notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await a?.requestNotificationsPermission();
}

Future<void> initBackgroundService() async {
  final s = FlutterBackgroundService();
  await s.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, autoStart: true, autoStartOnBoot: true, isForegroundMode: true,
      notificationChannelId: 'sbai_service', initialNotificationTitle: 'SBAI Chat',
      initialNotificationContent: 'กำลังรอข้อความใหม่', foregroundServiceNotificationId: 888),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart),
  );
  if (!await s.isRunning()) await s.startService();
}

void stopBackgroundService() => FlutterBackgroundService().invoke('stop');

String _preview(Map m) {
  switch (m['type']) {
    case 'image': return 'ส่งรูปภาพ';
    case 'sticker': return 'ส่งสติกเกอร์ ${m['content'] ?? ''}';
    case 'file': return 'ส่งไฟล์ ${m['file_name'] ?? ''}';
    case 'voice': return 'ส่งข้อความเสียง';
    default: return (m['content'] ?? '').toString();
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await initNotifications();
  service.on('stop').listen((_) => service.stopSelf());
  bool busy = false;
  final shownCalls = <int>{};
  Timer.periodic(const Duration(seconds: 10), (_) async {
    if (busy) return;
    busy = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final token = p.getString('token');
      if (token == null) return;
      final myId = jsonDecode(p.getString('me') ?? '{}')['id'];
      final since = p.getInt('bg_last_id') ?? 0;
      final r = await http.get(Uri.parse('$kBase?action=poll&bg=1&since_id=$since'),
          headers: {'X-Auth-Token': token}).timeout(const Duration(seconds: 15));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j['ok'] != true) return;
      await p.setInt('bg_last_id', j['last_id'] as int);
      final fr = (j['friend_requests'] ?? 0) as int;
      final prevFr = p.getInt('bg_fr') ?? 0;
      await p.setInt('bg_fr', fr);
      // app is open on screen -> it shows its own alerts
      final fgTs = p.getInt('fg_ts') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - fgTs < 8000) return;
      if (since == 0) return;
      for (final m in (j['messages'] as List)) {
        if (m['sender_id'] == myId || m['type'] == 'system' || m['type'] == 'deleted' || m['type'] == 'edited' || m['muted'] == 1) continue;
        final isGroup = m['conv_type'] == 'group';
        final sender = (m['sender_name'] ?? '').toString();
        final title = isGroup ? (m['conv_name'] ?? 'กลุ่ม').toString() : sender;
        final body = isGroup ? '$sender: ${_preview(m)}' : _preview(m);
        await notif.show(m['conversation_id'] as int, title, body, msgDetails,
            payload: jsonEncode({'c': m['conversation_id'], 't': title, 'g': isGroup, 'pid': m['sender_id'], 'avatar': m['sender_avatar']}));
      }
      for (final c in (j['incoming_calls'] as List)) {
        final id = c['id'] as int;
        if (!shownCalls.add(id)) continue;
        final video = c['call_type'] == 'video';
        await notif.show(100000 + id, (c['caller_name'] ?? '').toString(), video ? 'วิดีโอคอลเข้า' : 'สายเรียกเข้า', callDetails,
            payload: jsonEncode({'call': id, 'name': c['caller_name'], 'avatar': c['caller_avatar'], 'video': video}));
      }
      if (fr > prevFr) {
        await notif.show(999, 'คำขอเป็นเพื่อนใหม่', 'มีคำขอเป็นเพื่อนรอคุณตอบรับ ($fr)', msgDetails, payload: jsonEncode({'friend': true}));
      }
    } catch (_) {
    } finally {
      busy = false;
    }
  });
}
