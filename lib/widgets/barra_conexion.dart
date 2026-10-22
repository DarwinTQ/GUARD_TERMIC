import 'package:flutter/material.dart';

import '../servicios/mqtt/mqtt_servicio.dart';

/// Indicador del enlace MQTT para la barra superior.
///
/// Es la pieza que distingue "no hay datos porque no hay nodos" de
/// "no hay datos porque no llego al broker".
class BarraConexion extends StatelessWidget {
  const BarraConexion({
    required this.estado,
    required this.url,
    this.nodosActivos = 0,
    super.key,
  });

  final EstadoConexion estado;
  final String url;
  final int nodosActivos;

  @override
  Widget build(BuildContext context) {
    final (color, texto, icono) = switch (estado) {
      EstadoConexion.conectado => (
          Colors.greenAccent.shade400,
          'MQTT en vivo',
          Icons.sensors,
        ),
      EstadoConexion.conectando => (
          Colors.amberAccent.shade200,
          'Conectando...',
          Icons.sync,
        ),
      EstadoConexion.desconectado => (
          Colors.grey.shade400,
          'Sin conexion',
          Icons.sensors_off,
        ),
      EstadoConexion.error => (
          Colors.redAccent.shade200,
          'Broker inalcanzable',
          Icons.error_outline,
        ),
    };

    return Tooltip(
      message: 'Broker: $url',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 6),
          Text(texto, style: TextStyle(color: color, fontSize: 13)),
          if (estado == EstadoConexion.conectado) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$nodosActivos nodo${nodosActivos == 1 ? '' : 's'}',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
