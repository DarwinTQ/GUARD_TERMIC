import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/ajustes.dart';
import '../../config/paleta.dart';
import '../../estado/monitor_controlador.dart';
import '../../servicios/mqtt/mqtt_servicio.dart';
import '../../util/formato.dart';
import '../../widgets/seccion.dart';

/// Configuracion efectiva de esta compilacion y diagnostico rapido.
///
/// Muestra los valores que la app esta usando de verdad, no los del codigo
/// fuente: todos salen de `Ajustes`, que a su vez los lee de los
/// `--dart-define` del build. Cuando alguien dice "no conecta", esta es la
/// primera pantalla que hay que mirar.
class VistaSistema extends StatelessWidget {
  const VistaSistema({required this.controlador, super.key});

  final MonitorControlador controlador;

  @override
  Widget build(BuildContext context) {
    final (colorEnlace, textoEnlace) = switch (controlador.conexion) {
      EstadoConexion.conectado => (Paleta.enLinea, 'Conectado'),
      EstadoConexion.conectando => (Paleta.alerta, 'Conectando'),
      EstadoConexion.desconectado => (Paleta.inactivo, 'Desconectado'),
      EstadoConexion.error => (Paleta.desconectado, 'Inalcanzable'),
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Seccion(
          titulo: 'Conexiones',
          descripcion:
              'Se cambian al compilar con --dart-define, sin tocar el codigo.',
          hijo: Panel(
            hijo: Column(
              children: [
                _Fila(
                  clave: 'Host',
                  valor: Ajustes.host,
                  nota: 'TG_HOST',
                  copiable: true,
                ),
                _Fila(
                  clave: 'Broker MQTT (WebSocket)',
                  valor: controlador.urlBroker,
                  nota: 'TG_MQTT_WS = ${Ajustes.puertoMqtt}',
                  copiable: true,
                  estado: colorEnlace,
                  etiquetaEstado: textoEnlace,
                ),
                _Fila(
                  clave: 'API REST',
                  valor: controlador.urlApi,
                  nota: 'TG_API = ${Ajustes.puertoApi}',
                  copiable: true,
                  estado: controlador.avisoHistorial == null
                      ? Paleta.enLinea
                      : Paleta.desconectado,
                  etiquetaEstado: controlador.avisoHistorial == null
                      ? 'Responde'
                      : 'Sin respuesta',
                ),
                _Fila(
                  clave: 'Documentacion de la API',
                  valor: '${controlador.urlApi}/docs',
                  copiable: true,
                  ultima: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Seccion(
          titulo: 'Topicos MQTT',
          descripcion:
              'Los mismos strings estan en el firmware y en la ingesta: si se '
              'cambia uno, hay que cambiar los tres.',
          hijo: Panel(
            hijo: Column(
              children: [
                _Fila(
                  clave: 'Telemetria',
                  valor: Ajustes.topicoTelemetria,
                  nota: 'Suscripcion con comodin: un nodo nuevo aparece solo',
                ),
                _Fila(
                  clave: 'Estado (LWT)',
                  valor: Ajustes.topicoEstado,
                  nota: 'Retenido: online / offline',
                ),
                _Fila(
                  clave: 'Sonda de latencia',
                  valor: Ajustes.topicoSonda,
                  nota: 'Solo de esta app; la ingesta no lo escucha',
                  ultima: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Seccion(
          titulo: 'Parametros de la vista',
          hijo: Panel(
            hijo: Column(
              children: [
                _Fila(
                  clave: 'Historial inicial',
                  valor: '${Ajustes.limiteHistorial} lecturas',
                  nota: 'Lo que se pide a la API al abrir',
                ),
                _Fila(
                  clave: 'Ventana por nodo',
                  valor: '${Ajustes.maxPuntosPorNodo} puntos',
                  nota: 'Memoria acotada: las viejas se descartan',
                ),
                _Fila(
                  clave: 'Umbral sin senal',
                  valor: Formato.duracion(Ajustes.tiempoSinSenal),
                  nota: 'Sin lecturas durante este tiempo, el nodo es inactivo',
                ),
                _Fila(
                  clave: 'Refresco de la vista',
                  valor: Formato.duracion(Ajustes.refrescoVista),
                  nota: 'Hace avanzar el eje temporal de las graficas',
                ),
                _Fila(
                  clave: 'Sondeo de latencia',
                  valor: Formato.duracion(Ajustes.intervaloSondeo),
                  nota: 'Tiempo limite ${Formato.duracion(Ajustes.tiempoLimiteSonda)}',
                ),
                _Fila(
                  clave: 'Intervalo nominal del nodo',
                  valor: Formato.duracion(Ajustes.intervaloNominalNodo),
                  nota: 'Debe coincidir con INTERVALO_MS del firmware',
                  ultima: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Seccion(
          titulo: 'Sesion actual',
          hijo: Panel(
            hijo: Column(
              children: [
                _Fila(
                  clave: 'Tiempo en marcha',
                  valor: Formato.duracion(controlador.tiempoEnMarcha),
                ),
                _Fila(
                  clave: 'Lecturas recibidas en vivo',
                  valor: Formato.entero(controlador.lecturasEnVivo),
                ),
                _Fila(
                  clave: 'Puntos en memoria',
                  valor: Formato.entero(controlador.puntosEnMemoria),
                  nota: 'Sumando todas las series del dashboard',
                ),
                _Fila(
                  clave: 'Nodos',
                  valor: '${controlador.nodosActivos} activos de '
                      '${controlador.nodosTotales}',
                  nota: '${controlador.nodosCaidos} marcados como caidos',
                  ultima: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Seccion(
          titulo: 'Si algo no responde',
          descripcion: 'Comprobaciones en orden, de la mas probable a la menos.',
          hijo: Panel(hijo: _Diagnostico()),
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.clave,
    required this.valor,
    this.nota,
    this.copiable = false,
    this.estado,
    this.etiquetaEstado,
    this.ultima = false,
  });

  final String clave;
  final String valor;
  final String? nota;
  final bool copiable;
  final Color? estado;
  final String? etiquetaEstado;
  final bool ultima;

  /// Por debajo de este ancho la clave pasa encima del valor.
  ///
  /// Los valores de esta pantalla son URLs y topicos: en movil no caben al
  /// lado de su etiqueta sin partirse por la mitad.
  static const double _anchoDosColumnas = 560;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: ultima
          ? null
          : BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: tema.dividerColor.withValues(alpha: 0.5)),
              ),
            ),
      child: LayoutBuilder(
        builder: (context, restricciones) {
          final enColumna = restricciones.maxWidth < _anchoDosColumnas;
          final etiqueta = Text(clave, style: tema.textTheme.bodyMedium);

          if (enColumna) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                etiqueta,
                const SizedBox(height: 4),
                _valor(context),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 210, child: etiqueta),
              Expanded(child: _valor(context)),
            ],
          );
        },
      ),
    );
  }

  Widget _valor(BuildContext context) {
    final tema = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            SelectableText(
              valor,
              style: tema.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            if (estado != null && etiquetaEstado != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 9, color: estado),
                  const SizedBox(width: 5),
                  Text(etiquetaEstado!, style: tema.textTheme.bodySmall),
                ],
              ),
            if (copiable)
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                tooltip: 'Copiar',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: valor));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copiado: $valor'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
              ),
          ],
        ),
        if (nota != null)
          Text(
            nota!,
            style: tema.textTheme.bodySmall
                ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _Diagnostico extends StatelessWidget {
  const _Diagnostico();

  static const List<(String, String)> _pasos = [
    (
      'La pila esta levantada',
      'cd infra && docker compose ps  (deben salir 4 servicios)',
    ),
    (
      'El cortafuegos deja pasar',
      'Puertos 1883, 9001 y 8001 abiertos en el perfil de red actual',
    ),
    (
      'La IP sigue siendo la misma',
      'Si el router renovo el DHCP, recompila con --dart-define=TG_HOST=<ip>',
    ),
    (
      'Hay alguien publicando',
      'python infra/servicios/herramientas/simulador_nodos.py --nodos 3',
    ),
    (
      'La ingesta esta guardando',
      'docker compose logs -f ingesta',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _pasos.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: tema.colorScheme.secondaryContainer,
                child: Text(
                  '${i + 1}',
                  style: tema.textTheme.labelSmall?.copyWith(
                    color: tema.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_pasos[i].$1, style: tema.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    SelectableText(
                      _pasos[i].$2,
                      style: tema.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (i < _pasos.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}
