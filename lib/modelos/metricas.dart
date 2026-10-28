import 'package:flutter/foundation.dart';

import '../config/ajustes.dart';

/// Una medicion puntual de tiempo de respuesta.
///
/// Un fallo tambien es una muestra: sin registrarlo, un servicio que deja de
/// responder bajaria la latencia media en lugar de empeorarla.
@immutable
class MuestraLatencia {
  const MuestraLatencia({
    required this.instante,
    required this.duracion,
    this.detalle,
  });

  /// Medicion fallida (tiempo agotado, servicio caido, error de red).
  const MuestraLatencia.fallida({required this.instante, this.detalle})
      : duracion = null;

  final DateTime instante;

  /// `null` cuando la sonda no obtuvo respuesta.
  final Duration? duracion;

  /// Motivo del fallo, para mostrarlo en la tabla de sondas.
  final String? detalle;

  bool get ok => duracion != null;

  double? get milisegundos =>
      duracion == null ? null : duracion!.inMicroseconds / 1000;
}

/// Ventana deslizante de muestras de latencia con sus estadisticos.
///
/// Acumula en memoria del cliente: estas mediciones no se persisten, miden
/// la experiencia de *esta* app contra *este* servidor, que es justo lo que
/// se quiere ver cuando el dashboard va lento.
class SerieLatencia {
  SerieLatencia(this.nombre);

  /// Nombre visible de lo que se esta midiendo ("API REST", "Broker MQTT").
  final String nombre;

  final List<MuestraLatencia> _muestras = [];

  /// De la mas antigua a la mas reciente.
  List<MuestraLatencia> get muestras => List.unmodifiable(_muestras);

  bool get vacia => _muestras.isEmpty;
  int get total => _muestras.length;

  void agregar(MuestraLatencia muestra) {
    _muestras.add(muestra);
    final exceso = _muestras.length - Ajustes.maxMuestrasLatencia;
    if (exceso > 0) _muestras.removeRange(0, exceso);
  }

  void limpiar() => _muestras.clear();

  MuestraLatencia? get ultima => _muestras.isEmpty ? null : _muestras.last;

  /// Solo las mediciones con respuesta, ordenadas de menor a mayor.
  List<double> get _validasOrdenadas {
    final valores = [
      for (final m in _muestras)
        if (m.milisegundos != null) m.milisegundos!,
    ];
    valores.sort();
    return valores;
  }

  double? get ultimaMs => ultima?.milisegundos;

  double? get promedioMs {
    final valores = _validasOrdenadas;
    if (valores.isEmpty) return null;
    return valores.reduce((a, b) => a + b) / valores.length;
  }

  double? get minimoMs {
    final valores = _validasOrdenadas;
    return valores.isEmpty ? null : valores.first;
  }

  double? get maximoMs {
    final valores = _validasOrdenadas;
    return valores.isEmpty ? null : valores.last;
  }

  /// Percentil 95: el pico que sufre 1 de cada 20 peticiones.
  ///
  /// Es mas honesto que la media para un panel de salud: la media esconde
  /// los picos que son justo los que se notan al usar la app.
  double? get p95Ms => percentil(95);

  double? percentil(int p) {
    final valores = _validasOrdenadas;
    if (valores.isEmpty) return null;
    final indice = ((p / 100) * (valores.length - 1)).round();
    return valores[indice.clamp(0, valores.length - 1)];
  }

  int get fallos => _muestras.where((m) => !m.ok).length;

  /// Porcentaje de sondas respondidas sobre el total de la ventana.
  double? get disponibilidad {
    if (_muestras.isEmpty) return null;
    return (_muestras.length - fallos) / _muestras.length * 100;
  }
}

/// Metricas de llegada de un nodo: cada cuanto publica realmente.
///
/// El firmware dice publicar cada [Ajustes.intervaloNominalNodo], pero el
/// intervalo real lo marcan la WiFi, el broker y la carga del nodo. Esta
/// clase mide la diferencia, que es lo unico que delata un nodo que se esta
/// degradando antes de caerse del todo.
class MetricasNodo {
  MetricasNodo(this.nodo);

