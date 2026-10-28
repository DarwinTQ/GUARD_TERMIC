import 'package:flutter/material.dart';

import '../../config/ajustes.dart';
import '../../config/paleta.dart';
import '../../estado/monitor_controlador.dart';
import '../../modelos/metricas.dart';
import '../../util/formato.dart';
import '../../widgets/grafico_latencia.dart';
import '../../widgets/leyenda_series.dart';
import '../../widgets/panel_detalle.dart' show TarjetaResumenSimple;
import '../../widgets/seccion.dart';
import '../../widgets/tarjeta_kpi.dart';

/// Cuanto tarda en responder cada pieza del sistema.
///
/// Mide dos caminos distintos que la app usa de verdad:
///   * API REST: un GET a `/`, que toca FastAPI y hace ping a Mongo.
///   * Broker MQTT: un mensaje publicado en el topico de sonda y cronometrado
///     hasta que Mosquitto lo devuelve por el mismo WebSocket.
///
/// Son medidas de extremo a extremo tomadas desde el cliente, no metricas del
/// servidor: incluyen la red, que es donde suelen estar los problemas.
class VistaTiemposRespuesta extends StatelessWidget {
  const VistaTiemposRespuesta({required this.controlador, super.key});

  final MonitorControlador controlador;

  @override
  Widget build(BuildContext context) {
    final api = controlador.latenciaApi;
    final broker = controlador.latenciaBroker;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Seccion(
          titulo: 'Estado actual',
          descripcion: 'Sonda cada ${Ajustes.intervaloSondeo.inSeconds} s; '
              'se conservan las ultimas ${Ajustes.maxMuestrasLatencia} muestras '
              'de cada camino.',
          hijo: RejillaKpi(
            tarjetas: [
              _kpiDe(api, Icons.cloud_outlined, controlador.urlApi),
              _kpiDe(broker, Icons.swap_horiz, controlador.urlBroker),
              TarjetaKpi(
                titulo: 'Disponibilidad API',
                valor: Formato.porcentaje(api.disponibilidad),
                icono: Icons.verified_outlined,
                detalle: '${api.fallos} fallos de ${api.total} sondas',
              ),
              TarjetaKpi(
                titulo: 'Disponibilidad broker',
                valor: Formato.porcentaje(broker.disponibilidad),
                icono: Icons.verified_outlined,
                detalle: '${broker.fallos} fallos de ${broker.total} sondas',
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Seccion(
          titulo: 'Evolucion',
          descripcion:
              'Las sondas sin respuesta dejan hueco en la linea en lugar de '
              'interpolarse: un fallo no es una latencia baja.',
          hijo: Panel(
            hijo: Column(
              children: [
                SizedBox(
                  height: 240,
                  child: GraficoLatencia(
                    trazos: [
                      TrazoLatencia(
                        nombre: api.nombre,
                        color: Paleta.latenciaApi,
                        muestras: api.muestras,
                      ),
                      TrazoLatencia(
                        nombre: broker.nombre,
                        color: Paleta.latenciaBroker,
                        muestras: broker.muestras,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LeyendaSeries(
                  entradas: [
                    EntradaLeyenda(
                      nombre: api.nombre,
                      color: Paleta.latenciaApi,
                      valor: Formato.milisegundos(api.ultimaMs),
                    ),
                    EntradaLeyenda(
                      nombre: broker.nombre,
                      color: Paleta.latenciaBroker,
                      valor: Formato.milisegundos(broker.ultimaMs),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Seccion(
          titulo: 'Distribucion',
          descripcion:
              'El percentil 95 dice que sufre 1 de cada 20 peticiones; la media '
              'sola esconde justo los picos que se notan al usar la app.',
          hijo: Column(
            children: [
              _FilaEstadisticos(serie: api, color: Paleta.latenciaApi),
              const SizedBox(height: 12),
              _FilaEstadisticos(serie: broker, color: Paleta.latenciaBroker),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Seccion(
          titulo: 'Ultimas sondas',
          descripcion: 'Las 12 mediciones mas recientes de cada camino.',
          hijo: Panel(
            relleno: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            hijo: _TablaSondas(api: api, broker: broker),
          ),
        ),
      ],
    );
  }

  TarjetaKpi _kpiDe(SerieLatencia serie, IconData icono, String destino) {
    return TarjetaKpi(
      titulo: serie.nombre,
      valor: Formato.milisegundos(serie.ultimaMs),
      icono: icono,
      colorEstado: Paleta.deLatencia(serie.ultimaMs),
      etiquetaEstado: Paleta.etiquetaDeLatencia(serie.ultimaMs),
      detalle: destino,
    );
  }
}

/// Minimo / media / p95 / maximo de una serie, en una fila etiquetada.
class _FilaEstadisticos extends StatelessWidget {
  const _FilaEstadisticos({required this.serie, required this.color});

  final SerieLatencia serie;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Panel(
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 3,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                serie.nombre,
                style: tema.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${serie.total} muestras',
                style: tema.textTheme.bodySmall
                    ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          RejillaKpi(
            anchoMinimo: 130,
            tarjetas: [
              TarjetaResumenSimple(
                titulo: 'Minimo',
                valor: Formato.milisegundos(serie.minimoMs),
              ),
              TarjetaResumenSimple(
                titulo: 'Media',
                valor: Formato.milisegundos(serie.promedioMs),
              ),
              TarjetaResumenSimple(
                titulo: 'Percentil 95',
                valor: Formato.milisegundos(serie.p95Ms),
              ),
              TarjetaResumenSimple(
                titulo: 'Maximo',
                valor: Formato.milisegundos(serie.maximoMs),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Vista tabular de las mediciones: misma informacion que el grafico, para
/// quien necesite el numero exacto o no pueda distinguir las dos lineas.
class _TablaSondas extends StatelessWidget {
  const _TablaSondas({required this.api, required this.broker});

  final SerieLatencia api;
  final SerieLatencia broker;

  static const int _filas = 12;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final muestrasApi = api.muestras.reversed.take(_filas).toList();
    final muestrasBroker = broker.muestras.reversed.take(_filas).toList();

    if (muestrasApi.isEmpty && muestrasBroker.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Todavia no hay mediciones.',
          style: tema.textTheme.bodySmall,
        ),
      );
    }

    final total = muestrasApi.length > muestrasBroker.length
        ? muestrasApi.length
        : muestrasBroker.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 40,
        columnSpacing: 26,
        columns: const [
          DataColumn(label: Text('Hora')),
          DataColumn(label: Text('API REST')),
          DataColumn(label: Text('Broker MQTT')),
        ],
        rows: [
          for (var i = 0; i < total; i++)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    i < muestrasApi.length
                        ? Formato.hora(muestrasApi[i].instante)
                        : Formato.hora(muestrasBroker[i].instante),
                    style: tema.textTheme.bodySmall,
                  ),
                ),
                DataCell(_celda(context, i < muestrasApi.length ? muestrasApi[i] : null)),
                DataCell(_celda(
                    context, i < muestrasBroker.length ? muestrasBroker[i] : null)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _celda(BuildContext context, MuestraLatencia? muestra) {
    if (muestra == null) return const Text('--');
    if (!muestra.ok) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 14, color: Paleta.desconectado),
          const SizedBox(width: 6),
          Text(
            muestra.detalle ?? 'Fallo',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    return Text(
      Formato.milisegundos(muestra.milisegundos),
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}
