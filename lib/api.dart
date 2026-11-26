import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kBase = 'https://sbaichat.com/api/index.php';

class ApiError implements Exception {
  final String message; ApiError(this.message);
  @override String toString() => message;
}

class Api {
  static String? token;
  static Map<String, dynamic>? me;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    final m = p.getString('me');
    if (m != null) me = jsonDecode(m);
  }
  static Future<void> save(String t, Map<String, dynamic> u) async {
    token = t; me = u;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', t); await p.setString('me', jsonEncode(u));
  }
  static Future<void> clear() async {
    token = null; me = null;
    final p = await SharedPreferences.getInstance(); await p.clear();
  }
  static Map<String, String> get _h => {if (token != null) 'X-Auth-Token': token!};

  static Map<String, dynamic> _parse(http.Response r) {
    Map<String, dynamic> j;
    try { j = jsonDecode(utf8.decode(r.bodyBytes)); } catch (_) { throw ApiError('เซิร์ฟเวอร์ตอบกลับผิดพลาด (${r.statusCode})'); }
    if (j['ok'] != true) throw ApiError(j['error']?.toString() ?? 'error');
    return j;
  }
  static Future<Map<String, dynamic>> get(String action, [Map<String, dynamic>? q]) async {
    final uri = Uri.parse(kBase).replace(queryParameters: {'action': action, ...?q?.map((k, v) => MapEntry(k, '$v'))});
    return _parse(await http.get(uri, headers: _h).timeout(const Duration(seconds: 20)));
  }
  static Future<Map<String, dynamic>> post(String action, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$kBase?action=$action');
    return _parse(await http.post(uri, headers: {..._h, 'Content-Type': 'application/json'}, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 20)));
  }
  static Future<Map<String, dynamic>> upload(String action, String field, String path, [Map<String, String>? fields]) async {
    final req = http.MultipartRequest('POST', Uri.parse('$kBase?action=$action'))
      ..headers.addAll(_h)..fields.addAll(fields ?? {})
      ..files.add(await http.MultipartFile.fromPath(field, path));
    final s = await req.send().timeout(const Duration(seconds: 60));
    return _parse(await http.Response.fromStream(s));
  }
}
