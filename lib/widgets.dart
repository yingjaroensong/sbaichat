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
