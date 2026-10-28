import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/paleta.dart';

/// Huecos entre mensajes consecutivos de un nodo, en segundos.
///
/// Barras y no lineas: cada intervalo es una magnitud independiente que se
/// compara con la de al lado y con el nominal, no una serie continua que se
/// interpole. La linea de referencia marca el periodo que deberia tener el
/// firmware, asi que cualquier barra que la supere se ve de inmediato.
///
/// Las barras que pasan del umbral de hueco se pintan con el color de alerta
/// y se explican en la leyenda: el color nunca es la unica pista.
class GraficoIntervalos extends StatelessWidget {
  const GraficoIntervalos({
    required this.intervalos,
    required this.nominal,
    super.key,
  });

  /// De la mas antigua a la mas reciente.
  final List<Duration> intervalos;
  final Duration nominal;

  /// A partir de este multiplo del nominal se considera un hueco anomalo.
  static const double _factorHueco = 1.8;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    if (intervalos.isEmpty) {
      return Center(
        child: Text(
          'Aun no hay dos mensajes seguidos de este nodo.',
          style: tema.textTheme.bodySmall,
        ),
      );
    }

    final segundos = [for (final d in intervalos) d.inMilliseconds / 1000];
    final nominalSeg = nominal.inMilliseconds / 1000;
    final umbral = nominalSeg * _factorHueco;
    final maximo = segundos.reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        minY: 0,
        maxY: (maximo * 1.25).clamp(nominalSeg * 1.5, double.infinity),
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
              reservedSize: 40,
              getTitlesWidget: (valor, meta) => Text(
                '${valor.toStringAsFixed(0)} s',
                style: TextStyle(
                  fontSize: 10,
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          bottomTitles: const AxisTitles(
            // El indice de un hueco no dice nada util; la posicion ya ordena.
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: nominalSeg,
              color: tema.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              strokeWidth: 1,
              dashArray: [5, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: TextStyle(
                  fontSize: 10,
                  color: tema.colorScheme.onSurfaceVariant,
                ),
                labelResolver: (_) =>
                    'nominal ${nominalSeg.toStringAsFixed(0)} s',
              ),
            ),
          ],
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (grupo, indiceGrupo, barra, indiceBarra) {
              final valor = barra.toY;
              final desvio = valor - nominalSeg;
              final signo = desvio >= 0 ? '+' : '';
              return BarTooltipItem(
                '${valor.toStringAsFixed(2)} s\n'
                '$signo${desvio.toStringAsFixed(2)} s vs nominal',
                TextStyle(
                  color: tema.colorScheme.onInverseSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < segundos.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: segundos[i],
                  width: _ancho(segundos.length),
                  // Extremo redondeado arriba, anclado a la linea base.
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  color: segundos[i] > umbral
                      ? Paleta.alerta
                      : tema.colorScheme.primary,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Barras finas y con separacion: con 60 huecos en pantalla, mas grosor
  /// convierte el grafico en una mancha.
  static double _ancho(int cantidad) {
    if (cantidad <= 20) return 10;
    if (cantidad <= 40) return 6;
    return 4;
  }
}
