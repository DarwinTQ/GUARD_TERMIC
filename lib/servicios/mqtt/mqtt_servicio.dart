import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../../config/ajustes.dart';
import '../../modelos/lectura.dart';
import '../../modelos/nodo.dart';
import 'fabrica_cliente.dart';

/// Estado del enlace con el broker, para pintarlo en la barra superior.
enum EstadoConexion { desconectado, conectando, conectado, error }

/// Evento ya interpretado que sale del broker.
sealed class EventoMqtt {
  const EventoMqtt();
}

/// Una lectura nueva publicada por un nodo.
class EventoLectura extends EventoMqtt {
  const EventoLectura(this.lectura);
  final Lectura lectura;
}

/// Cambio de conectividad de un nodo (mensaje retenido o Last Will).
class EventoEstadoNodo extends EventoMqtt {
  const EventoEstadoNodo(this.dispositivo, this.estado);
  final String dispositivo;
  final EstadoNodo estado;
}

/// Enlace en tiempo real con Mosquitto sobre WebSocket.
///
/// Funciona igual en movil, desktop y web (ver `fabrica_cliente.dart`).
/// Se suscribe con comodin a todos los nodos, de modo que añadir un ESP32
/// no requiere cambiar nada en la app: aparece solo en el dashboard.
class MqttServicio {
  MqttServicio({String? url, int? puerto})
      : _url = url ?? Ajustes.urlMqtt,
        _puerto = puerto ?? Ajustes.puertoMqtt;

  final String _url;
  final int _puerto;

  MqttClient? _cliente;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _suscripcion;

  final _eventos = StreamController<EventoMqtt>.broadcast();
  final _conexion = StreamController<EstadoConexion>.broadcast();

  /// Lecturas y cambios de estado de todos los nodos.
  Stream<EventoMqtt> get eventos => _eventos.stream;

  /// Estado del enlace con el broker.
  Stream<EstadoConexion> get conexion => _conexion.stream;

  EstadoConexion _estado = EstadoConexion.desconectado;
  EstadoConexion get estado => _estado;

  String get url => '$_url:$_puerto';

  void _emitirConexion(EstadoConexion nuevo) {
    _estado = nuevo;
    if (!_conexion.isClosed) _conexion.add(nuevo);
  }

  Future<void> conectar() async {
    if (_estado == EstadoConexion.conectando ||
        _estado == EstadoConexion.conectado) {
      return;
    }
    _emitirConexion(EstadoConexion.conectando);

    // Id unico por instancia: dos clientes con el mismo id se expulsan
    // mutuamente del broker.
    final idCliente = 'tg-app-${DateTime.now().microsecondsSinceEpoch}';
    final cliente = crearClienteMqtt(
      url: _url,
      puerto: _puerto,
      idCliente: idCliente,
    )
      ..keepAlivePeriod = 20
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: false)
      // Cuerpos con bloque: los callbacks de mqtt_client no admiten una
      // expresion de tipo void como cuerpo de flecha.
      ..onConnected = () {
        _emitirConexion(EstadoConexion.conectado);
      }
      ..onDisconnected = () {
        _emitirConexion(EstadoConexion.desconectado);
      }
      ..onAutoReconnect = () {
        _emitirConexion(EstadoConexion.conectando);
      }
      ..onAutoReconnected = () {
        _emitirConexion(EstadoConexion.conectado);
      }
      ..connectionMessage =
          (MqttConnectMessage().withClientIdentifier(idCliente).startClean());

    _cliente = cliente;

    try {
      await cliente.connect();
    } catch (error) {
      debugPrint('MQTT: fallo al conectar a $url -> $error');
      cliente.disconnect();
      _cliente = null;
      _emitirConexion(EstadoConexion.error);
      return;
    }

    if (cliente.connectionStatus?.state != MqttConnectionState.connected) {
      _emitirConexion(EstadoConexion.error);
      return;
    }

    cliente.subscribe(Ajustes.topicoTelemetria, MqttQos.atMostOnce);
    cliente.subscribe(Ajustes.topicoEstado, MqttQos.atLeastOnce);

    _suscripcion = cliente.updates?.listen(_procesarMensajes);
    _emitirConexion(EstadoConexion.conectado);
  }

  void _procesarMensajes(List<MqttReceivedMessage<MqttMessage>> mensajes) {
    final recibida = DateTime.now();

    for (final mensaje in mensajes) {
      final publicacion = mensaje.payload;
      if (publicacion is! MqttPublishMessage) continue;

      final nodo = _nodoDesdeTopico(mensaje.topic);
      if (nodo == null) continue;

      final texto = utf8.decode(
        publicacion.payload.message,
        allowMalformed: true,
      );

      if (mensaje.topic.contains('/telemetria/')) {
        _emitirLectura(nodo, texto, recibida);
      } else if (mensaje.topic.contains('/estado/')) {
        _eventos.add(EventoEstadoNodo(nodo, EstadoNodo.desdeTexto(texto.trim())));
      }
    }
  }

  void _emitirLectura(String nodo, String texto, DateTime recibida) {
    try {
      final json = jsonDecode(texto) as Map<String, dynamic>;
      _eventos.add(
        EventoLectura(
          Lectura.desdeMqtt(json, dispositivo: nodo, recibida: recibida),
        ),
      );
    } catch (error) {
      // Un payload corrupto de un nodo no debe romper el stream.
      debugPrint('MQTT: payload invalido de $nodo -> $error');
    }
  }

  /// `termic_guard/telemetria/esp32-01` -> `esp32-01`
  static String? _nodoDesdeTopico(String topico) {
    final partes = topico.split('/');
    return partes.length == 3 && partes[2].isNotEmpty ? partes[2] : null;
  }

  Future<void> desconectar() async {
    await _suscripcion?.cancel();
    _suscripcion = null;
    _cliente?.disconnect();
    _cliente = null;
    _emitirConexion(EstadoConexion.desconectado);
  }

  Future<void> liberar() async {
    await desconectar();
    await _eventos.close();
    await _conexion.close();
  }
}
