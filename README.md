# TermicGuard

Monitorización de temperatura en tiempo real para una red de nodos ESP32.
Cada nodo publica dos temperaturas por MQTT, un servicio las persiste en
MongoDB y una única app Flutter las muestra en vivo en **móvil, desktop y web**.

---

## Arquitectura

```
   ESP32 #1 ─┐
   ESP32 #2 ─┼── MQTT/TCP :1883 ──►┌──────────────┐
   ESP32 #N ─┘                     │  Mosquitto   │
                                   │  (broker)    │
   App Flutter ◄── MQTT/WS :9001 ──┤              │
   (web/móvil/desktop)             └──────┬───────┘
         │                                │ suscripción con comodín
         │                                ▼
         │                         ┌──────────────┐
         │                         │   ingesta    │  (paho-mqtt)
         │                         └──────┬───────┘
         │                                │ inserta
         │                                ▼
         │                         ┌──────────────┐
         └── REST :8001 ───────────┤   MongoDB    │◄── MongoDB Compass
            (historial)   FastAPI  └──────────────┘        :27017
```

**Por qué dos caminos hacia la app.** El tiempo real va directo del broker a la
app, así que la latencia es la del broker y el dashboard sigue mostrando datos
en vivo aunque Mongo o la API estén caídos. La API REST solo se usa al abrir la
app, para que las gráficas no empiecen vacías. Ese reparto es deliberado:
`ingesta` es el único proceso que escribe en la base de datos.

**Por qué MQTT sobre WebSocket en la app.** Un navegador no puede abrir sockets
TCP, así que Flutter Web necesita obligatoriamente WebSocket. Mosquitto expone
los dos listeners y la app usa el mismo (`:9001`) en las tres plataformas: un
solo camino que mantener.

---

## Requisitos

| Pieza | Versión usada | Para qué |
|---|---|---|
| Docker Desktop | 29.4 + Compose v5.1 | broker, base de datos y servicios |
| Flutter SDK | 3.44.5 (Dart 3.12.2) | app cliente |
| Arduino IDE | 2.x con paquete `esp32` | firmware del nodo |
| MongoDB Compass | cualquiera | inspección de datos (opcional) |

---

## Puesta en marcha

### 1. Levantar la infraestructura

```bash
cd infra
docker compose up -d --build
docker compose ps          # los 4 servicios deben estar Up
```

Esto arranca cuatro contenedores:

| Servicio | Contenedor | Puerto | Rol |
|---|---|---|---|
| `mosquitto` | `tg-mosquitto` | 1883, 9001 | broker MQTT (TCP + WebSocket) |
| `mongo` | `tg-mongo` | 27017 | almacenamiento |
| `ingesta` | `tg-ingesta` | — | suscriptor MQTT que persiste |
| `api` | `tg-api` | 8001 | API REST de historial |

Comprobación rápida:

```bash
curl http://localhost:8001/            # {"estado":"ok","mongodb":"conectado"}
docker compose logs -f ingesta         # debe mostrar cada lectura guardada
```

### 2. Poner nodos a publicar

**Opción A — ESP32 real.** Abre `arduino_ide/sensor/sensor.ino` en el Arduino IDE:

1. Instala las librerías desde el *Gestor de librerías*: **PubSubClient** y **ArduinoJson** (v7).
2. Selecciona la placa *ESP32 Dev Module*.
3. Edita solo estas líneas:

   ```cpp
   const char* WIFI_SSID     = "tu_red";
   const char* WIFI_PASSWORD = "tu_clave";
   const char* MQTT_HOST     = "10.103.180.103";   // IP de esta laptop
   ```

4. Sube el sketch. El monitor serie (115200 baudios) mostrará las publicaciones.

`NODO_ID` se deja vacío a propósito: el identificador se deriva de la MAC
(`esp32-a4cf12`). Así se flashea el **mismo binario en N placas** sin editar
nada y cada una aparece como un nodo distinto en el dashboard.

**Opción B — simulador (sin hardware).** Publica el mismo JSON en los mismos
tópicos, incluido el Last Will:

```bash
pip install paho-mqtt
python infra/servicios/herramientas/simulador_nodos.py --nodos 3
```

### 3. Lanzar la app

La IP del backend está en `lib/config/ajustes.dart` (por defecto
`10.103.180.103`) y se puede sobrescribir al compilar, sin tocar código:

