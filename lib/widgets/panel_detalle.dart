import 'package:flutter/material.dart';

import '../config/paleta.dart';
import '../estado/monitor_controlador.dart';
import '../modelos/lectura.dart';
import '../modelos/metricas.dart';
import '../modelos/nodo.dart';
import '../util/formato.dart';
import 'grafico_temperaturas.dart';
import 'leyenda_series.dart';
import 'seccion.dart';

/// Panel con el detalle del nodo seleccionado: valores actuales, grafica en
/// tiempo real y las ultimas lecturas recibidas.
///
/// Las estadisticas de cabecera (minimo, maximo, media) se calculan sobre
/// [lecturasVisibles], no sobre toda la serie: si el usuario esta mirando la
/// ventana de 1 minuto, el maximo que lee tiene que ser el de ese minuto,
/// no el de hace media hora.
class PanelDetalle extends StatelessWidget {
  const PanelDetalle({
    required this.nodo,
    required this.lecturasVisibles,
    required this.ventana,
    required this.onCambiarVentana,
    required this.metricas,
    super.key,
  });

  final Nodo nodo;
  final List<Lectura> lecturasVisibles;
  final VentanaTiempo ventana;
  final ValueChanged<VentanaTiempo> onCambiarVentana;
  final MetricasNodo metricas;

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
              'Ultima lectura ${Formato.hora(ultima.fecha)} '
              '(${Formato.hace(ultima.fecha)})'
              '${ultima.rssi != null ? '  ·  RSSI ${ultima.rssi} dBm' : ''}',
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
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
        Seccion(
          titulo: 'Temperatura en tiempo real',
          descripcion: _descripcionVentana(),
          acciones: [
            _SelectorVentana(ventana: ventana, onCambiar: onCambiarVentana),
          ],
          hijo: Panel(
            hijo: Column(
              children: [
                SizedBox(
                  height: 260,
                  child: GraficoTemperaturas(
                    lecturas: nodo.lecturas,
                    ventana: ventana.duracion,
                  ),
                ),
                const SizedBox(height: 12),
                LeyendaSeries(
                  entradas: [
                    EntradaLeyenda(
                      nombre: 'Sensor 1',
                      color: Paleta.sensor1,
                      valor: Formato.grados(ultima?.sensor1),
                    ),
                    EntradaLeyenda(
                      nombre: 'Sensor 2',
                      color: Paleta.sensor2,
                      valor: Formato.grados(ultima?.sensor2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        RejillaKpi(
          anchoMinimo: 160,
          tarjetas: [
            TarjetaResumenSimple(
              titulo: 'Minimo visible',
              valor: Formato.grados(_extremo(menor: true)),
            ),
            TarjetaResumenSimple(
              titulo: 'Maximo visible',
              valor: Formato.grados(_extremo(menor: false)),
            ),
            TarjetaResumenSimple(
              titulo: 'Media visible',
              valor: Formato.grados(_media()),
            ),
            TarjetaResumenSimple(
              titulo: 'Cadencia real',
              valor: Formato.duracion(metricas.promedio),
              detalle: metricas.desvioNominal == null
                  ? null
                  : '${Formato.desvio(metricas.desvioNominal)} vs nominal',
            ),
          ],
        ),
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
                '${Formato.grados(lectura.sensor1)}'
                '     ${Formato.grados(lectura.sensor2)}',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              trailing: Text(
                Formato.hora(lectura.fecha),
                style: tema.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }

  String _descripcionVentana() {
    final puntos = lecturasVisibles.length;
    final tramo = ventana.duracion == null
        ? 'toda la ventana en memoria'
        : 'ultimos ${ventana.etiqueta}';
    return '$puntos puntos · $tramo';
  }

  double? _extremo({required bool menor}) {
    if (lecturasVisibles.isEmpty) return null;
    final valores = <double>[
      for (final l in lecturasVisibles) ...[l.sensor1, l.sensor2],
    ];
    return valores.reduce((a, b) => (menor ? a < b : a > b) ? a : b);
  }

  double? _media() {
    if (lecturasVisibles.isEmpty) return null;
    final valores = <double>[
      for (final l in lecturasVisibles) ...[l.sensor1, l.sensor2],
    ];
    return valores.reduce((a, b) => a + b) / valores.length;
  }
}

/// Selector de la ventana temporal del grafico.
class _SelectorVentana extends StatelessWidget {
  const _SelectorVentana({required this.ventana, required this.onCambiar});

  final VentanaTiempo ventana;
  final ValueChanged<VentanaTiempo> onCambiar;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<VentanaTiempo>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelSmall,
        ),
      ),
      segments: [
        for (final opcion in VentanaTiempo.values)
          ButtonSegment(value: opcion, label: Text(opcion.etiqueta)),
      ],
      selected: {ventana},
      onSelectionChanged: (seleccion) => onCambiar(seleccion.first),
    );
  }
}

/// Dato secundario en formato compacto, sin icono ni estado.
class TarjetaResumenSimple extends StatelessWidget {
  const TarjetaResumenSimple({
    required this.titulo,
    required this.valor,
    this.detalle,
    super.key,
  });

  final String titulo;
  final String valor;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Panel(
      relleno: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titulo,
            style: tema.textTheme.labelSmall
                ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: tema.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(height: 2),
            Text(
              detalle!,
              style: tema.textTheme.bodySmall
                  ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 7),
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              valor == null ? '--' : Formato.grados(valor),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
