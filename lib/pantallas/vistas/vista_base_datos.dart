import 'package:flutter/material.dart';

import '../../config/ajustes.dart';
import '../../config/paleta.dart';
import '../../estado/explorador_bd.dart';
import '../../modelos/estadistica_nodo.dart';
import '../../modelos/resumen_bd.dart';
import '../../util/formato.dart';
import '../../widgets/panel_detalle.dart' show TarjetaResumenSimple;
import '../../widgets/seccion.dart';
import '../../widgets/tarjeta_kpi.dart';

/// Lo que hay realmente guardado en MongoDB.
///
/// Es la contraparte del resto del dashboard: todas las demas vistas miran
/// la ventana en memoria -120 puntos por nodo- mientras que esta consulta la
/// serie completa. Por eso los minimos y maximos de aqui no tienen por que
/// coincidir con los de la vista de nodos, y esta bien que no coincidan.
///
/// Se carga bajo demanda y no se refresca sola: una consulta a Mongo cada
/// segundo no aportaria nada y si cargaria la base.
class VistaBaseDatos extends StatelessWidget {
  const VistaBaseDatos({required this.explorador, super.key});

  final ExploradorBd explorador;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: explorador,
      builder: (context, _) {
        if (explorador.cargando && explorador.resumen == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (explorador.error != null && explorador.resumen == null) {
          return _Error(
            mensaje: explorador.error!,
            onReintentar: explorador.cargar,
          );
        }

        final resumen = explorador.resumen;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (explorador.error != null) ...[
              _BandaError(mensaje: explorador.error!),
              const SizedBox(height: 16),
            ],
            Seccion(
              titulo: 'Base de datos',
              descripcion: resumen == null
                  ? null
                  : 'MongoDB ${resumen.servidor ?? ''} · base "${resumen.baseDatos}"'
                      '${explorador.consultadoEn == null ? '' : ' · consultado ${Formato.hora(explorador.consultadoEn!)}'}',
              acciones: [
                if (explorador.cargando)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                TextButton.icon(
                  onPressed: explorador.cargando ? null : explorador.cargar,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Recargar'),
                ),
              ],
              hijo: RejillaKpi(
                tarjetas: [
                  TarjetaKpi(
                    titulo: 'Lecturas almacenadas',
                    valor: Formato.entero(
                      _documentosDe(resumen, 'lecturas'),
                    ),
                    icono: Icons.dataset_outlined,
                    detalle: 'Coleccion lecturas',
                  ),
                  TarjetaKpi(
                    titulo: 'Dispositivos',
                    valor: Formato.entero(
                      _documentosDe(resumen, 'dispositivos'),
                    ),
                    icono: Icons.developer_board,
                    detalle: 'Coleccion dispositivos',
                  ),
                  TarjetaKpi(
                    titulo: 'Tamaño en disco',
                    valor: Formato.bytes(resumen?.totalBytes),
                    icono: Icons.save_outlined,
                    detalle: 'Datos, sin contar indices',
                  ),
                  TarjetaKpi(
                    titulo: 'Filtro actual',
                    valor: Formato.entero(explorador.total),
                    unidad: 'filas',
                    icono: Icons.filter_alt_outlined,
                    detalle: explorador.dispositivo ?? 'Todos los nodos',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            if (resumen != null) ...[
              Seccion(
                titulo: 'Colecciones e indices',
                descripcion:
                    'Los indices son los que hacen que el historial y el filtro '
                    'por nodo no recorran toda la coleccion.',
                hijo: Column(
                  children: [
                    for (final coleccion in resumen.colecciones) ...[
                      _PanelColeccion(coleccion: coleccion),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Seccion(
              titulo: 'Agregados por nodo',
              descripcion:
                  'Calculados por Mongo sobre la serie completa, no sobre la '
                  'ventana que muestra el dashboard.',
              hijo: Panel(
                relleno: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                hijo: _TablaEstadisticas(filas: explorador.estadisticas),
              ),
            ),
            const SizedBox(height: 28),
            Seccion(
              titulo: 'Lecturas crudas',
              descripcion:
                  'La coleccion tal cual, mas reciente primero, en paginas de '
                  '${Ajustes.filasPorPagina}.',
              acciones: [
                _FiltroNodo(explorador: explorador),
              ],
              hijo: Column(
                children: [
                  Panel(
                    relleno:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    hijo: _TablaLecturas(explorador: explorador),
                  ),
                  const SizedBox(height: 12),
                  _Paginacion(explorador: explorador),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static int _documentosDe(ResumenBd? resumen, String nombre) {
    if (resumen == null) return 0;
    for (final coleccion in resumen.colecciones) {
      if (coleccion.nombre == nombre) return coleccion.documentos;
    }
    return 0;
  }
}

class _PanelColeccion extends StatelessWidget {
  const _PanelColeccion({required this.coleccion});

  final ColeccionBd coleccion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Panel(
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.table_chart_outlined,
                  size: 18, color: tema.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                coleccion.nombre,
                style: tema.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          RejillaKpi(
            anchoMinimo: 140,
            tarjetas: [
              TarjetaResumenSimple(
                titulo: 'Documentos',
                valor: Formato.entero(coleccion.documentos),
              ),
              TarjetaResumenSimple(
                titulo: 'Datos',
                valor: Formato.bytes(coleccion.bytes),
              ),
              TarjetaResumenSimple(
                titulo: 'Indices',
                valor: Formato.bytes(coleccion.bytesIndices),
                detalle: '${coleccion.indices.length} definidos',
              ),
              TarjetaResumenSimple(
                titulo: 'Por documento',
                valor: coleccion.bytesPorDocumento == null
                    ? 'n/d'
                    : Formato.bytes(coleccion.bytesPorDocumento!.round()),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final indice in coleccion.indices)
                Tooltip(
                  message: indice.descripcion,
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.key_outlined, size: 14),
                    label: Text(
                      indice.nombre,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TablaEstadisticas extends StatelessWidget {
  const _TablaEstadisticas({required this.filas});

  final List<EstadisticaNodo> filas;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    if (filas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Sin datos agregados.', style: tema.textTheme.bodySmall),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 42,
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text('Nodo')),
          DataColumn(label: Text('Lecturas')),
          DataColumn(label: Text('S1 min')),
          DataColumn(label: Text('S1 med')),
          DataColumn(label: Text('S1 max')),
          DataColumn(label: Text('S2 min')),
          DataColumn(label: Text('S2 med')),
          DataColumn(label: Text('S2 max')),
          DataColumn(label: Text('Cadencia')),
          DataColumn(label: Text('Cobertura')),
          DataColumn(label: Text('Ultima')),
        ],
        rows: [
          for (final fila in filas)
            DataRow(
              cells: [
                DataCell(Text(
                  fila.dispositivo,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )),
                DataCell(_num(Formato.entero(fila.lecturas))),
                DataCell(_num(Formato.grados(fila.sensor1.minimo))),
                DataCell(_num(Formato.grados(fila.sensor1.promedio))),
                DataCell(_num(Formato.grados(fila.sensor1.maximo))),
                DataCell(_num(Formato.grados(fila.sensor2.minimo))),
                DataCell(_num(Formato.grados(fila.sensor2.promedio))),
                DataCell(_num(Formato.grados(fila.sensor2.maximo))),
                DataCell(_num(Formato.duracion(fila.intervaloMedio))),
                DataCell(_num(Formato.duracion(fila.cobertura))),
                DataCell(Text(
                  fila.ultima == null ? '--' : Formato.fechaHora(fila.ultima!),
                  style: tema.textTheme.bodySmall,
                )),
              ],
            ),
        ],
      ),
    );
  }

  static Widget _num(String texto) => Text(
        texto,
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      );
}

class _TablaLecturas extends StatelessWidget {
  const _TablaLecturas({required this.explorador});

  final ExploradorBd explorador;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final lecturas = explorador.lecturas;

    if (lecturas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          explorador.cargando
              ? 'Consultando...'
              : 'No hay lecturas para este filtro.',
          style: tema.textTheme.bodySmall,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 38,
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('Fecha (servidor)')),
          DataColumn(label: Text('Dispositivo')),
          DataColumn(label: Text('Sensor 1')),
          DataColumn(label: Text('Sensor 2')),
          DataColumn(label: Text('RSSI')),
          DataColumn(label: Text('_id')),
        ],
        rows: [
          for (final lectura in lecturas)
            DataRow(
              cells: [
                DataCell(Text(
                  Formato.fechaCompleta(lectura.fecha),
                  style: tema.textTheme.bodySmall,
                )),
                DataCell(Text(lectura.dispositivo)),
                DataCell(_celdaTemperatura(lectura.sensor1, Paleta.sensor1)),
                DataCell(_celdaTemperatura(lectura.sensor2, Paleta.sensor2)),
                DataCell(Text(
                  lectura.rssi == null ? '--' : '${lectura.rssi} dBm',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                )),
                DataCell(Text(
                  lectura.id ?? '--',
                  style: tema.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                )),
              ],
            ),
        ],
      ),
    );
  }

  /// Marca de color pequeña junto al numero: identifica el sensor sin teñir
  /// el texto, que debe seguir leyendose como texto.
  static Widget _celdaTemperatura(double valor, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            Formato.grados(valor),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class _FiltroNodo extends StatelessWidget {
  const _FiltroNodo({required this.explorador});

  final ExploradorBd explorador;

  @override
  Widget build(BuildContext context) {
    final nodos = explorador.dispositivosConocidos;

    return DropdownMenu<String?>(
      initialSelection: explorador.dispositivo,
      enabled: !explorador.cargando,
      label: const Text('Nodo'),
      width: 220,
      textStyle: Theme.of(context).textTheme.bodySmall,
      onSelected: explorador.filtrarPor,
      dropdownMenuEntries: [
        const DropdownMenuEntry<String?>(value: null, label: 'Todos'),
        for (final nodo in nodos)
          DropdownMenuEntry<String?>(value: nodo, label: nodo),
      ],
    );
  }
}

class _Paginacion extends StatelessWidget {
  const _Paginacion({required this.explorador});

  final ExploradorBd explorador;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          explorador.total == 0
              ? 'Sin filas'
              : '${Formato.entero(explorador.primeraFila)}'
                  '-${Formato.entero(explorador.ultimaFila)} '
                  'de ${Formato.entero(explorador.total)}',
          style: tema.textTheme.bodySmall
              ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'Pagina anterior',
          onPressed: explorador.hayAnterior && !explorador.cargando
              ? explorador.paginaAnterior
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '${explorador.pagina + 1} / ${explorador.paginas}',
          style: tema.textTheme.bodySmall,
        ),
        IconButton(
          tooltip: 'Pagina siguiente',
          onPressed: explorador.haySiguiente && !explorador.cargando
              ? explorador.paginaSiguiente
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _BandaError extends StatelessWidget {
  const _BandaError({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tema.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: 18, color: tema.colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: tema.textTheme.bodySmall
                  ?.copyWith(color: tema.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storage, size: 50, color: tema.colorScheme.outline),
            const SizedBox(height: 16),
            Text('No se pudo consultar la base de datos',
                style: tema.textTheme.titleMedium),
            const SizedBox(height: 10),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text(
              'El tiempo real sigue funcionando: va directo al broker y no '
              'pasa por la API.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall
                  ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