```bash
# Web
flutter run -d chrome

# Windows / macOS / Linux
flutter run -d windows

# Móvil físico (misma red WiFi que la laptop)
flutter run -d <id-del-dispositivo>

# Emulador de Android: el host es 10.0.2.2, no la IP de la LAN
flutter run --dart-define=TG_HOST=10.0.2.2

# Otra red / otra máquina
flutter run --dart-define=TG_HOST=192.168.1.50
```

---

## Contrato de datos

Es el mismo de punta a punta. Cambiar un nombre obliga a cambiarlo en los tres
sitios: el sketch, `infra/servicios/comun/modelos.py` y `lib/modelos/`.

### Tópicos MQTT

| Tópico | Payload | Notas |
|---|---|---|
| `termic_guard/telemetria/<nodo>` | JSON de lectura | QoS 0, una cada 5 s |
| `termic_guard/estado/<nodo>` | `online` / `offline` | retenido; `offline` lo publica el broker como Last Will |

Los servicios se suscriben con comodín (`.../telemetria/+`), así que **añadir un
nodo no requiere configurar nada**: aparece solo en cuanto publica.

### JSON que envía el ESP32

```json
{
  "dispositivo": "esp32-a4cf12",
  "sensor1": 36.4,
  "sensor2": 39.1,
  "rssi": -58,
  "uptime_ms": 183400
}
```

Las temperaturas se generan con un paseo aleatorio acotado a **32.0 – 42.0 °C**
(salto máximo de 0.4 °C entre lecturas), de modo que la curva se parece a un
sensor real en vez de a ruido.

El nodo **no envía fecha**: el ESP32 no tiene reloj de tiempo real. La marca de
tiempo la pone `ingesta` al persistir, en UTC, y la app la convierte a hora
local. Para la vista en vivo la app usa la hora de llegada del mensaje.

### Colecciones en MongoDB

Base de datos: **`termic_guard`**

`lecturas` — serie temporal, un documento por publicación:

```json
{
  "_id": ObjectId("..."),
  "dispositivo": "sim-03",
  "sensor1": 32.2,
  "sensor2": 37.1,
  "fecha": ISODate("2026-10-22T00:34:10.110Z"),
  "rssi": -55,
  "uptime_ms": 14007
}
```

Índices: `fecha_desc` (historial global) y `dispositivo_fecha` (historial de un
nodo, que es lo que pide el dashboard).

`dispositivos` — estado actual de cada nodo, con `_id` = id del dispositivo,
de forma que los upserts son idempotentes y nunca se duplica un nodo:

```json
{
  "_id": "sim-03",
  "estado": "online",
  "vista_por_ultima_vez": ISODate("..."),
  "ultima_lectura": { "sensor1": 32.2, "sensor2": 37.1, "fecha": ISODate("...") },
  "primera_vez": ISODate("...")
}
```

---

## API REST

Documentación interactiva en **http://localhost:8001/docs**.

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/` | estado del servicio y de la conexión a Mongo |
| `GET` | `/lecturas?limite=50&dispositivo=esp32-01` | historial, **más reciente primero**; `limite` entre 1 y 1000, `dispositivo` opcional |
| `GET` | `/lecturas/ultima?dispositivo=esp32-01` | última lectura; 404 si no hay ninguna |
| `GET` | `/dispositivos` | nodos conocidos, su estado y su última lectura |

La API es de **solo lectura**: no hay forma de inyectar datos por HTTP, todo
entra por MQTT.

---

## MongoDB Compass

1. Cadena de conexión: `mongodb://localhost:27017`
2. Base de datos: `termic_guard`
3. Colecciones: `lecturas` y `dispositivos`

Para ver las últimas lecturas de un nodo, en la pestaña de la colección
`lecturas` usa el filtro `{ "dispositivo": "esp32-01" }` y ordena por
`{ "fecha": -1 }`.

---

## Estructura del proyecto

