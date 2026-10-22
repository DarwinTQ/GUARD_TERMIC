import 'package:flutter/foundation.dart';

/// Una lectura de temperatura de un nodo, con sus dos sensores.
///
/// Llega por dos caminos y el modelo unifica ambos:
///   * REST (`/lecturas`): tiene `id` y la fecha la puso el servidor.
///   * MQTT en vivo: no tiene `id` todavia y se sella con la hora de llegada.
@immutable
class Lectura {
  const Lectura({
    required this.dispositivo,
    required this.sensor1,
    required this.sensor2,
    required this.fecha,
    this.id,
    this.rssi,
  });

  final String? id;
  final String dispositivo;
  final double sensor1;
  final double sensor2;
  final DateTime fecha;
  final int? rssi;

  /// Media de ambos sensores, util para tarjetas resumidas.
  double get promedio => (sensor1 + sensor2) / 2;

  /// Documento devuelto por la API REST (fecha UTC del servidor).
  factory Lectura.desdeApi(Map<String, dynamic> json) => Lectura(
        id: json['id'] as String?,
        dispositivo: (json['dispositivo'] as String?) ?? '',
        sensor1: _aDouble(json['sensor1']),
        sensor2: _aDouble(json['sensor2']),
        fecha: DateTime.parse(json['fecha'] as String).toLocal(),
        rssi: (json['rssi'] as num?)?.toInt(),
      );

  /// Payload MQTT publicado por el ESP32.
  ///
  /// El nodo no tiene reloj, asi que para la vista en vivo se usa la hora de
  /// llegada; la fecha autoritativa la pone la ingesta al persistir.
  factory Lectura.desdeMqtt(
    Map<String, dynamic> json, {
    required String dispositivo,
    required DateTime recibida,
  }) =>
      Lectura(
        dispositivo: dispositivo,
        sensor1: _aDouble(json['sensor1']),
        sensor2: _aDouble(json['sensor2']),
        fecha: recibida,
        rssi: (json['rssi'] as num?)?.toInt(),
      );

  static double _aDouble(Object? valor) => (valor as num).toDouble();

  @override
  String toString() => 'Lectura($dispositivo, $sensor1, $sensor2, $fecha)';
}
