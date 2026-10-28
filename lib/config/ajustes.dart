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
    defaultValue: '10.137.195.103',
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

  /// Topico de eco que solo usa la app para medir el RTT del broker.
  ///
  /// Cuelga de un segmento propio (`sonda`), no de `telemetria`, para que la
  /// ingesta -suscrita con comodin a telemetria y estado- lo ignore y estas
  /// mediciones no acaben en la base de datos.
  static const String topicoSonda = '$prefijoTopico/sonda/app';

  // --- Limites de la vista ---
  /// Lecturas que se piden a la API al abrir la app.
  static const int limiteHistorial = 300;

  /// Puntos que conserva en memoria cada nodo (ventana deslizante del grafico).
  static const int maxPuntosPorNodo = 120;

  /// Si un nodo no publica en este tiempo, se considera inactivo.
  static const Duration tiempoSinSenal = Duration(seconds: 20);

  // --- Tiempo real y metricas ---
  /// Cada cuanto se repinta el dashboard aunque no llegue nada nuevo.
  ///
  /// Un segundo: la ventana temporal de las graficas se desplaza sola y los
  /// contadores de "hace N s" avanzan sin esperar a la siguiente lectura.
  static const Duration refrescoVista = Duration(seconds: 1);

  /// Cada cuanto se mide la latencia de la API y el RTT del broker.
  static const Duration intervaloSondeo = Duration(seconds: 5);

  /// Si una sonda no responde en este tiempo, cuenta como fallo.
  static const Duration tiempoLimiteSonda = Duration(seconds: 3);

  /// Muestras de latencia que se conservan (5 s x 120 = 10 min de historia).
  static const int maxMuestrasLatencia = 120;

  /// Intervalos entre llegadas que se conservan por nodo.
  static const int maxIntervalosPorNodo = 60;

  /// Periodo de publicacion nominal del firmware (`INTERVALO_MS`).
  ///
  /// Es la referencia contra la que se compara el ritmo real de llegada:
  /// si cambias INTERVALO_MS en el sketch, cambia esto tambien.
  static const Duration intervaloNominalNodo = Duration(seconds: 5);

  /// Filas por pagina en la vista de base de datos.
  static const int filasPorPagina = 50;
}
