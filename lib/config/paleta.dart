import 'package:flutter/material.dart';

import '../modelos/nodo.dart';

/// Colores del dashboard en un solo sitio, para que graficas, tarjetas y
/// leyendas no se desincronicen.
class Paleta {
  const Paleta._();

  static const Color sensor1 = Color(0xFFE8590C); // naranja
  static const Color sensor2 = Color(0xFF0C8599); // cian

  static const Color enLinea = Color(0xFF2F9E44);
  static const Color desconectado = Color(0xFFE03131);
  static const Color inactivo = Color(0xFF868E96);

  /// Color del indicador de un nodo segun su estado real (incluye el caso
  /// "dice online pero lleva rato sin publicar").
  static Color deNodo(Nodo nodo) {
    if (nodo.estado == EstadoNodo.desconectado) return desconectado;
    return nodo.activo ? enLinea : inactivo;
  }

  static String etiquetaDeNodo(Nodo nodo) {
    if (nodo.estado == EstadoNodo.desconectado) return 'Desconectado';
    if (nodo.lecturas.isEmpty) return 'Sin lecturas';
    return nodo.activo ? 'En linea' : 'Sin senal';
  }
}
