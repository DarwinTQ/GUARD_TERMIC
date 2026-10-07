import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lectura.dart';

class Api {
  // ====== CONFIG ======
//static const String baseUrl = 'http://10.0.2.2:8001';
static const String baseUrl = 'http://10.82.82.103:8001';
  // ============================

  static Future<List<Lectura>> obtenerLecturas({int limite = 50}) async {
    final res = await http
        .get(Uri.parse('$baseUrl/lecturas?limite=$limite'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('Error ${res.statusCode} al cargar lecturas');
    }
    final List data = jsonDecode(res.body);
    return data.map((e) => Lectura.fromJson(e)).toList();
  }
}
