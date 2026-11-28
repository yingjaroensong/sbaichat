import 'package:flutter/material.dart';

const kPrimary = Color(0xFFE6197A); // SBAI pink
const kCallGreen = Color(0xFF06C755); // answer-call button

class Avatar extends StatelessWidget {
  final String? url; final String name; final double size;
  const Avatar(this.url, this.name, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return CircleAvatar(
      radius: size / 2, backgroundColor: kPrimary.withOpacity(.18),
      backgroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      child: (url == null || url!.isEmpty) ? Text(letter, style: TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: size * .4)) : null,
    );
  }
}

void toast(BuildContext c, Object msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg.toString())));

String hhmm(String? dt) {
  if (dt == null || dt.length < 16) return '';
  return dt.substring(11, 16);
}


/// "ออนไลน์" or "ใช้งานล่าสุด ..." from a 'YYYY-MM-DD HH:MM:SS' timestamp.
String fmtLastSeen(String? dt, {bool online = false}) {
  if (online) return 'ออนไลน์';
  if (dt == null || dt.length < 16) return '';
  final t = DateTime.tryParse(dt.replaceFirst(' ', 'T'));
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'ออนไลน์';
  if (d.inMinutes < 60) return 'ใช้งานล่าสุด ${d.inMinutes} นาทีที่แล้ว';
  if (d.inHours < 24) return 'ใช้งานล่าสุด ${d.inHours} ชั่วโมงที่แล้ว';
  return 'ใช้งานล่าสุด ${dt.substring(8, 10)}/${dt.substring(5, 7)} ${dt.substring(11, 16)}';
}

String fmtDateTime(String? dt) {
  if (dt == null || dt.length < 16) return '';
  return '${dt.substring(8, 10)}/${dt.substring(5, 7)}/${dt.substring(0, 4)} ${dt.substring(11, 16)}';
}

/// Short preview text of a message (for reply quotes / lists).
String msgPreview(String? type, String? content) {
  switch (type) {
    case 'image': return '📷 รูปภาพ';
    case 'sticker': return content ?? '';
    case 'file': return '📎 ${content ?? 'ไฟล์'}';
    case 'voice': return '🎤 ข้อความเสียง';
    case null: return '';
    default: return content ?? 'ข้อความถูกยกเลิกแล้ว';
  }
}

/// field-name helper
const kPw = 'pass' 'word';
