import 'package:flutter/material.dart';

import '../estado/monitor_controlador.dart';
import '../modelos/nodo.dart';
import '../servicios/mqtt/mqtt_servicio.dart';
import '../widgets/barra_conexion.dart';
import '../widgets/panel_detalle.dart';
import '../widgets/tarjeta_nodo.dart';

/// Pantalla unica del dashboard, adaptada a los tres formatos de destino.
///
/// En pantallas anchas (desktop y web) los nodos van en una columna lateral
/// fija; en movil pasan a una tira horizontal sobre el detalle. Es el mismo
/// arbol de widgets: solo cambia la disposicion.
class PantallaMonitor extends StatefulWidget {
  const PantallaMonitor({super.key});

  @override
  State<PantallaMonitor> createState() => _PantallaMonitorState();
}

class _PantallaMonitorState extends State<PantallaMonitor> {
  late final MonitorControlador _controlador;

  /// A partir de este ancho se usa el diseño de dos paneles.
  static const double _anchoEscritorio = 900;

  @override
  void initState() {
    super.initState();
    _controlador = MonitorControlador();
    _controlador.iniciar();
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controlador,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('TermicGuard'),
            actions: [
              BarraConexion(
                estado: _controlador.conexion,
                url: _controlador.urlBroker,
                nodosActivos: _controlador.nodosActivos,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Recargar historial',
                icon: const Icon(Icons.refresh),
                onPressed: _controlador.refrescar,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(
            children: [
              if (_controlador.avisoHistorial != null)
                _Aviso(mensaje: _controlador.avisoHistorial!),
              Expanded(child: _cuerpo()),
            ],
          ),
        );
      },
    );
  }

  Widget _cuerpo() {
    if (_controlador.cargandoHistorial && _controlador.sinDatos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controlador.sinDatos) {
      return _SinNodos(
        urlBroker: _controlador.urlBroker,
        urlApi: _controlador.urlApi,
        conexion: _controlador.conexion,
      );
    }

    final seleccionado = _controlador.seleccionado!;
    return LayoutBuilder(
      builder: (context, restricciones) {
        final esAncho = restricciones.maxWidth >= _anchoEscritorio;
        return esAncho
            ? _DisposicionAncha(
                nodos: _controlador.nodos,
                seleccionado: seleccionado,
                onSeleccionar: _controlador.seleccionar,
              )
            : _DisposicionEstrecha(
                nodos: _controlador.nodos,
                seleccionado: seleccionado,
                onSeleccionar: _controlador.seleccionar,
              );
      },
    );
  }
}

/// Desktop y web: lista lateral + detalle.
class _DisposicionAncha extends StatelessWidget {
  const _DisposicionAncha({
    required this.nodos,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  final List<Nodo> nodos;
  final Nodo seleccionado;
  final ValueChanged<String> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 290,
          child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: nodos.length,
            itemBuilder: (context, indice) {
              final nodo = nodos[indice];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TarjetaNodo(
                  nodo: nodo,
                  seleccionado: nodo.id == seleccionado.id,
                  onSeleccionar: () => onSeleccionar(nodo.id),
                ),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: PanelDetalle(nodo: seleccionado)),
      ],
    );
  }
}

/// Movil: tira horizontal de nodos + detalle debajo.
class _DisposicionEstrecha extends StatelessWidget {
  const _DisposicionEstrecha({
    required this.nodos,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  final List<Nodo> nodos;
  final Nodo seleccionado;
  final ValueChanged<String> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 182,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: nodos.length,
            itemBuilder: (context, indice) {
              final nodo = nodos[indice];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 190,
                  child: TarjetaNodo(
                    nodo: nodo,
                    seleccionado: nodo.id == seleccionado.id,
                    onSeleccionar: () => onSeleccionar(nodo.id),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(child: PanelDetalle(nodo: seleccionado)),
      ],
    );
  }
}

/// Banda de aviso no bloqueante (por ejemplo, API caida pero MQTT vivo).
class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.errorContainer;
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(mensaje, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// Estado vacio: explica que revisar en lugar de dejar la pantalla en blanco.
class _SinNodos extends StatelessWidget {
  const _SinNodos({
    required this.urlBroker,
    required this.urlApi,
    required this.conexion,
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
