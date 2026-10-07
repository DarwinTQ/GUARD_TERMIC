import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'lectura.dart';

void main() => runApp(const AppTemperaturas());

class AppTemperaturas extends StatelessWidget {
  const AppTemperaturas({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monitor de Temperatura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const PantallaPrincipal(),
    );
  }
}

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  static const colorS1 = Colors.deepOrange;
  static const colorS2 = Colors.teal;

  List<Lectura> lecturas = [];
  String? error;
  bool cargando = true;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    cargar();
    // Refresca cada 5 s para verlo "en vivo"
    timer = Timer.periodic(const Duration(seconds: 5), (_) => cargar());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> cargar() async {
    try {
      final datos = await Api.obtenerLecturas(limite: 50);
      if (!mounted) return;
      setState(() {
        lecturas = datos;
        error = null;
        cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudo conectar al servidor.\n${Api.baseUrl}';
        cargando = false;
      });
    }
  }

  String hora(DateTime f) =>
      '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}:${f.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor de Temperatura'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: cargar)],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (cargando) return const Center(child: CircularProgressIndicator());
    if (error != null && lecturas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (lecturas.isEmpty) {
      return const Center(child: Text('Aún no hay lecturas'));
    }

    final ultima = lecturas.first; // la API las devuelve de la más nueva a la más antigua
    return RefreshIndicator(
      onRefresh: cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: _tarjeta('Sensor 1', ultima.sensor1, colorS1)),
            const SizedBox(width: 12),
            Expanded(child: _tarjeta('Sensor 2', ultima.sensor2, colorS2)),
          ]),
          const SizedBox(height: 8),
          Text('Última lectura: ${hora(ultima.fecha)}',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          if (error != null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Sin conexión, mostrando últimos datos',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 20),
          Text('Historial', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(height: 240, child: _grafico()),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _leyenda('Sensor 1', colorS1),
            const SizedBox(width: 16),
            _leyenda('Sensor 2', colorS2),
          ]),
          const SizedBox(height: 20),
          Text('Últimas lecturas', style: Theme.of(context).textTheme.titleMedium),
          ...lecturas.take(15).map((l) => ListTile(
                dense: true,
                leading: const Icon(Icons.thermostat),
                title: Text('${l.sensor1.toStringAsFixed(1)} °C   |   ${l.sensor2.toStringAsFixed(1)} °C'),
                subtitle: Text('${hora(l.fecha)} · ${l.dispositivo}'),
              )),
        ],
      ),
    );
  }

  Widget _tarjeta(String titulo, double valor, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(children: [
          Text(titulo, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('${valor.toStringAsFixed(1)} °C',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _leyenda(String texto, Color color) => Row(children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 6),
        Text(texto),
      ]);

  Widget _grafico() {
    // Del más antiguo al más nuevo para que el tiempo avance hacia la derecha
    final datos = lecturas.reversed.toList();
    List<FlSpot> puntos(double Function(Lectura) valor) =>
        [for (var i = 0; i < datos.length; i++) FlSpot(i.toDouble(), valor(datos[i]))];

    LineChartBarData linea(List<FlSpot> spots, Color color) => LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
        );

    return LineChart(LineChartData(
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, meta) => Text('${v.toStringAsFixed(0)}°', style: const TextStyle(fontSize: 11)),
          ),
        ),
      ),
      lineBarsData: [
        linea(puntos((l) => l.sensor1), colorS1),
        linea(puntos((l) => l.sensor2), colorS2),
      ],
    ));
  }
}
