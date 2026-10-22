import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/paleta.dart';
import '../modelos/lectura.dart';

/// Grafica de las dos series de temperatura de un nodo.
///
/// El eje X es el indice de la lectura, no el tiempo absoluto: las lecturas
/// llegan a intervalo fijo, asi se evita deformar la curva si un nodo pierde
/// un paquete. Las etiquetas inferiores muestran la hora real.
class GraficoTemperaturas extends StatelessWidget {
  const GraficoTemperaturas({required this.lecturas, super.key});

  /// De la mas antigua a la mas reciente.
  final List<Lectura> lecturas;

  /// Margen vertical para que las lineas no toquen los bordes.
  static const double _margenY = 1.5;

  @override
  Widget build(BuildContext context) {
    if (lecturas.length < 2) {
      return const Center(
        child: Text('Esperando lecturas suficientes para graficar...'),
      );
    }

    final temperaturas = <double>[
      for (final lectura in lecturas) ...[lectura.sensor1, lectura.sensor2],
    ];
    final minimo = temperaturas.reduce((a, b) => a < b ? a : b) - _margenY;
    final maximo = temperaturas.reduce((a, b) => a > b ? a : b) + _margenY;

    return LineChart(
      LineChartData(
        minY: minimo,
        maxY: maximo,
        minX: 0,
        maxX: (lecturas.length - 1).toDouble(),
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
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
              reservedSize: 44,
              getTitlesWidget: (valor, meta) => Text(
                '${valor.toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Pocas marcas: con 120 puntos las horas se solaparian.
              interval: (lecturas.length / 4).ceilToDouble(),
              getTitlesWidget: _etiquetaHora,
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (puntos) => puntos.map((punto) {
              final esPrimero = punto.barIndex == 0;
              final color = esPrimero ? Paleta.sensor1 : Paleta.sensor2;
              final nombre = esPrimero ? 'Sensor 1' : 'Sensor 2';
              return LineTooltipItem(
                '$nombre  ${punto.y.toStringAsFixed(1)} °C',
                TextStyle(color: color, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          _linea((lectura) => lectura.sensor1, Paleta.sensor1),
          _linea((lectura) => lectura.sensor2, Paleta.sensor2),
        ],
      ),
      // Sin animacion: con datos cada 5 s el interpolado despista mas que ayuda.
      duration: Duration.zero,
    );
  }

  Widget _etiquetaHora(double valor, TitleMeta meta) {
    final indice = valor.round();
    if (indice < 0 || indice >= lecturas.length) {
      return const SizedBox.shrink();
    }
    final fecha = lecturas[indice].fecha;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '${_dosDigitos(fecha.hour)}:${_dosDigitos(fecha.minute)}',
        style: const TextStyle(fontSize: 10),
      ),
    );
  }

  LineChartBarData _linea(double Function(Lectura) valor, Color color) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < lecturas.length; i++)
          FlSpot(i.toDouble(), valor(lecturas[i])),
      ],
      isCurved: true,
      curveSmoothness: 0.2,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.10),
      ),
    );
  }

  static String _dosDigitos(int valor) => valor.toString().padLeft(2, '0');
}