```
termic_guard/
├── arduino_ide/
│   └── sensor/sensor.ino          firmware del nodo (carpeta = nombre del .ino,
│                                  como exige el Arduino IDE)
├── infra/
│   ├── docker-compose.yml         los 4 servicios
│   ├── mosquitto/config/          configuración del broker (2 listeners)
│   └── servicios/                 un paquete Python, dos entrypoints
│       ├── comun/                 ajustes, contrato de datos y acceso a Mongo
│       │   ├── ajustes.py         URIs y tópicos, leídos del entorno
│       │   ├── modelos.py         validación de payloads y forma de la API
│       │   └── almacen.py         único módulo que conoce el esquema de Mongo
│       ├── ingesta/__main__.py    MQTT ──► MongoDB
│       ├── api/main.py            MongoDB ──► REST
│       └── herramientas/
│           └── simulador_nodos.py N nodos falsos para probar sin hardware
└── lib/                           app Flutter
    ├── config/                    ajustes.dart (IP, puertos, tópicos), paleta.dart
    ├── modelos/                   lectura.dart, nodo.dart  (inmutables)
    ├── servicios/
    │   ├── api_rest.dart          carga del historial
    │   └── mqtt/                  enlace en vivo
    │       ├── fabrica_cliente.dart   export condicional según plataforma
    │       ├── fabrica_nativa.dart    móvil y desktop
    │       ├── fabrica_web.dart       navegador
    │       └── mqtt_servicio.dart     suscripción, reconexión y parseo
    ├── estado/monitor_controlador.dart  fusiona REST + MQTT (ChangeNotifier)
    ├── pantallas/pantalla_monitor.dart  layout adaptativo
    └── widgets/                   tarjeta de nodo, gráfica, detalle, estado
```

La app no usa paquetes de gestión de estado: un `ChangeNotifier` y
`ListenableBuilder` bastan para una pantalla, y así no hay dependencias ni
generación de código que mantener.

---

## Cómo escala

- **Más nodos**: enciéndelos. Las suscripciones usan comodín y la app crea la
  tarjeta en cuanto llega el primer mensaje. No hay lista de nodos en ningún
  sitio.
- **Memoria acotada**: cada nodo conserva en la app una ventana deslizante de
  120 lecturas (`Ajustes.maxPuntosPorNodo`), así la RAM no crece con los días.
- **Reinicios sin pérdida**: `ingesta` se conecta con sesión persistente y QoS 1,
  de modo que si el contenedor se reinicia el broker le entrega lo que se perdió.
- **Nodo caído**: cuando un ESP32 pierde corriente o red, el broker publica su
  Last Will (`offline`) y el dashboard lo marca en rojo. Además, si un nodo deja
  de publicar durante más de 20 s, la app lo muestra como *Sin señal* aunque su
  último estado fuera `online`.

---

## Solución de problemas

| Síntoma | Causa habitual |
|---|---|
| La app dice **"Broker inalcanzable"** | La pila no está arriba (`docker compose ps`) o el firewall de Windows bloquea el puerto. Permite 1883, 9001, 8001 y 27017 para Docker en redes privadas. |
| Conecta pero **ningún nodo publica** | Ningún ESP32 encendido. Arranca el simulador para descartar problemas de app. |
| Funciona en web pero **no en el móvil** | El móvil debe estar en la misma WiFi y `TG_HOST` apuntar a la IP de la laptop (`10.103.180.103`), no a `localhost`. |
| Funciona en el móvil pero **no en el emulador** | En el emulador de Android la laptop es `10.0.2.2`: `flutter run --dart-define=TG_HOST=10.0.2.2`. |
| El ESP32 no conecta al broker | Revisa `MQTT_HOST` en el sketch y que la laptop no haya cambiado de IP (el DHCP la puede mover). |
| Sin red en una build **release de Android** | Ya está resuelto: el manifest principal incluye `INTERNET` y `usesCleartextTraffic`. Si lo regeneras, vuelve a añadirlos. |
| Sin red en **macOS desktop** | Añade `com.apple.security.network.client` a `macos/Runner/Release.entitlements`. |

Para empezar de cero (borra todos los datos):

```bash
cd infra
docker compose down -v
docker compose up -d --build
```

---

## Notas de seguridad

Esta configuración es un **perfil de desarrollo en LAN de confianza**:
Mosquitto acepta conexiones anónimas, Mongo no pide credenciales y CORS está
abierto. Antes de exponer cualquier puerto fuera de la red local hay que poner
`allow_anonymous false` con `password_file` en el broker, activar autenticación
en Mongo y restringir `allow_origins` en la API.

---

## Nota sobre `pyhton/`

La carpeta `pyhton/` es la primera versión del backend, en la que el ESP32
enviaba las lecturas por `POST` HTTP. Queda **sustituida** por `infra/` y no se
usa; puede borrarse cuando quieras.
