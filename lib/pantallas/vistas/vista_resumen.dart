import 'package:flutter/material.dart';

import '../../config/ajustes.dart';
import '../../config/paleta.dart';
import '../../estado/monitor_controlador.dart';
import '../../servicios/mqtt/mqtt_servicio.dart';
import '../../util/formato.dart';
import '../../widgets/grafico_latencia.dart';
import '../../widgets/leyenda_series.dart';
import '../../widgets/seccion.dart';
import '../../widgets/tarjeta_kpi.dart';
import '../../widgets/tarjeta_nodo.dart';

/// Vista de entrada: el estado de todo el sistema en una pantalla.
///
/// Los nodos se muestran como multiplos pequeños -una tarjeta con su propia
/// mini grafica por nodo- en lugar de una grafica unica con N series. Con
/// nodos que entran y salen solos, una serie por nodo obligaria a inventar
/// colores nuevos sobre la marcha y a repintar los supervivientes cuando uno
/// se cae; la rejilla escala sin ese problema.
class VistaResumen extends StatelessWidget {
  const VistaResumen({
    required this.controlador,
    required this.onAbrirNodo,
    super.key,
  });

  final MonitorControlador controlador;
  final ValueChanged<String> onAbrirNodo;

  @override
  Widget build(BuildContext context) {
    if (controlador.cargandoHistorial && controlador.sinDatos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controlador.sinDatos) {
      return SinNodos(
        urlBroker: controlador.urlBroker,
        urlApi: controlador.urlApi,
        conexion: controlador.conexion,
      );
    }

    final masCaliente = controlador.lecturaMasCaliente;
    final latenciaApi = controlador.latenciaApi;
    final latenciaBroker = controlador.latenciaBroker;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        RejillaKpi(
          tarjetas: [
            TarjetaKpi(
              titulo: 'Nodos activos',
              valor: '${controlador.nodosActivos}',
              unidad: 'de ${controlador.nodosTotales}',
              icono: Icons.developer_board,
              detalle: controlador.nodosCaidos > 0
                  ? '${controlador.nodosCaidos} marcados como caidos'
                  : 'Ninguno caido',
            ),
            TarjetaKpi(
              titulo: 'Temperatura media',
              valor: Formato.grados(controlador.temperaturaMediaGlobal),
              icono: Icons.thermostat,
              detalle: 'Media de los nodos activos',
            ),
            TarjetaKpi(
              titulo: 'Pico actual',
              valor: masCaliente == null
                  ? '--'
                  : Formato.grados(
                      masCaliente.sensor1 > masCaliente.sensor2
                          ? masCaliente.sensor1
                          : masCaliente.sensor2,
                    ),
              icono: Icons.local_fire_department_outlined,
              detalle: masCaliente?.dispositivo ?? 'Sin nodos activos',
            ),
            TarjetaKpi(
              titulo: 'Lecturas en vivo',
              valor: Formato.entero(controlador.lecturasEnVivo),
              icono: Icons.bolt_outlined,
              detalle: 'En ${Formato.duracion(controlador.tiempoEnMarcha)} '
                  'de sesion',
            ),
            TarjetaKpi(
              titulo: 'Latencia API',
              valor: Formato.milisegundos(latenciaApi.ultimaMs),
              icono: Icons.cloud_outlined,
              colorEstado: Paleta.deLatencia(latenciaApi.ultimaMs),
              etiquetaEstado: Paleta.etiquetaDeLatencia(latenciaApi.ultimaMs),
              detalle: 'Media ${Formato.milisegundos(latenciaApi.promedioMs)}',
            ),
            TarjetaKpi(
              titulo: 'RTT broker',
              valor: Formato.milisegundos(latenciaBroker.ultimaMs),
              icono: Icons.swap_horiz,
              colorEstado: Paleta.deLatencia(latenciaBroker.ultimaMs),
              etiquetaEstado: Paleta.etiquetaDeLatencia(latenciaBroker.ultimaMs),
              detalle: 'Media ${Formato.milisegundos(latenciaBroker.promedioMs)}',
            ),
          ],
        ),
        const SizedBox(height: 28),
        Seccion(
          titulo: 'Nodos',
          descripcion:
              'Una tarjeta por nodo con su tendencia; toca una para abrir su detalle.',
          hijo: LayoutBuilder(
            builder: (context, restricciones) {
              const anchoTarjeta = 230.0;
              const separacion = 12.0;
              final columnas = (restricciones.maxWidth /
                      (anchoTarjeta + separacion))
                  .floor()
                  .clamp(1, 6);
              final ancho = (restricciones.maxWidth -
                      separacion * (columnas - 1)) /
                  columnas;

              return Wrap(
                spacing: separacion,
                runSpacing: separacion,
                children: [
                  for (final nodo in controlador.nodos)
                    SizedBox(
                      width: ancho,
                      child: TarjetaNodo(
                        nodo: nodo,
                        seleccionado: false,
                        onSeleccionar: () => onAbrirNodo(nodo.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 28),
        Seccion(
          titulo: 'Salud del enlace',
          descripcion:
              'Tiempos de ida y vuelta medidos cada ${Ajustes.intervaloSondeo.inSeconds} s '
              'desde esta app.',
          hijo: Panel(
            hijo: Column(
              children: [
                SizedBox(
                  height: 170,
                  child: GraficoLatencia(
                    trazos: [
                      TrazoLatencia(
                        nombre: latenciaApi.nombre,
                        color: Paleta.latenciaApi,
                        muestras: latenciaApi.muestras,
                      ),
                      TrazoLatencia(
                        nombre: latenciaBroker.nombre,
                        color: Paleta.latenciaBroker,
                        muestras: latenciaBroker.muestras,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LeyendaSeries(
                  entradas: [
                    EntradaLeyenda(
                      nombre: latenciaApi.nombre,
                      color: Paleta.latenciaApi,
                      valor: Formato.milisegundos(latenciaApi.ultimaMs),
                    ),
                    EntradaLeyenda(
                      nombre: latenciaBroker.nombre,
                      color: Paleta.latenciaBroker,
                      valor: Formato.milisegundos(latenciaBroker.ultimaMs),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Estado vacio: explica que revisar en lugar de dejar la pantalla en blanco.
class SinNodos extends StatelessWidget {
  const SinNodos({
    required this.urlBroker,
    required this.urlApi,
    required this.conexion,
    super.key,
  });

  final String urlBroker;
  final String urlApi;
  final EstadoConexion conexion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final falloBroker = conexion != EstadoConexion.conectado;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                falloBroker ? Icons.cloud_off : Icons.sensors_off,
                size: 54,
                color: tema.colorScheme.outline,
              ),
              const SizedBox(height: 18),
              Text(
                falloBroker
                    ? 'No se pudo conectar al broker'
                    : 'Conectado, pero ningun nodo publica aun',
                style: tema.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                falloBroker
                    ? 'Revisa que la pila este levantada:\n'
                        'cd infra && docker compose up -d'
                    : 'Enciende un ESP32 con el sketch cargado, o lanza el\n'
                        'simulador:\n'
                        'python infra/servicios/herramientas/simulador_nodos.py',
                style: tema.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'MQTT  $urlBroker\nAPI   $urlApi',
                style: tema.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: tema.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
