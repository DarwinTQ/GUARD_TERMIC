/*
 * TermicGuard - Nodo sensor ESP32
 * ------------------------------------------------------------------
 * Publica dos temperaturas simuladas (32.0 - 42.0 C) en formato JSON
 * sobre MQTT cada INTERVALO_MS milisegundos.
 *
 * El mismo binario sirve para N nodos: si NODO_ID se deja vacio, el
 * identificador se deriva de la MAC del chip (esp32-a4cf12), por lo
 * que se puede flashear la misma placa-tras-placa sin editar nada.
 *
 * Topicos:
 *   termic_guard/telemetria/<nodo>  -> lecturas JSON
 *   termic_guard/estado/<nodo>      -> "online" / "offline" (retenido, LWT)
 *
 * Librerias requeridas (Arduino IDE -> Gestor de librerias):
 *   - PubSubClient  (Nick O'Leary)
 *   - ArduinoJson   (Benoit Blanchon, v7)
 *
 * Placa: "ESP32 Dev Module" (paquete esp32 de Espressif)
 */

#include <ArduinoJson.h>
#include <PubSubClient.h>
#include <WiFi.h>

// ======================= CONFIGURACION =======================

// --- Red WiFi ---
const char* WIFI_SSID     = "CAMBIAME";
const char* WIFI_PASSWORD = "CAMBIAME";

// --- Broker MQTT (IP de la laptop que corre docker compose) ---
const char* MQTT_HOST = "10.103.180.103";
const uint16_t MQTT_PORT = 1883;
const char* MQTT_USUARIO  = "";  // vacio = acceso anonimo (perfil local)
const char* MQTT_CLAVE    = "";

// --- Identidad del nodo ---
// Vacio => se deriva de la MAC. Rellenar solo si se quiere un nombre fijo.
const char* NODO_ID = "";

// --- Comportamiento ---
const uint32_t INTERVALO_MS = 5000;  // cada cuanto se publica una lectura
const float TEMP_MIN = 32.0f;
const float TEMP_MAX = 42.0f;
const float PASO_MAX = 0.4f;  // variacion maxima entre lecturas consecutivas

// =============================================================

namespace {

const char* PREFIJO_TOPICO = "termic_guard";

WiFiClient wifi;
PubSubClient mqtt(wifi);

String nodoId;
String topicoTelemetria;
String topicoEstado;

// Estado del paseo aleatorio de cada sensor.
float sensor1;
float sensor2;

uint32_t ultimaPublicacion = 0;
uint32_t ultimoIntentoMqtt = 0;

/// Identificador estable y legible derivado de la MAC: "esp32-a4cf12".
String idDerivadoDeMac() {
  uint64_t mac = ESP.getEfuseMac();
  char buffer[16];
  snprintf(buffer, sizeof(buffer), "esp32-%02x%02x%02x",
           (uint8_t)(mac >> 24), (uint8_t)(mac >> 32), (uint8_t)(mac >> 40));
  return String(buffer);
}

float aleatorioEnRango(float minimo, float maximo) {
  return minimo + (float)random(0, 10001) / 10000.0f * (maximo - minimo);
}

/// Paseo aleatorio acotado: oscila dentro de [TEMP_MIN, TEMP_MAX] sin saltos
/// bruscos, de modo que la grafica se parezca a un sensor real.
float siguienteTemperatura(float actual) {
  float propuesta = actual + aleatorioEnRango(-PASO_MAX, PASO_MAX);
  return constrain(propuesta, TEMP_MIN, TEMP_MAX);
}

void conectarWifi() {
  if (WiFi.status() == WL_CONNECTED) return;

  Serial.printf("[wifi] conectando a %s", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  while (WiFi.status() != WL_CONNECTED) {
    delay(400);
    Serial.print('.');
  }
  Serial.printf("\n[wifi] ok  ip=%s  rssi=%d dBm\n",
                WiFi.localIP().toString().c_str(), WiFi.RSSI());
}

/// Intenta una reconexion MQTT. No bloquea: si falla, se reintenta en el
/// siguiente loop() pasados 3 s.
bool conectarMqtt() {
  if (mqtt.connected()) return true;
  if (ultimoIntentoMqtt != 0 && millis() - ultimoIntentoMqtt < 3000) return false;
  ultimoIntentoMqtt = millis();

  Serial.printf("[mqtt] conectando a %s:%u ...\n", MQTT_HOST, MQTT_PORT);

  // Last Will: si el nodo se apaga o pierde la red, el broker publica
  // "offline" en su topico de estado y el dashboard lo marca caido.
  const bool conectado =
      (strlen(MQTT_USUARIO) > 0)
          ? mqtt.connect(nodoId.c_str(), MQTT_USUARIO, MQTT_CLAVE,
                         topicoEstado.c_str(), 1, true, "offline")
          : mqtt.connect(nodoId.c_str(), nullptr, nullptr,
                         topicoEstado.c_str(), 1, true, "offline");

  if (!conectado) {
    Serial.printf("[mqtt] fallo (rc=%d), reintento en 3 s\n", mqtt.state());
    return false;
  }

  mqtt.publish(topicoEstado.c_str(), "online", true);  // retenido
  Serial.printf("[mqtt] ok  nodo=%s  topico=%s\n", nodoId.c_str(),
                topicoTelemetria.c_str());
  return true;
}

void publicarLectura() {
  sensor1 = siguienteTemperatura(sensor1);
  sensor2 = siguienteTemperatura(sensor2);

  // La fecha la pone el servidor: el ESP32 no tiene reloj de tiempo real.
  JsonDocument doc;
  doc["dispositivo"] = nodoId;
  doc["sensor1"] = round(sensor1 * 10) / 10.0;
  doc["sensor2"] = round(sensor2 * 10) / 10.0;
  doc["rssi"] = WiFi.RSSI();
  doc["uptime_ms"] = millis();

  char payload[192];
  const size_t escritos = serializeJson(doc, payload, sizeof(payload));

  if (mqtt.publish(topicoTelemetria.c_str(), (const uint8_t*)payload, escritos, false)) {
    Serial.printf("[pub] %s\n", payload);
  } else {
    Serial.println("[pub] error al publicar");
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(200);

  nodoId = (strlen(NODO_ID) > 0) ? String(NODO_ID) : idDerivadoDeMac();
  topicoTelemetria = String(PREFIJO_TOPICO) + "/telemetria/" + nodoId;
  topicoEstado = String(PREFIJO_TOPICO) + "/estado/" + nodoId;

  Serial.printf("\n=== TermicGuard :: nodo %s ===\n", nodoId.c_str());

  // Semilla distinta por placa para que dos nodos no publiquen la misma serie.
  randomSeed((uint32_t)ESP.getEfuseMac());
  sensor1 = aleatorioEnRango(TEMP_MIN, TEMP_MAX);
  sensor2 = aleatorioEnRango(TEMP_MIN, TEMP_MAX);

  conectarWifi();

  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(256);
  mqtt.setKeepAlive(15);
}

void loop() {
  conectarWifi();

  if (!conectarMqtt()) {
    delay(50);
    return;
  }

  mqtt.loop();

  if (millis() - ultimaPublicacion >= INTERVALO_MS) {
    ultimaPublicacion = millis();
    publicarLectura();
  }
}
