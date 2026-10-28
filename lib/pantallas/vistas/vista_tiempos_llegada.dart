import 'package:flutter/material.dart';

import '../../config/ajustes.dart';
import '../../config/paleta.dart';
import '../../estado/monitor_controlador.dart';
import '../../modelos/metricas.dart';
import '../../modelos/nodo.dart';
import '../../util/formato.dart';
import '../../widgets/grafico_intervalos.dart';
import '../../widgets/panel_detalle.dart' show TarjetaResumenSimple;
import '../../widgets/seccion.dart';
import '../../widgets/tarjeta_kpi.dart';

/// Con que puntualidad publica cada nodo.
///
/// El firmware publica cada [Ajustes.intervaloNominalNodo]; lo que se mide
/// aqui es el hueco real entre dos mensajes consecutivos tal y como llegan a
/// esta app. La diferencia entre ambos numeros es la que avisa de un nodo que
/// se esta degradando -WiFi al limite, broker saturado, nodo reiniciandose-
/// mucho antes de que acabe marcado como caido.
///
/// Solo cuenta el trafico en vivo: el historial que viene de la API lleva la
/// fecha que puso el servidor al persistir, no la de llegada, y mezclar las
/// dos falsearia los intervalos.
class VistaTiemposLlegada extends StatelessWidget {
  const VistaTiemposLlegada({required this.controlador, super.key});

  final MonitorControlador controlador;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final nodos = controlador.nodos;

    if (nodos.isEmpty) {
      return Center(
        child: Text(
          'Sin nodos todavia.',
          style: tema.textTheme.bodyMedium,
        ),
      );
    }

