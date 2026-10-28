import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/paleta.dart';
import '../modelos/lectura.dart';

/// Grafica de las dos series de temperatura de un nodo, con eje de tiempo real.
///
/// El eje X son milisegundos desde epoch, no el indice de la lectura. Eso
/// cuesta un poco mas de calculo pero es lo que hace que la vista sea de
/// verdad en tiempo real: si un nodo se calla, la linea deja un hueco visible
/// en lugar de seguir dibujando como si no hubiera pasado nada.
///
/// Con [ventana] la ventana se ancla a `ahora`, de modo que el grafico se
/// desplaza solo con cada repintado aunque no lleguen datos nuevos.
class GraficoTemperaturas extends StatelessWidget {
  const GraficoTemperaturas({
    required this.lecturas,
    this.ventana,
    this.mostrarEjes = true,
    super.key,
  });

  /// De la mas antigua a la mas reciente.
  final List<Lectura> lecturas;

  /// Tramo de tiempo visible; `null` muestra todo lo que haya en memoria.
  final Duration? ventana;

  final bool mostrarEjes;

  /// Margen vertical para que las lineas no toquen los bordes.
  static const double _margenY = 1.5;

  @override
  Widget build(BuildContext context) {
    if (lecturas.length < 2) {
      return Center(
        child: Text(
          'Esperando lecturas suficientes para graficar...',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final ahora = DateTime.now().millisecondsSinceEpoch.toDouble();
    final primera = lecturas.first.fecha.millisecondsSinceEpoch.toDouble();
    final ultima = lecturas.last.fecha.millisecondsSinceEpoch.toDouble();

    final (minX, maxX) = ventana == null
        ? (primera, ultima)
        : (ahora - ventana!.inMilliseconds, ahora);

    final visibles =
        lecturas.where((l) => _x(l) >= minX && _x(l) <= maxX).toList();
    final temperaturas = <double>[
      for (final lectura in (visibles.isEmpty ? lecturas : visibles))
        ...[lectura.sensor1, lectura.sensor2],
    ];
    final minimo = temperaturas.reduce((a, b) => a < b ? a : b) - _margenY;
    final maximo = temperaturas.reduce((a, b) => a > b ? a : b) + _margenY;

    final tema = Theme.of(context);

    return LineChart(
      LineChartData(
        minY: minimo,
        maxY: maximo,
        minX: minX,
        maxX: maxX,
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
          show: mostrarEjes,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (valor, meta) => Text(
                '${valor.toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 11,
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Cuatro marcas: con 120 puntos las horas se solaparian.
              interval: ((maxX - minX) / 4).clamp(1, double.infinity),
              getTitlesWidget: (valor, meta) => _etiquetaHora(context, valor),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (puntos) => puntos.map((punto) {
              final esPrimero = punto.barIndex == 0;
              final nombre = esPrimero ? 'Sensor 1' : 'Sensor 2';
              final hora = DateTime.fromMillisecondsSinceEpoch(punto.x.toInt());
              return LineTooltipItem(
                '$nombre  ${punto.y.toStringAsFixed(1)} °C\n${_hora(hora)}',
                TextStyle(
                  color: esPrimero ? Paleta.sensor1 : Paleta.sensor2,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
          getTouchedSpotIndicator: (barra, indices) => indices
              .map(
                (_) => TouchedSpotIndicatorData(
                  FlLine(color: barra.color, strokeWidth: 1),
                  FlDotData(
                    getDotPainter: (spot, porcentaje, datos, indice) =>
                        FlDotCirclePainter(
                      radius: 4,
                      color: barra.color ?? Paleta.sensor1,
                      // Anillo del color de la superficie: separa el punto de
                      // la linea cuando ambos se solapan.
                      strokeColor: tema.colorScheme.surface,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              )
              .toList(),
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

  static double _x(Lectura lectura) =>
      lectura.fecha.millisecondsSinceEpoch.toDouble();

  Widget _etiquetaHora(BuildContext context, double valor) {
    final fecha = DateTime.fromMillisecondsSinceEpoch(valor.toInt());
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        _hora(fecha),
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  LineChartBarData _linea(double Function(Lectura) valor, Color color) {
    return LineChartBarData(
      spots: [for (final lectura in lecturas) FlSpot(_x(lectura), valor(lectura))],
      isCurved: true,
      curveSmoothness: 0.2,
      color: color,
      barWidth: 2,
      // Un unico punto marcado: el ultimo, que es "ahora".
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, datos) =>
            datos.spots.isNotEmpty && spot.x == datos.spots.last.x,
        getDotPainter: (spot, porcentaje, datos, indice) =>
            FlDotCirclePainter(radius: 3.5, color: color, strokeWidth: 0),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.10),
      ),
    );
  }

  static String _hora(DateTime fecha) {
    String dos(int valor) => valor.toString().padLeft(2, '0');
    return '${dos(fecha.hour)}:${dos(fecha.minute)}:${dos(fecha.second)}';
  }
}
