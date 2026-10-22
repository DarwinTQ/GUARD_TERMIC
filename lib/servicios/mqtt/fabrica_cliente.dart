/// Selecciona la implementacion de cliente MQTT segun la plataforma.
///
/// `mqtt_client` expone dos clases distintas con la misma interfaz base:
/// `MqttServerClient` (movil/desktop) y `MqttBrowserClient` (web). Esta
/// exportacion condicional deja que el resto de la app ignore la diferencia.
library;

export 'fabrica_nativa.dart'
    if (dart.library.js_interop) 'fabrica_web.dart';
