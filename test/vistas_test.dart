import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:guard/estado/explorador_bd.dart';
import 'package:guard/estado/monitor_controlador.dart';
import 'package:guard/modelos/lectura.dart';
import 'package:guard/modelos/metricas.dart';
import 'package:guard/modelos/nodo.dart';
import 'package:guard/pantallas/vistas/vista_base_datos.dart';
import 'package:guard/pantallas/vistas/vista_nodos.dart';
import 'package:guard/pantallas/vistas/vista_resumen.dart';
import 'package:guard/pantallas/vistas/vista_sistema.dart';
import 'package:guard/pantallas/vistas/vista_tiempos_llegada.dart';
import 'package:guard/pantallas/vistas/vista_tiempos_respuesta.dart';
import 'package:guard/servicios/api_rest.dart';
import 'package:guard/servicios/mqtt/mqtt_servicio.dart';

/// Prueba de humo de las vistas del dashboard.
///
/// No comprueba logica de negocio: comprueba que cada vista se construye con
/// datos reales a lo ancho y a lo estrecho sin lanzar. Es lo unico que
/// detecta los desbordes de layout, que no aparecen ni en `flutter analyze`
/// ni al compilar; solo al pintar.
///
/// Los dos servicios estan falseados, asi que ninguna prueba toca la red.
void main() {
  late MonitorControlador controlador;
  late MqttFalso mqtt;

  setUp(() async {
    mqtt = MqttFalso();
    controlador = MonitorControlador(api: ApiRest(cliente: clienteFalso(), urlBase: 'http://falso'), mqtt: mqtt);
    await controlador.iniciar();

    // Dos nodos con trafico en vivo: asi se pueblan tambien las metricas de
    // llegada, que solo se alimentan del flujo MQTT.
    final ahora = DateTime.now();
    for (var i = 0; i < 12; i++) {
      for (final nodo in ['nodo1', 'nodo2']) {
        mqtt.emitir(
          EventoLectura(
            Lectura(
              dispositivo: nodo,
              sensor1: 35 + i * 0.3,
              sensor2: 37 - i * 0.2,
              fecha: ahora.subtract(Duration(seconds: (12 - i) * 5)),
              rssi: -52,
            ),
          ),
        );
      }
    }
    mqtt.emitir(const EventoEstadoNodo('nodo2', EstadoNodo.desconectado));
    await Future<void>.delayed(Duration.zero); // deja correr los streams
  });

  tearDown(() => controlador.dispose());

  /// Monta una vista dentro de la app con un tamaño de pantalla concreto.
  Future<void> montar(WidgetTester tester, Widget vista, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: vista)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  const escritorio = Size(1440, 900);
  const movil = Size(420, 880);

  for (final (nombre, tamano) in [('escritorio', escritorio), ('movil', movil)]) {
    group('en $nombre', () {
      testWidgets('resumen', (tester) async {
        await montar(
          tester,
          VistaResumen(controlador: controlador, onAbrirNodo: (_) {}),
          tamano,
        );
        expect(find.textContaining('nodo1'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('vista de nodos', (tester) async {
        await montar(tester, VistaNodos(controlador: controlador), tamano);
        expect(find.textContaining('nodo1'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('tiempos de respuesta', (tester) async {
        await montar(
          tester,
          VistaTiemposRespuesta(controlador: controlador),
          tamano,
        );
        expect(find.text('API REST'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('tiempos de llegada', (tester) async {
        await montar(
          tester,
          VistaTiemposLlegada(controlador: controlador),
          tamano,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('base de datos', (tester) async {
        final explorador = ExploradorBd(
          api: ApiRest(cliente: clienteFalso(), urlBase: 'http://falso'),
        );
        await explorador.cargar();
        addTearDown(explorador.dispose);

        await montar(tester, VistaBaseDatos(explorador: explorador), tamano);
        expect(explorador.error, isNull);
        expect(find.text('lecturas'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('sistema', (tester) async {
        await montar(tester, VistaSistema(controlador: controlador), tamano);
        expect(tester.takeException(), isNull);
      });
    });
  }

  test('las metricas de llegada miden el hueco entre mensajes', () {
    final metricas = controlador.metricasDe('nodo1');
    expect(metricas.mensajes, 12);
    expect(metricas.promedio, isNotNull);
    // Las lecturas se emitieron con 5 s de separacion.
    expect(metricas.promedio!.inSeconds, 5);
    expect(metricas.huecos, 0);
  });

  test('la ventana temporal recorta las lecturas visibles', () {
    final nodo = controlador.nodos.firstWhere((n) => n.id == 'nodo1');
    controlador.cambiarVentana(VentanaTiempo.unMinuto);
    final visibles = controlador.lecturasVisibles(nodo);
    expect(visibles.length, lessThan(nodo.lecturas.length));

    controlador.cambiarVentana(VentanaTiempo.todo);
    expect(controlador.lecturasVisibles(nodo).length, nodo.lecturas.length);
  });
}

/// Cliente HTTP que responde lo mismo que la API real, sin red.
http.Client clienteFalso() {
  return MockClient((peticion) async {
    final ruta = peticion.url.path;

    if (ruta == '/') {
      return http.Response(
        jsonEncode({'estado': 'ok', 'mongodb': 'conectado'}),
        200,
      );
    }
    if (ruta == '/lecturas/total') {
      return http.Response(jsonEncode({'total': 1225}), 200);
    }
    if (ruta == '/lecturas') {
      // Anclado al reloj del momento: con una fecha fija la prueba caducaria.
      final base = DateTime.now().toUtc();
      return http.Response(
        jsonEncode([
          for (var i = 0; i < 50; i++)
            {
              'id': '6ae26925df4b9f131eb1e9${i.toString().padLeft(2, '0')}',
              'dispositivo': i.isEven ? 'nodo1' : 'nodo2',
              'sensor1': 36.0 + i % 5,
              'sensor2': 38.0 - i % 4,
              'fecha': base.subtract(Duration(seconds: i * 5)).toIso8601String(),
              'rssi': -50 - i % 7,
            },
        ]),
        200,
      );
    }
    if (ruta == '/dispositivos') {
      return http.Response(
        jsonEncode([
          {
            'dispositivo': 'nodo1',
            'estado': 'online',
            'vista_por_ultima_vez': DateTime.now().toUtc().toIso8601String(),
            'ultima_lectura': null,
          },
          {
            'dispositivo': 'nodo2',
            'estado': 'offline',
            'vista_por_ultima_vez': DateTime.now().toUtc().toIso8601String(),
            'ultima_lectura': null,
          },
        ]),
        200,
      );
    }
    if (ruta == '/estadisticas') {
      return http.Response(
        jsonEncode([
          {
            'dispositivo': 'nodo1',
            'lecturas': 726,
            'sensor1': {'minimo': 35.2, 'maximo': 42.0, 'promedio': 39.12},
            'sensor2': {'minimo': 38.8, 'maximo': 42.0, 'promedio': 41.22},
            'rssi_prom': -43.4,
            'primera': '2026-10-22T01:13:45.912000+00:00',
            'ultima': '2026-10-28T21:29:19.242000+00:00',
            'intervalo_medio_s': 815.63,
          },
          {
            'dispositivo': 'nodo2',
            'lecturas': 499,
            'sensor1': {'minimo': 32.0, 'maximo': 38.4, 'promedio': 34.54},
            'sensor2': {'minimo': 32.0, 'maximo': 39.6, 'promedio': 34.44},
            'rssi_prom': -40.2,
            'primera': '2026-10-28T20:47:50.037000+00:00',
            'ultima': '2026-10-28T21:29:19.990000+00:00',
            'intervalo_medio_s': 5.0,
          },
        ]),
        200,
      );
    }
    if (ruta == '/bd/resumen') {
      return http.Response(
        jsonEncode({
          'base_datos': 'termic_guard',
          'servidor': '7.0.43',
          'colecciones': [
            {
              'nombre': 'lecturas',
              'documentos': 1225,
              'bytes': 145775,
              'bytes_indices': 176128,
              'indices': [
                {'nombre': '_id_', 'campos': ['_id:1']},
                {'nombre': 'fecha_desc', 'campos': ['fecha:-1']},
                {
                  'nombre': 'dispositivo_fecha',
                  'campos': ['dispositivo:1', 'fecha:-1'],
                },
              ],
            },
            {
              'nombre': 'dispositivos',
              'documentos': 2,
              'bytes': 319,
              'bytes_indices': 36864,
              'indices': [
                {'nombre': '_id_', 'campos': ['_id:1']},
              ],
            },
          ],
        }),
        200,
      );
    }
    return http.Response('no encontrado', 404);
  });
}

/// Enlace MQTT falso: no abre sockets y permite inyectar eventos a mano.
class MqttFalso extends MqttServicio {
  MqttFalso() : super(url: 'ws://falso', puerto: 9001);

  final _eventos = StreamController<EventoMqtt>.broadcast();
  final _conexion = StreamController<EstadoConexion>.broadcast();

  @override
  Stream<EventoMqtt> get eventos => _eventos.stream;

  @override
  Stream<EstadoConexion> get conexion => _conexion.stream;

  @override
  Future<void> conectar() async => _conexion.add(EstadoConexion.conectado);

  @override
  Future<MuestraLatencia> sondear() async => MuestraLatencia(
        instante: DateTime.now(),
        duracion: const Duration(milliseconds: 14),
      );

  @override
  Future<void> liberar() async {
    await _eventos.close();
    await _conexion.close();
  }

  void emitir(EventoMqtt evento) => _eventos.add(evento);
}
