import 'package:flutter/material.dart';

import '../../estado/monitor_controlador.dart';
import '../../modelos/nodo.dart';
import '../../widgets/panel_detalle.dart';
import '../../widgets/tarjeta_nodo.dart';
import 'vista_resumen.dart' show SinNodos;

/// Monitorizacion en vivo de un nodo concreto.
///
/// En pantallas anchas los nodos van en una columna fija a la izquierda del
/// contenido; en movil pasan a una tira horizontal sobre el detalle. Es el
/// mismo arbol de widgets: solo cambia la disposicion.
class VistaNodos extends StatelessWidget {
  const VistaNodos({required this.controlador, super.key});

  final MonitorControlador controlador;

  /// A partir de este ancho cabe la lista de nodos junto al detalle.
  static const double _anchoDosPaneles = 900;

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

    final seleccionado = controlador.seleccionado!;
    final detalle = PanelDetalle(
      nodo: seleccionado,
      lecturasVisibles: controlador.lecturasVisibles(seleccionado),
      ventana: controlador.ventana,
      onCambiarVentana: controlador.cambiarVentana,
      metricas: controlador.metricasDe(seleccionado.id),
    );

    return LayoutBuilder(
      builder: (context, restricciones) {
        final esAncho = restricciones.maxWidth >= _anchoDosPaneles;
        return esAncho
            ? _DisposicionAncha(
                nodos: controlador.nodos,
                seleccionado: seleccionado,
                onSeleccionar: controlador.seleccionar,
                detalle: detalle,
              )
            : _DisposicionEstrecha(
                nodos: controlador.nodos,
                seleccionado: seleccionado,
                onSeleccionar: controlador.seleccionar,
                detalle: detalle,
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
    required this.detalle,
  });

  final List<Nodo> nodos;
  final Nodo seleccionado;
  final ValueChanged<String> onSeleccionar;
  final Widget detalle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 268,
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
        Expanded(child: detalle),
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
    required this.detalle,
  });

  final List<Nodo> nodos;
  final Nodo seleccionado;
  final ValueChanged<String> onSeleccionar;
  final Widget detalle;

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
        Expanded(child: detalle),
      ],
    );
  }
}
