import 'package:flutter/material.dart';

import '../config/paleta.dart';
import '../modelos/nodo.dart';
import 'grafico_temperaturas.dart';

/// Panel con el detalle del nodo seleccionado: valores actuales, grafica
/// historica y las ultimas lecturas recibidas.
class PanelDetalle extends StatelessWidget {
  const PanelDetalle({required this.nodo, super.key});

  final Nodo nodo;

  /// Cuantas lecturas se listan bajo la grafica.
  static const int _lecturasEnLista = 12;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ultima = nodo.ultima;
    final color = Paleta.deNodo(nodo);

    // Mas recientes primero para la lista de abajo.
    final recientes = nodo.lecturas.reversed.take(_lecturasEnLista).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Icon(Icons.developer_board, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                nodo.id,
                style: tema.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Chip(
              label: Text(Paleta.etiquetaDeNodo(nodo)),
              avatar: Icon(Icons.circle, size: 12, color: color),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (ultima != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Ultima lectura ${_hora(ultima.fecha)}'
              '${ultima.rssi != null ? '  ·  RSSI ${ultima.rssi} dBm' : ''}',
              style: tema.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _TarjetaValor(
                titulo: 'Sensor 1',
                valor: ultima?.sensor1,
                color: Paleta.sensor1,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _TarjetaValor(
                titulo: 'Sensor 2',
                valor: ultima?.sensor2,
                color: Paleta.sensor2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text('Historial', style: tema.textTheme.titleMedium),
        const SizedBox(height: 14),
        SizedBox(height: 260, child: GraficoTemperaturas(lecturas: nodo.lecturas)),
        const SizedBox(height: 12),
        const _Leyenda(),
        const SizedBox(height: 28),
        Text('Ultimas lecturas', style: tema.textTheme.titleMedium),
        const SizedBox(height: 4),
        if (recientes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Este nodo todavia no ha publicado nada.'),
          )
        else
          ...recientes.map(
            (lectura) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.thermostat, size: 20),
              title: Text(
                '${lectura.sensor1.toStringAsFixed(1)} °C'
                '     ${lectura.sensor2.toStringAsFixed(1)} °C',
              ),
              trailing: Text(
                _hora(lectura.fecha),
                style: tema.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }

  static String _hora(DateTime fecha) {
    String dos(int valor) => valor.toString().padLeft(2, '0');
    return '${dos(fecha.hour)}:${dos(fecha.minute)}:${dos(fecha.second)}';
  }
}

class _TarjetaValor extends StatelessWidget {
  const _TarjetaValor({
    required this.titulo,
    required this.valor,
    required this.color,
  });

  final String titulo;
  final double? valor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Column(
          children: [
            Text(
              titulo,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              valor == null ? '--' : '${valor!.toStringAsFixed(1)} °C',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _entrada('Sensor 1', Paleta.sensor1),
        const SizedBox(width: 20),
        _entrada('Sensor 2', Paleta.sensor2),
      ],
    );
  }

  Widget _entrada(String texto, Color color) {
    return Row(
      children: [
        Container(width: 14, height: 4, color: color),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
