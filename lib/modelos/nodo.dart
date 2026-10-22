import 'package:flutter/foundation.dart';

import '../config/ajustes.dart';
import 'lectura.dart';

/// Conectividad de un nodo, segun el Last Will que publica el broker.
enum EstadoNodo {
  enLinea('En linea'),
  desconectado('Desconectado'),
  desconocido('Sin datos');

  const EstadoNodo(this.etiqueta);
  final String etiqueta;

  static EstadoNodo desdeTexto(String? texto) => switch (texto?.toLowerCase()) {
        'online' => EstadoNodo.enLinea,
        'offline' => EstadoNodo.desconectado,
        _ => EstadoNodo.desconocido,
      };
}

/// Estado de un nodo ESP32 en el dashboard: sus ultimas lecturas y si responde.
///
/// Inmutable: el controlador reemplaza la instancia en cada evento, de modo
/// que la UI nunca lee una lista a medio mutar.
@immutable
class Nodo {
  const Nodo({
    required this.id,
    required this.lecturas,
    this.estado = EstadoNodo.desconocido,
  });

  final String id;
  final EstadoNodo estado;

  /// Ordenadas de la mas antigua a la mas reciente (lista para graficar).
  final List<Lectura> lecturas;

  Lectura? get ultima => lecturas.isEmpty ? null : lecturas.last;

  /// Un nodo puede decir "online" y haber dejado de publicar: si no llega
  /// nada en [Ajustes.tiempoSinSenal] lo tratamos como inactivo.
  bool get activo {
    final reciente = ultima;
    if (reciente == null || estado == EstadoNodo.desconectado) return false;
    return DateTime.now().difference(reciente.fecha) < Ajustes.tiempoSinSenal;
  }

  /// Añade una lectura manteniendo la ventana deslizante acotada.
  Nodo conLectura(Lectura lectura) {
    final siguientes = [...lecturas, lectura];
    final exceso = siguientes.length - Ajustes.maxPuntosPorNodo;
    return copiarCon(
      lecturas: exceso > 0 ? siguientes.sublist(exceso) : siguientes,
      estado: EstadoNodo.enLinea, // si publica, esta vivo
    );
  }

  Nodo copiarCon({List<Lectura>? lecturas, EstadoNodo? estado}) => Nodo(
        id: id,
        lecturas: lecturas ?? this.lecturas,
        estado: estado ?? this.estado,
      );
}
