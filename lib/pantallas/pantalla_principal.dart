import 'package:flutter/material.dart';

import '../config/paleta.dart';
import '../estado/explorador_bd.dart';
import '../estado/monitor_controlador.dart';
import '../servicios/mqtt/mqtt_servicio.dart';
import '../widgets/barra_conexion.dart';
import 'vistas/vista_base_datos.dart';
import 'vistas/vista_nodos.dart';
import 'vistas/vista_resumen.dart';
import 'vistas/vista_sistema.dart';
import 'vistas/vista_tiempos_llegada.dart';
import 'vistas/vista_tiempos_respuesta.dart';

/// Las vistas que ofrece el menu lateral, en el orden en que se muestran.
///
/// El orden no es decorativo: va de lo general a lo concreto y de lo que
/// pasa ahora a lo que quedo guardado, que es el recorrido natural cuando
/// algo va mal (veo el resumen -> miro el nodo -> compruebo si es la red ->
/// confirmo en la base).
enum VistaApp {
  resumen(
    'Resumen',
    'Estado global de la planta',
    Icons.dashboard_outlined,
    Icons.dashboard,
    GrupoMenu.monitorizacion,
  ),
  nodos(
    'Nodos en vivo',
    'Temperaturas en tiempo real',
    Icons.developer_board_outlined,
    Icons.developer_board,
    GrupoMenu.monitorizacion,
  ),
  tiemposRespuesta(
    'Tiempos de respuesta',
    'Latencia de la API y del broker',
    Icons.speed_outlined,
    Icons.speed,
    GrupoMenu.rendimiento,
  ),
  tiemposLlegada(
    'Tiempos de llegada',
    'Cadencia real de cada nodo',
    Icons.schedule_outlined,
    Icons.schedule,
    GrupoMenu.rendimiento,
  ),
  baseDatos(
    'Base de datos',
    'Lo que hay persistido en MongoDB',
    Icons.storage_outlined,
    Icons.storage,
    GrupoMenu.datos,
  ),
  sistema(
    'Sistema',
    'Configuracion y diagnostico',
    Icons.tune_outlined,
    Icons.tune,
    GrupoMenu.datos,
  );

  const VistaApp(
    this.titulo,
    this.subtitulo,
    this.icono,
    this.iconoActivo,
    this.grupo,
  );

  final String titulo;
  final String subtitulo;
  final IconData icono;
  final IconData iconoActivo;
  final GrupoMenu grupo;
}

/// Secciones del menu lateral.
enum GrupoMenu {
  monitorizacion('Monitorizacion'),
  rendimiento('Rendimiento'),
  datos('Datos y sistema');

  const GrupoMenu(this.etiqueta);
  final String etiqueta;
}