  final String nodo;

  final List<Duration> _intervalos = [];
  DateTime? _ultimaLlegada;
  DateTime? _primeraLlegada;
  int _mensajes = 0;

  /// Registra la llegada de una lectura en vivo.
  ///
  /// Solo se llama desde el flujo MQTT: el historial REST tiene la fecha que
  /// puso el servidor al persistir, no la de llegada a esta app, y mezclar
  /// ambas falsearia los intervalos.
  void registrarLlegada(DateTime instante) {
    _primeraLlegada ??= instante;
    final anterior = _ultimaLlegada;
    if (anterior != null) {
      final hueco = instante.difference(anterior);
      // Un reloj que retrocede (cambio de hora, suspension) daria negativos.
      if (!hueco.isNegative) {
        _intervalos.add(hueco);
        final exceso = _intervalos.length - Ajustes.maxIntervalosPorNodo;
        if (exceso > 0) _intervalos.removeRange(0, exceso);
      }
    }
    _ultimaLlegada = instante;
    _mensajes++;
  }

  /// De la mas antigua a la mas reciente.
  List<Duration> get intervalos => List.unmodifiable(_intervalos);

  int get mensajes => _mensajes;
  DateTime? get ultimaLlegada => _ultimaLlegada;
  bool get vacia => _intervalos.isEmpty;

  /// Tiempo transcurrido desde el ultimo mensaje.
  Duration? get desdeUltima {
    final ultima = _ultimaLlegada;
    return ultima == null ? null : DateTime.now().difference(ultima);
  }

  Duration? get ultimo => _intervalos.isEmpty ? null : _intervalos.last;

  Duration? get promedio {
    if (_intervalos.isEmpty) return null;
    final total = _intervalos.fold<int>(0, (a, d) => a + d.inMicroseconds);
    return Duration(microseconds: total ~/ _intervalos.length);
  }

  Duration? get minimo => _extremo(menor: true);
  Duration? get maximo => _extremo(menor: false);

  Duration? _extremo({required bool menor}) {
    if (_intervalos.isEmpty) return null;
    return _intervalos.reduce(
      (a, b) => (menor ? a < b : a > b) ? a : b,
    );
  }

  Duration? get p95 {
    if (_intervalos.isEmpty) return null;
    final ordenados = [..._intervalos]..sort();
    final indice = (0.95 * (ordenados.length - 1)).round();
    return ordenados[indice.clamp(0, ordenados.length - 1)];
  }

  /// Jitter: desviacion media absoluta de los intervalos respecto a su media.
  ///
  /// Cerca de cero = cadencia de reloj; alto = la red esta agrupando y
  /// soltando mensajes a rafagas aunque el promedio parezca correcto.
  Duration? get jitter {
    final media = promedio;
    if (media == null || _intervalos.length < 2) return null;
    final suma = _intervalos.fold<int>(
      0,
      (a, d) => a + (d.inMicroseconds - media.inMicroseconds).abs(),
    );
    return Duration(microseconds: suma ~/ _intervalos.length);
  }

  /// Diferencia entre el ritmo real y el nominal del firmware.
  /// Positivo = el nodo va mas lento de lo que deberia.
  Duration? get desvioNominal {
    final media = promedio;
    if (media == null) return null;
    return media - Ajustes.intervaloNominalNodo;
  }

  /// Huecos de mas de 1.8 veces el intervalo nominal.
  ///
  /// Con QoS 0 en telemetria no hay reintento, asi que un hueco asi es casi
  /// siempre un mensaje que se perdio por el camino.
  int get huecos {
    final umbral = Ajustes.intervaloNominalNodo * 1.8;
    return _intervalos.where((d) => d > umbral).length;
  }

  /// Mensajes por minuto segun el intervalo medio observado.
  double? get mensajesPorMinuto {
    final media = promedio;
    if (media == null || media.inMicroseconds == 0) return null;
    return 60 * 1000000 / media.inMicroseconds;
  }
}
