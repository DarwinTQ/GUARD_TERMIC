# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Real-time temperature monitoring for a fleet of ESP32 nodes. Four tiers, all in this repo:

1. **Firmware** — `arduino_ide/sensor/sensor.ino`. Publishes two simulated temperatures (32–42 °C random walk) as JSON over MQTT every 5 s.
2. **Broker** — Mosquitto with two listeners: `1883` (TCP, for ESP32s) and `9001` (WebSocket, for the app).
3. **Backend** — `infra/servicios/`: one Python package, two entrypoints. `ingesta` subscribes to MQTT and writes to MongoDB; `api` serves read-only history over REST.
4. **Client** — `lib/`, a single Flutter app targeting mobile, desktop and web.

`README.md` documents the whole system for users (in Spanish); this file covers what you need to change it safely.

User-facing text, identifiers, and comments are **Spanish** (`lectura`, `dispositivo`, `fecha`, `ajustes`, `almacen`, `ingesta`). Match it — don't introduce English names alongside.

## Commands

Infrastructure (Docker Desktop must be running):

```bash
cd infra
docker compose up -d --build
docker compose ps                   # 4 services: mosquitto, mongo, ingesta, api
docker compose logs -f ingesta      # live view of every reading persisted
docker compose down -v              # reset, wipes all data
```

Flutter (from repo root):

```bash
flutter pub get
flutter analyze                     # currently clean — keep it that way
flutter run -d chrome               # web
flutter run -d windows              # desktop
flutter run --dart-define=TG_HOST=10.0.2.2   # Android emulator
flutter build web --release
flutter test                        # no tests exist yet (test/ is empty)
flutter test test/x_test.dart --plain-name 'some test'   # single test, once tests exist
```

Node simulator — publishes the same JSON on the same topics as real firmware, so the stack can't tell the difference:

```bash
python infra/servicios/herramientas/simulador_nodos.py --nodos 3
```

To run it without installing anything on the host, reuse the ingest image (it already has `paho-mqtt`) and join the compose network:

```bash
MSYS_NO_PATHCONV=1 docker run --rm --network termic-guard_default \
  -v "D:/Flutter_projects/first_/termic_guard/infra/servicios/herramientas:/t:ro" \
  termic-guard-ingesta python /t/simulador_nodos.py --host mosquitto --nodos 3
```

Note: that container keeps running if the invoking command is interrupted. Check `docker ps | grep sim` before trusting a test that depends on who's publishing — a leftover simulator silently keeps a node "online".

## Architecture notes

**Two data paths into the app, on purpose.** Live telemetry goes broker → app directly over WebSocket; history comes from the REST API only at startup. So the dashboard keeps showing live data when Mongo or the API are down, and `ingesta` stays the single writer to the database. `MonitorControlador` (`lib/estado/`) is where the two merge — it's the only place that decides what the UI sees, and it degrades to "live only, with a warning banner" rather than failing.

**The app always speaks MQTT over WebSocket**, never raw TCP, on every platform. Browsers can't open TCP sockets, so web forces WebSocket; using `:9001` everywhere means one listener and one code path. `lib/servicios/mqtt/fabrica_cliente.dart` picks the implementation with a conditional export on `dart.library.js_interop` (`MqttServerClient` + `useWebSocket` for native, `MqttBrowserClient` for web). **Changes there need both targets rebuilt** — `flutter analyze` alone won't catch a platform-specific break. `flutter build web` and `flutter build windows` both currently pass.

**Wildcard subscriptions everywhere, no node registry.** Services subscribe to `termic_guard/telemetria/+`; the app creates a card when a node's first message arrives. Adding an ESP32 requires zero configuration. Preserve that when touching subscriptions: don't introduce a list of known devices.

**Node identity comes from the topic, not the payload.** `ingesta` overwrites `payload["dispositivo"]` with the node segment from the topic before validating, so a misconfigured node can't write into another's series. The firmware leaves `NODO_ID` empty and derives `esp32-<mac>` so the same binary flashes to N boards.

**Timestamps.** Nodes send no date — the ESP32 has no RTC. `ingesta` stamps `fecha` in UTC on insert; the app converts with `.toLocal()`. For live MQTT points the app uses arrival time, since the authoritative date only exists after persistence. Don't "fix" this by having the firmware send a time.

**`GET /lecturas` returns newest-first.** The REST client reverses it, because charts need increasing time. `Nodo.lecturas` is always oldest→newest. Changing either end breaks the charts silently.

**Bounded memory.** Each node keeps a sliding window of `Ajustes.maxPuntosPorNodo` (120) readings in the app; `Nodo.conLectura` trims as it appends. `Nodo` is immutable and replaced wholesale on each event, so the UI never reads a half-mutated list.

**Liveness is two signals, not one.** `dispositivos.estado` comes from the retained LWT topic (`online`/`offline`), but a node can say `online` and stop publishing. `Nodo.activo` also requires a reading within `Ajustes.tiempoSinSenal` (20 s), and `Paleta.deNodo`/`etiquetaDeNodo` render the three-way result. Mosquitto only fires the will after the keepalive (30 s) elapses — allow for that when testing offline detection.

**Config is centralized and build-overridable.** `lib/config/ajustes.dart` holds host, ports and topics via `String.fromEnvironment`, so `--dart-define=TG_HOST=…` retargets a build with no code edit. Default is the dev laptop, `10.103.180.103`. Python side mirrors this in `infra/servicios/comun/ajustes.py` (env vars). MQTT topic strings are duplicated across firmware, Python and Dart by necessity — change all three together.

**Android networking is already patched.** `android/app/src/main/AndroidManifest.xml` carries `INTERNET` (Flutter's template only puts it in the debug manifest, so release builds had no network) and `usesCleartextTraffic="true"` (API 28+ blocks `http://` and `ws://` by default). If you regenerate the manifest, re-add both or the app silently fails on device.

## Legacy

`pyhton/` is the first-generation backend, where the ESP32 POSTed readings over HTTP. It is fully superseded by `infra/` and nothing references it. Safe to delete; don't extend it.