/// Armazon de la aplicacion: menu lateral fijo + vista activa.
///
/// Los dos controladores viven aqui y no en cada vista, de modo que cambiar
/// de pestaña no reconecta el broker ni pierde el historial acumulado: las
/// vistas son solo distintas lecturas del mismo estado.
class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  late final MonitorControlador _controlador;
  late final ExploradorBd _explorador;

  VistaApp _vista = VistaApp.resumen;

  /// La vista de base de datos se consulta la primera vez que se abre, no al
  /// arrancar: si nadie la mira, no se le pide nada a Mongo.
  bool _bdCargada = false;

  /// A partir de este ancho cabe el menu lateral desplegado.
  static const double _anchoMenuFijo = 1000;

  /// Por debajo de esto el menu pasa a ser un cajon.
  static const double _anchoMenuCompacto = 760;

  static const double _anchoMenu = 238;

  @override
  void initState() {
    super.initState();
    _controlador = MonitorControlador();
    _explorador = ExploradorBd();
    _controlador.iniciar();
  }

  @override
  void dispose() {
    _controlador.dispose();
    _explorador.dispose();
    super.dispose();
  }

  void _irA(VistaApp vista) {
    setState(() => _vista = vista);
    if (vista == VistaApp.baseDatos && !_bdCargada) {
      _bdCargada = true;
      _explorador.cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final ancho = restricciones.maxWidth;
        final menuFijo = ancho >= _anchoMenuCompacto;
        final menuExtendido = ancho >= _anchoMenuFijo;

        return ListenableBuilder(
          listenable: _controlador,
          builder: (context, _) => Scaffold(
            appBar: _barraSuperior(context, menuFijo),
            drawer: menuFijo
                ? null
                : Drawer(
                    child: SafeArea(
                      child: _MenuLateral(
                        vista: _vista,
                        extendido: true,
                        conexion: _controlador.conexion,
                        nodosActivos: _controlador.nodosActivos,
                        nodosTotales: _controlador.nodosTotales,
                        onSeleccionar: (vista) {
                          Navigator.of(context).pop();
                          _irA(vista);
                        },
                      ),
                    ),
                  ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (menuFijo) ...[
                  SizedBox(
                    width: menuExtendido ? _anchoMenu : 72,
                    child: _MenuLateral(
                      vista: _vista,
                      extendido: menuExtendido,
                      conexion: _controlador.conexion,
                      nodosActivos: _controlador.nodosActivos,
                      nodosTotales: _controlador.nodosTotales,
                      onSeleccionar: _irA,
                    ),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                ],
                Expanded(
                  child: Column(
                    children: [
                      if (_controlador.avisoHistorial != null)
                        _Aviso(mensaje: _controlador.avisoHistorial!),
                      Expanded(child: _contenido()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _barraSuperior(BuildContext context, bool menuFijo) {
    final tema = Theme.of(context);
    return AppBar(
      titleSpacing: menuFijo ? 20 : 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_vista.titulo, style: tema.textTheme.titleMedium),
          Text(
            _vista.subtitulo,
            style: tema.textTheme.bodySmall?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        if (MediaQuery.sizeOf(context).width >= 520)
          BarraConexion(
            estado: _controlador.conexion,
            url: _controlador.urlBroker,
            nodosActivos: _controlador.nodosActivos,
          ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Recargar historial desde la API',
          icon: const Icon(Icons.refresh),
          onPressed: () {
            _controlador.refrescar();
            if (_vista == VistaApp.baseDatos) _explorador.cargar();
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _contenido() {
    return switch (_vista) {
      VistaApp.resumen => VistaResumen(
          controlador: _controlador,
          onAbrirNodo: (id) {
            _controlador.seleccionar(id);
            _irA(VistaApp.nodos);
          },
        ),
      VistaApp.nodos => VistaNodos(controlador: _controlador),
      VistaApp.tiemposRespuesta =>
        VistaTiemposRespuesta(controlador: _controlador),
      VistaApp.tiemposLlegada => VistaTiemposLlegada(controlador: _controlador),
      VistaApp.baseDatos => VistaBaseDatos(explorador: _explorador),
      VistaApp.sistema => VistaSistema(controlador: _controlador),
    };
  }
}

/// Barra de navegacion de la izquierda.
///
/// No usa `NavigationRail` porque este menu agrupa las vistas por seccion y
/// cierra con el estado del enlace; el rail de Material no admite ni
/// cabeceras de grupo ni un pie que cambie en caliente.
class _MenuLateral extends StatelessWidget {
  const _MenuLateral({
    required this.vista,
    required this.extendido,
    required this.conexion,
    required this.nodosActivos,
    required this.nodosTotales,
    required this.onSeleccionar,
  });

  final VistaApp vista;
  final bool extendido;
  final EstadoConexion conexion;
  final int nodosActivos;
  final int nodosTotales;
  final ValueChanged<VistaApp> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Material(
      color: tema.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cabecera(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final grupo in GrupoMenu.values) ...[
                  if (extendido)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
                      child: Text(
                        grupo.etiqueta.toUpperCase(),
                        style: tema.textTheme.labelSmall?.copyWith(
                          color: tema.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.9,
                        ),
                      ),
                    )
                  else
                    const Divider(indent: 16, endIndent: 16, height: 18),
                  for (final destino
                      in VistaApp.values.where((v) => v.grupo == grupo))
                    _OpcionMenu(
                      destino: destino,
                      activa: destino == vista,
                      extendido: extendido,
                      onTocar: () => onSeleccionar(destino),
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          _pie(context),
        ],
      ),
    );
  }

  Widget _cabecera(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(extendido ? 20 : 14, 18, 14, 12),
      child: Row(
        children: [
          Icon(Icons.thermostat, color: tema.colorScheme.primary, size: 26),
          if (extendido) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'TermicGuard',
                style: tema.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Pie con el estado del enlace: siempre visible, se mire la vista que se
  /// mire, porque cualquier numero del dashboard es sospechoso si el enlace
  /// esta caido.
  Widget _pie(BuildContext context) {
    final tema = Theme.of(context);
    final (color, texto) = switch (conexion) {
      EstadoConexion.conectado => (Paleta.enLinea, 'En vivo'),
      EstadoConexion.conectando => (Paleta.alerta, 'Conectando'),
      EstadoConexion.desconectado => (Paleta.inactivo, 'Sin conexion'),
      EstadoConexion.error => (Paleta.desconectado, 'Broker caido'),
    };

    if (!extendido) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Tooltip(
          message: '$texto  ·  $nodosActivos/$nodosTotales nodos activos',
          child: Icon(Icons.circle, size: 12, color: color),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 9, color: color),
              const SizedBox(width: 8),
              Text(texto, style: tema.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$nodosActivos de $nodosTotales nodos activos',
            style: tema.textTheme.bodySmall?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpcionMenu extends StatelessWidget {
  const _OpcionMenu({
    required this.destino,
    required this.activa,
    required this.extendido,
    required this.onTocar,
  });

  final VistaApp destino;
  final bool activa;
  final bool extendido;
  final VoidCallback onTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color =
        activa ? tema.colorScheme.onSecondaryContainer : tema.colorScheme.onSurface;

    final contenido = Row(
      mainAxisAlignment:
          extendido ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        Icon(activa ? destino.iconoActivo : destino.icono, size: 20, color: color),
        if (extendido) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              destino.titulo,
              style: tema.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: activa ? FontWeight.w700 : FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: extendido ? 10 : 12, vertical: 2),
      child: Material(
        color: activa ? tema.colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTocar,
          child: Tooltip(
            message: extendido ? '' : destino.titulo,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: extendido ? 12 : 8,
                vertical: 11,
              ),
              child: contenido,
            ),
          ),
        ),
      ),
    );
  }
}

/// Banda de aviso no bloqueante (por ejemplo, API caida pero MQTT vivo).
class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      width: double.infinity,
      color: tema.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: tema.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(
                fontSize: 13,
                color: tema.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
