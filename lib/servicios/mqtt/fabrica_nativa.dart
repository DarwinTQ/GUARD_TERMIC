import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Cliente MQTT para Android, iOS, Windows, macOS y Linux.
///
/// Se usa WebSocket (no TCP puro) para hablar el mismo protocolo y puerto
/// que la version web: un solo listener que mantener en el broker.
MqttClient crearClienteMqtt({
  required String url,
  required int puerto,
  required String idCliente,
}) {
  final cliente = MqttServerClient.withPort(url, idCliente, puerto)
    ..useWebSocket = true
    ..websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return cliente;
}
