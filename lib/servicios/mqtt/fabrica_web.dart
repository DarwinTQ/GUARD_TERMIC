import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

/// Cliente MQTT para Flutter Web (WebSocket del navegador).
MqttClient crearClienteMqtt({
  required String url,
  required int puerto,
  required String idCliente,
}) {
  return MqttBrowserClient.withPort(url, idCliente, puerto);
}
