import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ajustes.dart';
import '../modelos/lectura.dart';
import '../modelos/metricas.dart';
import '../modelos/nodo.dart';
import '../servicios/api_rest.dart';
import '../servicios/mqtt/mqtt_servicio.dart';

/// Ventanas temporales que ofrece la grafica en vivo.
enum VentanaTiempo {
  unMinuto('1 min', Duration(minutes: 1)),
  cincoMinutos('5 min', Duration(minutes: 5)),
  quinceMinutos('15 min', Duration(minutes: 15)),
  todo('Todo', null);

  const VentanaTiempo(this.etiqueta, this.duracion);
  final String etiqueta;

  /// `null` = sin recorte, se muestra toda la ventana en memoria.
  final Duration? duracion;
}

/// Fuente de verdad de la pantalla de monitorizacion.
///
/// Combina las dos fuentes de datos y es el unico sitio donde se decide
/// que ve la UI:
///   * REST: historial ya persistido, para que las graficas no arranquen vacias.
///   * MQTT: lecturas en vivo, que se van añadiendo a la ventana deslizante.
///
/// Si la API falla pero el broker responde, la app sigue siendo util: se
/// muestra el tiempo real y se avisa de que falta el historial.
///
/// Ademas instrumenta el propio enlace: cada [Ajustes.intervaloSondeo] mide
/// el tiempo de respuesta de la API y el RTT del broker, y por cada lectura
/// en vivo anota el hueco respecto a la anterior. Esos numeros alimentan las
/// vistas de tiempos de respuesta y de llegada.
class MonitorControlador extends ChangeNotifier {
  MonitorControlador({ApiRest? api, MqttServicio? mqtt})
      : _api = api ?? ApiRest(),
        _mqtt = mqtt ?? MqttServicio();

  final ApiRest _api;
  final MqttServicio _mqtt;

  final Map<String, Nodo> _nodos = {};
  final Map<String, MetricasNodo> _metricas = {};

  /// Tiempo de respuesta de la API REST, muestreado periodicamente.
  final SerieLatencia latenciaApi = SerieLatencia('API REST');

  /// Ida y vuelta real contra Mosquitto sobre WebSocket.
  final SerieLatencia latenciaBroker = SerieLatencia('Broker MQTT');

  StreamSubscription<EventoMqtt>? _subEventos;
  StreamSubscription<EstadoConexion>? _subConexion;
  Timer? _temporizadorFrescura;
  Timer? _temporizadorSondeo;

  bool _cargandoHistorial = true;
  bool _liberado = false;
  String? _avisoHistorial;
  EstadoConexion _conexion = EstadoConexion.desconectado;
  String? _seleccionado;
  VentanaTiempo _ventana = VentanaTiempo.cincoMinutos;

  DateTime? _inicioSesion;
  int _lecturasEnVivo = 0;

  // ------------------------------------------------------------- lectura UI

  /// Nodos ordenados por id, para que la lista no baile entre refrescos.
  List<Nodo> get nodos {
    final lista = _nodos.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(lista);
  }

  bool get cargandoHistorial => _cargandoHistorial;
  String? get avisoHistorial => _avisoHistorial;
  EstadoConexion get conexion => _conexion;
  String get urlBroker => _mqtt.url;
  String get urlApi => Ajustes.urlApi;
  bool get sinDatos => _nodos.isEmpty;

  int get nodosActivos => _nodos.values.where((n) => n.activo).length;
  int get nodosTotales => _nodos.length;
  int get nodosCaidos =>
      _nodos.values.where((n) => n.estado == EstadoNodo.desconectado).length;

  /// Lecturas recibidas por MQTT desde que se abrio la app.
  int get lecturasEnVivo => _lecturasEnVivo;

  /// Cuanto lleva abierta esta sesion (denominador de las tasas).
  Duration get tiempoEnMarcha {
    final inicio = _inicioSesion;
    return inicio == null ? Duration.zero : DateTime.now().difference(inicio);
  }

  /// Puntos que acumula el dashboard sumando todas las series en memoria.
  int get puntosEnMemoria =>
      _nodos.values.fold(0, (suma, n) => suma + n.lecturas.length);

  /// Media de la ultima lectura de cada nodo activo.
  ///
  /// Solo cuenta nodos activos: promediar la ultima temperatura conocida de
  /// un nodo apagado hace horas daria una cifra que no describe nada.
  double? get temperaturaMediaGlobal {
    final valores = [
      for (final nodo in _nodos.values)
        if (nodo.activo && nodo.ultima != null) nodo.ultima!.promedio,
    ];
    if (valores.isEmpty) return null;
    return valores.reduce((a, b) => a + b) / valores.length;
  }

  /// Lectura mas caliente ahora mismo, para destacar el nodo en riesgo.
  Lectura? get lecturaMasCaliente {
    Lectura? maxima;
    for (final nodo in _nodos.values) {
      final ultima = nodo.ultima;
      if (ultima == null || !nodo.activo) continue;
      if (maxima == null || _pico(ultima) > _pico(maxima)) maxima = ultima;
    }
    return maxima;
  }

  static double _pico(Lectura lectura) =>
      lectura.sensor1 > lectura.sensor2 ? lectura.sensor1 : lectura.sensor2;

  VentanaTiempo get ventana => _ventana;

  void cambiarVentana(VentanaTiempo nueva) {
    if (_ventana == nueva) return;
    _ventana = nueva;
    notifyListeners();
  }

