/// Configuracion de la app en un solo sitio.
///
/// Los valores se pueden sobrescribir al compilar sin tocar codigo:
///   flutter run --dart-define=TG_HOST=192.168.1.50
/// Asi un mismo codigo sirve para emulador, movil fisico, web y desktop.
class Ajustes {
  const Ajustes._();

  /// IP de la laptop que ejecuta `docker compose` en `infra/`.
  /// En el emulador de Android usar 10.0.2.2.
  static const String host = String.fromEnvironment(
    'TG_HOST',
    defaultValue: '10.103.180.103',
  );

  /// Puerto WebSocket de Mosquitto (el 1883 es TCP y no sirve en navegador).
  static const int puertoMqtt = int.fromEnvironment(
    'TG_MQTT_WS',
    defaultValue: 9001,
  );

  /// Puerto de la API REST de historial.
  static const int puertoApi = int.fromEnvironment(
    'TG_API',
    defaultValue: 8001,
  );

  static String get urlApi => 'http://$host:$puertoApi';
  static String get urlMqtt => 'ws://$host:$puertoMqtt';

  // --- Topicos MQTT (deben coincidir con el firmware y con la ingesta) ---
  static const String prefijoTopico = 'termic_guard';
  static const String topicoTelemetria = '$prefijoTopico/telemetria/+';
  static const String topicoEstado = '$prefijoTopico/estado/+';

  // --- Limites de la vista ---
  /// Lecturas que se piden a la API al abrir la app.
  static const int limiteHistorial = 300;

  /// Puntos que conserva en memoria cada nodo (ventana deslizante del grafico).
  static const int maxPuntosPorNodo = 120;

  /// Si un nodo no publica en este tiempo, se considera inactivo.
  static const Duration tiempoSinSenal = Duration(seconds: 20);
}
