import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../modelos/metricas.dart';

/// Una serie de latencias lista para pintar.
@immutable
class TrazoLatencia {
  const TrazoLatencia({
    required this.nombre,
    required this.color,
    required this.muestras,
  });

  final String nombre;
  final Color color;
  final List<MuestraLatencia> muestras;
}

/// Evolucion de los tiempos de respuesta medidos por la app.
///
/// Las dos series comparten eje porque miden lo mismo (milisegundos de ida y
/// vuelta); si alguna vez hiciera falta graficar algo de otra magnitud, va en
/// otro grafico, no en un segundo eje.
///
/// Las sondas fallidas no se dibujan: dejan un hueco en la linea. Es
/// deliberado -interpolar sobre un fallo pintaria una latencia que nunca
/// existio- y el numero de fallos se muestra aparte.
class GraficoLatencia extends StatelessWidget {
  const GraficoLatencia({required this.trazos, super.key});

  final List<TrazoLatencia> trazos;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final conDatos = trazos.where((t) => t.muestras.length >= 2).toList();

    if (conDatos.isEmpty) {
      return Center(
        child: Text(
          'Midiendo... la primera grafica aparece con dos sondas.',
          style: tema.textTheme.bodySmall,
        ),
      );
    }

    final instantes = <double>[
      for (final trazo in conDatos)
        for (final muestra in trazo.muestras)
          muestra.instante.millisecondsSinceEpoch.toDouble(),
    ];
    final valores = <double>[
      for (final trazo in conDatos)
        for (final muestra in trazo.muestras)
          if (muestra.milisegundos != null) muestra.milisegundos!,
    ];

    if (valores.isEmpty) {
      return Center(
        child: Text(
          'Ninguna sonda obtuvo respuesta.',
          style: tema.textTheme.bodySmall,
        ),
      );
    }

    final minX = instantes.reduce((a, b) => a < b ? a : b);
    final maxX = instantes.reduce((a, b) => a > b ? a : b);
    final maxValor = valores.reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX == minX ? minX + 1 : maxX,
        minY: 0,
        // Un 20% de aire arriba para que el pico no quede pegado al borde.
        maxY: (maxValor * 1.2).clamp(10, double.infinity),
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: tema.dividerColor.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (valor, meta) => Text(
                '${valor.toStringAsFixed(0)} ms',
                style: TextStyle(
                  fontSize: 10,
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: ((maxX - minX) / 4).clamp(1, double.infinity),
              getTitlesWidget: (valor, meta) {
                final fecha =
                    DateTime.fromMillisecondsSinceEpoch(valor.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _hora(fecha),
                    style: TextStyle(
                      fontSize: 10,
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (puntos) => puntos.map((punto) {
              final trazo = conDatos[punto.barIndex.clamp(0, conDatos.length - 1)];
              final fecha = DateTime.fromMillisecondsSinceEpoch(punto.x.toInt());
              return LineTooltipItem(
                '${trazo.nombre}  ${punto.y.toStringAsFixed(1)} ms\n${_hora(fecha)}',
                TextStyle(
                  color: trazo.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          for (final trazo in conDatos)
            LineChartBarData(
              spots: [
                for (final muestra in trazo.muestras)
                  if (muestra.milisegundos != null)
                    FlSpot(
                      muestra.instante.millisecondsSinceEpoch.toDouble(),
                      muestra.milisegundos!,
                    ),
              ],
              isCurved: false,
              color: trazo.color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: trazo.color.withValues(alpha: 0.08),
              ),
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  static String _hora(DateTime fecha) {
    String dos(int valor) => valor.toString().padLeft(2, '0');
    return '${dos(fecha.hour)}:${dos(fecha.minute)}:${dos(fecha.second)}';
  }
}
