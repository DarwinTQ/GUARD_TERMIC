import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/paleta.dart';
import '../modelos/lectura.dart';
import '../modelos/nodo.dart';

/// Tarjeta seleccionable de un nodo: estado, ultimas temperaturas y tendencia.
class TarjetaNodo extends StatelessWidget {
  const TarjetaNodo({
    required this.nodo,
    required this.seleccionado,
    required this.onSeleccionar,
    super.key,
  });

  final Nodo nodo;
  final bool seleccionado;
  final VoidCallback onSeleccionar;

  /// Puntos que entran en la mini grafica de la tarjeta.
  static const int _puntosSparkline = 30;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = Paleta.deNodo(nodo);
    final ultima = nodo.ultima;

    return Card(
      elevation: seleccionado ? 3 : 0,
      color: seleccionado ? tema.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: seleccionado
              ? tema.colorScheme.primary
              : tema.dividerColor.withValues(alpha: 0.5),
          width: seleccionado ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSeleccionar,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nodo.id,
                      style: tema.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                Paleta.etiquetaDeNodo(nodo),
                style: tema.textTheme.bodySmall?.copyWith(color: color),
              ),
              const SizedBox(height: 12),
              if (ultima == null)
                Text('-- °C', style: tema.textTheme.headlineSmall)
              else
                Row(
                  children: [
                    _valor(context, ultima.sensor1, Paleta.sensor1),
                    const SizedBox(width: 14),
                    _valor(context, ultima.sensor2, Paleta.sensor2),
                  ],
                ),
              const SizedBox(height: 10),
              SizedBox(height: 34, child: _sparkline()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _valor(BuildContext context, double temperatura, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 18, height: 3, color: color),
        const SizedBox(height: 4),
        Text(
          '${temperatura.toStringAsFixed(1)} °C',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// Mini grafica sin ejes: solo la tendencia de los ultimos puntos.
  Widget _sparkline() {
    final total = nodo.lecturas.length;
    final datos = total > _puntosSparkline
        ? nodo.lecturas.sublist(total - _puntosSparkline)
        : nodo.lecturas;

    if (datos.length < 2) return const SizedBox.shrink();

    LineChartBarData linea(double Function(Lectura) valor, Color color) {
      return LineChartBarData(
        spots: [
          for (var i = 0; i < datos.length; i++)
            FlSpot(i.toDouble(), valor(datos[i])),
        ],
        isCurved: true,
        color: color,
        barWidth: 1.8,
        dotData: const FlDotData(show: false),
      );
    }

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          linea((lectura) => lectura.sensor1, Paleta.sensor1),
          linea((lectura) => lectura.sensor2, Paleta.sensor2),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