    final conMetricas = [
      for (final nodo in nodos) (nodo, controlador.metricasDe(nodo.id)),
    ];
    final totalHuecos =
        conMetricas.fold<int>(0, (suma, par) => suma + par.$2.huecos);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Seccion(
          titulo: 'Cadencia global',
          descripcion:
              'Medido desde que se abrio la app: '
              '${Formato.duracion(controlador.tiempoEnMarcha)}.',
          hijo: RejillaKpi(
            tarjetas: [
              TarjetaKpi(
                titulo: 'Mensajes en vivo',
                valor: Formato.entero(controlador.lecturasEnVivo),
                icono: Icons.bolt_outlined,
                detalle: '${nodos.length} nodos publicando',
              ),
              TarjetaKpi(
                titulo: 'Intervalo nominal',
                valor: Formato.duracion(Ajustes.intervaloNominalNodo),
                icono: Icons.timer_outlined,
                detalle: 'INTERVALO_MS del firmware',
              ),
              TarjetaKpi(
                titulo: 'Huecos detectados',
                valor: Formato.entero(totalHuecos),
                icono: Icons.link_off,
                colorEstado:
                    totalHuecos == 0 ? Paleta.enLinea : Paleta.alerta,
                etiquetaEstado:
                    totalHuecos == 0 ? 'Sin perdidas' : 'Posibles perdidas',
                detalle: 'Huecos > 1.8x el nominal',
              ),
              TarjetaKpi(
                titulo: 'Ventana por nodo',
                valor: '${Ajustes.maxIntervalosPorNodo}',
                unidad: 'huecos',
                icono: Icons.straighten,
                detalle: 'Lo que abarca cada grafico',
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Seccion(
          titulo: 'Comparativa',
          descripcion: 'Misma informacion que los graficos, en numeros exactos.',
          hijo: Panel(
            relleno: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            hijo: _TablaComparativa(filas: conMetricas),
          ),
        ),
        const SizedBox(height: 28),
        for (final (nodo, metricas) in conMetricas) ...[
          _PanelNodo(nodo: nodo, metricas: metricas),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

/// Detalle de un nodo: sus cifras y el histograma de huecos.
class _PanelNodo extends StatelessWidget {
  const _PanelNodo({required this.nodo, required this.metricas});

  final Nodo nodo;
  final MetricasNodo metricas;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = Paleta.deNodo(nodo);

    return Panel(
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: 8),
              Text(
                nodo.id,
                style: tema.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              Text(
                Paleta.etiquetaDeNodo(nodo),
                style: tema.textTheme.bodySmall
                    ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                'Ultimo mensaje ${Formato.hace(metricas.ultimaLlegada)}',
                style: tema.textTheme.bodySmall
                    ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RejillaKpi(
            anchoMinimo: 140,
            tarjetas: [
              TarjetaResumenSimple(
                titulo: 'Ultimo hueco',
                valor: Formato.duracion(metricas.ultimo),
              ),
              TarjetaResumenSimple(
                titulo: 'Media',
                valor: Formato.duracion(metricas.promedio),
                detalle: metricas.desvioNominal == null
                    ? null
                    : '${Formato.desvio(metricas.desvioNominal)} vs nominal',
              ),
              TarjetaResumenSimple(
                titulo: 'Jitter',
                valor: Formato.duracion(metricas.jitter),
                detalle: 'Desviacion media',
              ),
              TarjetaResumenSimple(
                titulo: 'Percentil 95',
                valor: Formato.duracion(metricas.p95),
              ),
              TarjetaResumenSimple(
                titulo: 'Maximo',
                valor: Formato.duracion(metricas.maximo),
              ),
              TarjetaResumenSimple(
                titulo: 'Mensajes',
                valor: Formato.entero(metricas.mensajes),
                detalle: metricas.mensajesPorMinuto == null
                    ? null
                    : '${metricas.mensajesPorMinuto!.toStringAsFixed(1)}/min',
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 150,
            child: GraficoIntervalos(
              intervalos: metricas.intervalos,
              nominal: Ajustes.intervaloNominalNodo,
            ),
          ),
          const SizedBox(height: 10),
          _LeyendaHuecos(huecos: metricas.huecos),
        ],
      ),
    );
  }
}

/// Explica el codigo de color del grafico de barras sin depender del color.
class _LeyendaHuecos extends StatelessWidget {
  const _LeyendaHuecos({required this.huecos});

  final int huecos;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    Widget entrada(Color color, String texto) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              texto,
              style: tema.textTheme.bodySmall
                  ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            ),
          ],
        );

    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        entrada(tema.colorScheme.primary, 'Hueco normal'),
        entrada(Paleta.alerta, 'Hueco > 1.8x nominal ($huecos)'),
      ],
    );
  }
}

class _TablaComparativa extends StatelessWidget {
  const _TablaComparativa({required this.filas});

  final List<(Nodo, MetricasNodo)> filas;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 42,
        columnSpacing: 22,
        columns: const [
          DataColumn(label: Text('Nodo')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Media')),
          DataColumn(label: Text('Jitter')),
          DataColumn(label: Text('p95')),
          DataColumn(label: Text('Maximo')),
          DataColumn(label: Text('Huecos')),
          DataColumn(label: Text('Mensajes')),
          DataColumn(label: Text('Ultimo')),
        ],
        rows: [
          for (final (nodo, metricas) in filas)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    nodo.id,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 9, color: Paleta.deNodo(nodo)),
                      const SizedBox(width: 6),
                      Text(
                        Paleta.etiquetaDeNodo(nodo),
                        style: tema.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                DataCell(_numero(Formato.duracion(metricas.promedio))),
                DataCell(_numero(Formato.duracion(metricas.jitter))),
                DataCell(_numero(Formato.duracion(metricas.p95))),
                DataCell(_numero(Formato.duracion(metricas.maximo))),
                DataCell(_numero('${metricas.huecos}')),
                DataCell(_numero(Formato.entero(metricas.mensajes))),
                DataCell(
                  Text(
                    Formato.hace(metricas.ultimaLlegada),
                    style: tema.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Widget _numero(String texto) => Text(
        texto,
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      );
}
