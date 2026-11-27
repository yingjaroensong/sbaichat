import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'widgets.dart';

/// Build number baked in by CI (--dart-define=BUILD_NUMBER=...).
const int kBuild = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);
const String kVersionName = 'v1.0.$kBuild';
const String kVersionUrl = 'https://sbaichat.com/download/version.json';

class Updater {
  static bool _busy = false;
  static DateTime? _last;

  /// Checks sbaichat.com/download/version.json and offers to install a newer APK.
  static Future<void> check(BuildContext context, {bool manual = false}) async {
    if (_busy) return;
    if (!manual && _last != null && DateTime.now().difference(_last!) < const Duration(hours: 1)) return;
    _busy = true;
    _last = DateTime.now();
    try {
      final r = await http.get(Uri.parse('$kVersionUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw 'ไม่พบข้อมูลเวอร์ชัน';
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final latest = (j['version_code'] as num).toInt();
      if (latest <= kBuild) {
        if (manual && context.mounted) toast(context, 'เป็นเวอร์ชันล่าสุดแล้ว ($kVersionName)');
        return;
      }
      final v = Platform.version;
      final url = (v.contains('android_arm') && !v.contains('android_arm64'))
          ? (j['apk_armv7'] ?? j['apk_arm64']).toString()
          : j['apk_arm64'].toString();
      if (!context.mounted) return;
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: Text('มีเวอร์ชันใหม่ ${j['version_name'] ?? ''}'),
        content: Text('เวอร์ชันปัจจุบัน: $kVersionName\n\n${(j['notes'] ?? '').toString()}'.trim()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ภายหลัง')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kPrimary),
              onPressed: () => Navigator.pop(c, true), child: const Text('อัปเดตเลย')),
        ]));
      if (ok == true && context.mounted) await _download(context, url, latest);
    } catch (e) {
      if (manual && context.mounted) toast(context, 'ตรวจสอบอัปเดตไม่สำเร็จ: $e');
    } finally {
      _busy = false;
    }
  }

  static Future<void> _download(BuildContext context, String url, int code) async {
    final progress = ValueNotifier<double?>(null);
    final client = http.Client();
    bool cancelled = false;
    showDialog(context: context, barrierDismissible: false, builder: (c) => AlertDialog(
      title: const Text('กำลังดาวน์โหลดอัปเดต'),
      content: ValueListenableBuilder<double?>(valueListenable: progress, builder: (_, p, __) => Column(
        mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: p, color: kPrimary),
          const SizedBox(height: 12),
          Text(p == null ? 'กำลังเชื่อมต่อ...' : '${(p * 100).toStringAsFixed(0)}%'),
        ])),
      actions: [TextButton(onPressed: () { cancelled = true; client.close(); Navigator.pop(c); }, child: const Text('ยกเลิก'))],
    ));
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sbaichat_$code.apk');
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw 'ดาวน์โหลดไม่สำเร็จ (${res.statusCode})';
      final total = res.contentLength ?? 0;
      final sink = file.openWrite();
      int got = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) progress.value = got / total;
      }
      await sink.close();
      if (cancelled) return;
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      final r = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done && context.mounted) {
        toast(context, 'เปิดตัวติดตั้งไม่ได้: ${r.message}\nให้อนุญาต "ติดตั้งแอปที่ไม่รู้จัก" สำหรับ SBAI Chat');
      }
    } catch (e) {
      if (!cancelled && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        toast(context, 'อัปเดตไม่สำเร็จ: $e');
      }
    } finally {
      client.close();
    }
  }
}
