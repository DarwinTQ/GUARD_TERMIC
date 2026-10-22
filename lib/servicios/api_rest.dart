import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/ajustes.dart';
import '../modelos/lectura.dart';
import '../modelos/nodo.dart';

/// Cliente de la API REST de historial (`infra/servicios/api`).
///
/// Solo se usa al arrancar, para rellenar las graficas con lo ya almacenado.
/// A partir de ahi el tiempo real llega por MQTT.
class ApiRest {
  ApiRest({http.Client? cliente, String? urlBase})
      : _cliente = cliente ?? http.Client(),
        _urlBase = urlBase ?? Ajustes.urlApi;

  final http.Client _cliente;
  final String _urlBase;

  static const Duration _tiempoLimite = Duration(seconds: 6);

  /// Historial reciente agrupado por nodo, de la mas antigua a la mas nueva.
  ///
  /// La API devuelve las lecturas de la mas nueva a la mas antigua; aqui se
  /// invierten porque las graficas necesitan el tiempo creciente.
  Future<Map<String, List<Lectura>>> historialPorNodo({
    int limite = Ajustes.limiteHistorial,
  }) async {
    final crudas = await _obtenerLista('/lecturas?limite=$limite');
    final porNodo = <String, List<Lectura>>{};

    for (final json in crudas.reversed) {
      final lectura = Lectura.desdeApi(json);
      (porNodo[lectura.dispositivo] ??= <Lectura>[]).add(lectura);
    }

    // Recorta cada serie a la ventana que muestra el grafico.
    for (final entrada in porNodo.entries) {
      final exceso = entrada.value.length - Ajustes.maxPuntosPorNodo;
      if (exceso > 0) {
        porNodo[entrada.key] = entrada.value.sublist(exceso);
      }
    }
    return porNodo;
  }

  /// Estado conocido de cada nodo (incluye los que ahora estan apagados).
  Future<Map<String, EstadoNodo>> estadoDeNodos() async {
    final crudos = await _obtenerLista('/dispositivos');
    return {
      for (final json in crudos)
        json['dispositivo'] as String:
            EstadoNodo.desdeTexto(json['estado'] as String?),
    };
  }

  Future<List<Map<String, dynamic>>> _obtenerLista(String ruta) async {
    final respuesta =
        await _cliente.get(Uri.parse('$_urlBase$ruta')).timeout(_tiempoLimite);

    if (respuesta.statusCode != 200) {
      throw ApiExcepcion(
        'La API respondio ${respuesta.statusCode} en $ruta',
        codigo: respuesta.statusCode,
      );
    }
    final decodificado = jsonDecode(utf8.decode(respuesta.bodyBytes));
    return (decodificado as List).cast<Map<String, dynamic>>();
  }

  void cerrar() => _cliente.close();
}

class ApiExcepcion implements Exception {
  const ApiExcepcion(this.mensaje, {this.codigo});

  final String mensaje;
  final int? codigo;

  @override
  String toString() => mensaje;
}
