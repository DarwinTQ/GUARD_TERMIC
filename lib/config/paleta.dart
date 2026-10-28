import 'package:flutter/material.dart';

import '../modelos/nodo.dart';

/// Colores del dashboard en un solo sitio, para que graficas, tarjetas y
/// leyendas no se desincronicen.
class Paleta {
  const Paleta._();

  // --- Series de temperatura ---
  // Par validado para daltonismo (deutan/protan/tritan) sobre fondo claro y
  // oscuro: separacion suficiente sin depender del color para distinguirlas,
  // porque ademas van siempre con leyenda.
  static const Color sensor1 = Color(0xFFE8590C); // naranja
  static const Color sensor2 = Color(0xFF1098AD); // cian

  // --- Series de transporte (vista de tiempos de respuesta) ---
  // Hues distintos a los de temperatura a proposito: en esta app el naranja
  // y el cian significan "sensor", y reutilizarlos para latencias haria
  // pensar que miden lo mismo.
  static const Color latenciaApi = Color(0xFF7048E8); // violeta
  static const Color latenciaBroker = Color(0xFF0CA678); // verde azulado

  // --- Estado (reservados: nunca se usan como color de serie) ---
  static const Color enLinea = Color(0xFF2F9E44);
  static const Color desconectado = Color(0xFFE03131);
  static const Color inactivo = Color(0xFF868E96);
  static const Color alerta = Color(0xFFF08C00);

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

  /// Umbrales de salud para un tiempo de respuesta, en milisegundos.
  ///
  /// Calibrados para LAN cableada o WiFi local, que es el escenario de este
  /// sistema: por encima de 150 ms algo esta saturado, no es distancia.
  /// Siempre se acompaña de [etiquetaDeLatencia] para no depender del color.
  static Color deLatencia(double? milisegundos) {
    if (milisegundos == null) return desconectado;
    if (milisegundos < 150) return enLinea;
    if (milisegundos < 500) return alerta;
    return desconectado;
  }

  static String etiquetaDeLatencia(double? milisegundos) {
    if (milisegundos == null) return 'Sin respuesta';
    if (milisegundos < 150) return 'Buena';
    if (milisegundos < 500) return 'Lenta';
    return 'Critica';
  }
}
