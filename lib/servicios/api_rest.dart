import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/ajustes.dart';
import '../modelos/estadistica_nodo.dart';
import '../modelos/lectura.dart';
import '../modelos/metricas.dart';
import '../modelos/nodo.dart';
import '../modelos/resumen_bd.dart';

/// Cliente de la API REST de historial (`infra/servicios/api`).
///
/// Cubre dos usos distintos:
///   * arranque: rellenar las graficas con lo ya almacenado (de ahi en
///     adelante el tiempo real llega por MQTT);
///   * vista de base de datos: consultar lo que hay persistido sin que eso
///     toque el camino del tiempo real.
///
/// Toda peticion se cronometra, porque el tiempo de respuesta de la API es
/// en si mismo un dato que el dashboard muestra.
class ApiRest {
  ApiRest({http.Client? cliente, String? urlBase})
      : _cliente = cliente ?? http.Client(),
        _urlBase = urlBase ?? Ajustes.urlApi;

  final http.Client _cliente;
  final String _urlBase;

  static const Duration _tiempoLimite = Duration(seconds: 6);

  /// Duracion de la ultima peticion completada, sea cual sea la ruta.
  Duration? _ultimaDuracion;
  Duration? get ultimaDuracion => _ultimaDuracion;

  String get urlBase => _urlBase;

  // -------------------------------------------------------------- historial

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

  // -------------------------------------------------------- vista de la BD

  /// Pagina de lecturas crudas, tal cual estan en Mongo (mas nueva primero).
  ///
  /// A diferencia de [historialPorNodo] aqui no se invierte ni se agrupa: la
  /// tabla muestra la coleccion en su orden natural.
  Future<List<Lectura>> lecturas({
    int limite = Ajustes.filasPorPagina,
    int desplazamiento = 0,
    String? dispositivo,
  }) async {
    final filtro = dispositivo == null ? '' : '&dispositivo=$dispositivo';
    final crudas = await _obtenerLista(
      '/lecturas?limite=$limite&desplazamiento=$desplazamiento$filtro',
    );
    return crudas.map(Lectura.desdeApi).toList();
  }

  /// Numero total de lecturas almacenadas (para paginar y para el contador).
  Future<int> totalLecturas({String? dispositivo}) async {
    final filtro = dispositivo == null ? '' : '?dispositivo=$dispositivo';
    final json = await _obtenerMapa('/lecturas/total$filtro');
    return (json['total'] as num?)?.toInt() ?? 0;
  }

  /// Agregados por nodo calculados por Mongo sobre toda la serie.
  Future<List<EstadisticaNodo>> estadisticas({int? horas}) async {
    final crudas = await _obtenerLista(
      horas == null ? '/estadisticas' : '/estadisticas?horas=$horas',
    );
    return crudas.map(EstadisticaNodo.desdeApi).toList();
  }

  /// Colecciones, indices y tamaño de la base.
  Future<ResumenBd> resumenBd() async =>
      ResumenBd.desdeApi(await _obtenerMapa('/bd/resumen'));

  // ---------------------------------------------------------------- sondeo

  /// Mide el tiempo de respuesta de la API golpeando su endpoint de estado.
  ///
  /// Nunca lanza: un fallo es una muestra valida (y la mas interesante).
  Future<MuestraLatencia> sondear() async {
    final inicio = DateTime.now();
    final reloj = Stopwatch()..start();
    try {
      final respuesta = await _cliente
          .get(Uri.parse('$_urlBase/'))
          .timeout(Ajustes.tiempoLimiteSonda);
      reloj.stop();

      if (respuesta.statusCode != 200) {
        return MuestraLatencia.fallida(
          instante: inicio,
          detalle: 'HTTP ${respuesta.statusCode}',
        );
      }
      _ultimaDuracion = reloj.elapsed;
      return MuestraLatencia(instante: inicio, duracion: reloj.elapsed);
    } catch (error) {
      return MuestraLatencia.fallida(
        instante: inicio,
        detalle: _motivo(error),
      );
    }
  }

  // ------------------------------------------------------------- transporte

  Future<List<Map<String, dynamic>>> _obtenerLista(String ruta) async {
    final decodificado = await _obtener(ruta);
    return (decodificado as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _obtenerMapa(String ruta) async {
    final decodificado = await _obtener(ruta);
    return decodificado as Map<String, dynamic>;
  }

  Future<Object?> _obtener(String ruta) async {
    final reloj = Stopwatch()..start();
    final respuesta =
        await _cliente.get(Uri.parse('$_urlBase$ruta')).timeout(_tiempoLimite);
    reloj.stop();
    _ultimaDuracion = reloj.elapsed;

    if (respuesta.statusCode != 200) {
      throw ApiExcepcion(
        'La API respondio ${respuesta.statusCode} en $ruta',
        codigo: respuesta.statusCode,
      );
    }
    return jsonDecode(utf8.decode(respuesta.bodyBytes));
  }

  /// Mensaje corto para la tabla de sondas: el `toString` de una excepcion de
  /// red ocupa varias lineas y no cabe en una celda.
  static String _motivo(Object error) {
    final texto = error.toString();
    if (texto.contains('TimeoutException')) return 'Tiempo agotado';
    if (texto.contains('Connection refused')) return 'Conexion rechazada';
    if (texto.contains('Failed host lookup')) return 'Host no resuelto';
    return texto.length > 60 ? '${texto.substring(0, 60)}...' : texto;
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
