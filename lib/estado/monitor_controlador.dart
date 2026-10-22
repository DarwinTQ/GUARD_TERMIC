import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ajustes.dart';
import '../modelos/lectura.dart';
import '../modelos/nodo.dart';
import '../servicios/api_rest.dart';
import '../servicios/mqtt/mqtt_servicio.dart';

/// Fuente de verdad de la pantalla de monitorizacion.
///
/// Combina las dos fuentes de datos y es el unico sitio donde se decide
/// que ve la UI:
///   * REST: historial ya persistido, para que las graficas no arranquen vacias.
///   * MQTT: lecturas en vivo, que se van añadiendo a la ventana deslizante.
///
/// Si la API falla pero el broker responde, la app sigue siendo util: se
/// muestra el tiempo real y se avisa de que falta el historial.
class MonitorControlador extends ChangeNotifier {
  MonitorControlador({ApiRest? api, MqttServicio? mqtt})
      : _api = api ?? ApiRest(),
        _mqtt = mqtt ?? MqttServicio();

  final ApiRest _api;
  final MqttServicio _mqtt;

  final Map<String, Nodo> _nodos = {};
  StreamSubscription<EventoMqtt>? _subEventos;
  StreamSubscription<EstadoConexion>? _subConexion;
  Timer? _temporizadorFrescura;

  bool _cargandoHistorial = true;
  String? _avisoHistorial;
  EstadoConexion _conexion = EstadoConexion.desconectado;
  String? _seleccionado;

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

  // ----------------------------------------------------------------- ciclo

  Future<void> iniciar() async {
    await _cargarHistorial();
    await _conectarBroker();

    // Reevalua periodicamente `Nodo.activo` para que un nodo que deja de
    // publicar se marque como inactivo sin necesidad de un evento nuevo.
    _temporizadorFrescura = Timer.periodic(
      const Duration(seconds: 5),
      (_) => notifyListeners(),
    );
  }

  /// Recarga el historial desde la API sin tocar el enlace MQTT.
  Future<void> refrescar() async {
    _cargandoHistorial = true;
    notifyListeners();
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
      notifyListeners();
    }
  }

  Future<void> _conectarBroker() async {
    _subConexion ??= _mqtt.conexion.listen((estado) {
      _conexion = estado;
      notifyListeners();
    });
    _subEventos ??= _mqtt.eventos.listen(_aplicarEvento);
    await _mqtt.conectar();
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
    notifyListeners();
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
  }

  @override
  void dispose() {
    _temporizadorFrescura?.cancel();
    _subEventos?.cancel();
    _subConexion?.cancel();
    _mqtt.liberar();
    _api.cerrar();
    super.dispose();
  }
}