  /// Lecturas de un nodo recortadas a la ventana temporal elegida.
  ///
  /// El recorte se hace aqui y no en el widget para que la grafica grande,
  /// las tarjetas y las estadisticas de cabecera miren exactamente el mismo
  /// conjunto de puntos.
  List<Lectura> lecturasVisibles(Nodo nodo) {
    final duracion = _ventana.duracion;
    if (duracion == null) return nodo.lecturas;
    final corte = DateTime.now().subtract(duracion);
    return nodo.lecturas.where((l) => l.fecha.isAfter(corte)).toList();
  }

  /// Metricas de llegada de un nodo; se crean vacias la primera vez.
  MetricasNodo metricasDe(String id) =>
      _metricas.putIfAbsent(id, () => MetricasNodo(id));

  /// Metricas de todos los nodos conocidos, en el mismo orden que [nodos].
  List<MetricasNodo> get metricas =>
      [for (final nodo in nodos) metricasDe(nodo.id)];

  /// Nodo abierto en el panel de detalle (el primero por defecto).
  Nodo? get seleccionado {
    if (_nodos.isEmpty) return null;
    final elegido = _seleccionado;
    if (elegido != null && _nodos.containsKey(elegido)) return _nodos[elegido];
    return nodos.first;
  }

  void seleccionar(String id) {
    if (!_nodos.containsKey(id) || _seleccionado == id) return;
    _seleccionado = id;
    notifyListeners();
  }

  // ------------------------------------------------------------------ ciclo

  Future<void> iniciar() async {
    _inicioSesion = DateTime.now();
    await _cargarHistorial();
    await _conectarBroker();

    // Repintado a 1 Hz: la ventana temporal de las graficas se desplaza sola
    // y `Nodo.activo` se reevalua sin esperar a que llegue un evento nuevo.
    _temporizadorFrescura = Timer.periodic(
      Ajustes.refrescoVista,
      (_) => _avisar(),
    );

    _temporizadorSondeo = Timer.periodic(
      Ajustes.intervaloSondeo,
      (_) => _sondear(),
    );
    await _sondear(); // primera muestra sin esperar al primer tick
  }

  /// Recarga el historial desde la API sin tocar el enlace MQTT.
  Future<void> refrescar() async {
    _cargandoHistorial = true;
    _avisar();
    await _cargarHistorial();
    if (_conexion != EstadoConexion.conectado) {
      await _conectarBroker();
    }
  }

  Future<void> _cargarHistorial() async {
    try {
      final historial = await _api.historialPorNodo();
      final estados = await _api.estadoDeNodos();

      for (final entrada in historial.entries) {
        _nodos[entrada.key] = Nodo(
          id: entrada.key,
          lecturas: entrada.value,
          estado: estados[entrada.key] ?? EstadoNodo.desconocido,
        );
      }
      // Nodos conocidos que aun no tienen lecturas en la ventana cargada.
      for (final entrada in estados.entries) {
        _nodos.putIfAbsent(
          entrada.key,
          () => Nodo(id: entrada.key, lecturas: const [], estado: entrada.value),
        );
      }
      _avisoHistorial = null;
    } catch (error) {
      _avisoHistorial = 'Sin historial: no se pudo consultar ${Ajustes.urlApi}';
      debugPrint('Historial no disponible: $error');
    } finally {
      _cargandoHistorial = false;
      _avisar();
    }
  }

  Future<void> _conectarBroker() async {
    _subConexion ??= _mqtt.conexion.listen((estado) {
      _conexion = estado;
      _avisar();
    });
    _subEventos ??= _mqtt.eventos.listen(_aplicarEvento);
    await _mqtt.conectar();
  }

  /// Mide los dos caminos a la vez: si uno tarda, no retrasa la medicion del
  /// otro y la comparacion entre ambos sigue siendo del mismo instante.
  Future<void> _sondear() async {
    final resultados = await Future.wait([_api.sondear(), _mqtt.sondear()]);
    if (_liberado) return;
    latenciaApi.agregar(resultados[0]);
    latenciaBroker.agregar(resultados[1]);
    _avisar();
  }

  void _aplicarEvento(EventoMqtt evento) {
    switch (evento) {
      case EventoLectura(:final lectura):
        _registrarLectura(lectura);
      case EventoEstadoNodo(:final dispositivo, :final estado):
        final actual = _nodos[dispositivo];
        _nodos[dispositivo] = actual == null
            ? Nodo(id: dispositivo, lecturas: const [], estado: estado)
            : actual.copiarCon(estado: estado);
    }
    _avisar();
  }

  void _registrarLectura(Lectura lectura) {
    final actual = _nodos[lectura.dispositivo];
    _nodos[lectura.dispositivo] = actual == null
        ? Nodo(
            id: lectura.dispositivo,
            lecturas: [lectura],
            estado: EstadoNodo.enLinea,
          )
        : actual.conLectura(lectura);

    // Solo las lecturas en vivo alimentan las metricas de llegada: en las
    // del historial `fecha` es la hora a la que el servidor persistio, no la
    // hora a la que el mensaje llego a esta app.
    metricasDe(lectura.dispositivo).registrarLlegada(lectura.fecha);
    _lecturasEnVivo++;
  }

  /// `notifyListeners` seguro: los temporizadores y los `await` pueden
  /// disparar despues de que la pantalla se haya cerrado.
  void _avisar() {
    if (_liberado) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _liberado = true;
    _temporizadorFrescura?.cancel();
    _temporizadorSondeo?.cancel();
    _subEventos?.cancel();
    _subConexion?.cancel();
    _mqtt.liberar();
    _api.cerrar();
    super.dispose();
  }
}
