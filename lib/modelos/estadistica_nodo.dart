import 'package:flutter/foundation.dart';

/// Agregados de un sensor calculados por MongoDB sobre la serie completa.
@immutable
class ResumenSensor {
  const ResumenSensor({this.minimo, this.maximo, this.promedio});

  final double? minimo;
  final double? maximo;
  final double? promedio;

  factory ResumenSensor.desdeApi(Map<String, dynamic>? json) => ResumenSensor(
        minimo: (json?['minimo'] as num?)?.toDouble(),
        maximo: (json?['maximo'] as num?)?.toDouble(),
        promedio: (json?['promedio'] as num?)?.toDouble(),
      );

  double? get rango =>
      (minimo == null || maximo == null) ? null : maximo! - minimo!;
}

/// Fila de `GET /estadisticas`: lo que sabe la base de datos de un nodo.
///
/// Es deliberadamente distinto de lo que muestra el dashboard en vivo: aqui
/// el minimo y el maximo son los de todo el historico, no los de la ventana
/// de 120 puntos que la app guarda en memoria.
@immutable
class EstadisticaNodo {
  const EstadisticaNodo({
    required this.dispositivo,
    required this.lecturas,
    required this.sensor1,
    required this.sensor2,
    this.rssiPromedio,
    this.primera,
    this.ultima,
    this.intervaloMedio,
  });

  final String dispositivo;
  final int lecturas;
  final ResumenSensor sensor1;
  final ResumenSensor sensor2;
  final double? rssiPromedio;
  final DateTime? primera;
  final DateTime? ultima;

  /// Periodo real de publicacion medido sobre lo persistido.
  final Duration? intervaloMedio;

  factory EstadisticaNodo.desdeApi(Map<String, dynamic> json) {
    final segundos = (json['intervalo_medio_s'] as num?)?.toDouble();
    return EstadisticaNodo(
      dispositivo: (json['dispositivo'] as String?) ?? '',
      lecturas: (json['lecturas'] as num?)?.toInt() ?? 0,
      sensor1: ResumenSensor.desdeApi(json['sensor1'] as Map<String, dynamic>?),
      sensor2: ResumenSensor.desdeApi(json['sensor2'] as Map<String, dynamic>?),
      rssiPromedio: (json['rssi_prom'] as num?)?.toDouble(),
      primera: _fecha(json['primera']),
      ultima: _fecha(json['ultima']),
      intervaloMedio: segundos == null
          ? null
          : Duration(microseconds: (segundos * 1000000).round()),
    );
  }

  /// Cuanto tiempo cubre la serie almacenada de este nodo.
  Duration? get cobertura =>
      (primera == null || ultima == null) ? null : ultima!.difference(primera!);

  static DateTime? _fecha(Object? valor) =>
      valor is String ? DateTime.parse(valor).toLocal() : null;
}
