# TermicGuard — Documentación técnica

Monitorización de temperatura en tiempo real para una flota de nodos ESP32.
Este documento explica **cómo está hecho el software**: su arquitectura, su
modelo de datos, sus protocolos y las decisiones que explican por qué está
hecho así y no de otra forma.

> `README.md` es la guía de uso (cómo levantarlo y manejarlo).
> `CLAUDE.md` es la guía para modificarlo con seguridad.
> **Este documento es la referencia de diseño.**

Todos los diagramas están en Mermaid, así que se renderizan solos en GitHub,
GitLab, VS Code (extensión *Markdown Preview Mermaid*) y Obsidian.

---

## Índice

1. [Visión general](#1-visión-general)
2. [Mapa del repositorio](#2-mapa-del-repositorio)
3. [Arquitectura de software](#3-arquitectura-de-software)
4. [Arquitectura de red](#4-arquitectura-de-red)
5. [Arquitectura de despliegue](#5-arquitectura-de-despliegue)
6. [Modelo de datos](#6-modelo-de-datos)
7. [Contrato MQTT](#7-contrato-mqtt)
8. [API REST](#8-api-rest)
9. [Diagramas temporales](#9-diagramas-temporales)
10. [Máquinas de estado](#10-máquinas-de-estado)
11. [Arquitectura del cliente Flutter](#11-arquitectura-del-cliente-flutter)
12. [Métricas: qué se mide y cómo](#12-métricas-qué-se-mide-y-cómo)
13. [Decisiones de diseño](#13-decisiones-de-diseño)
14. [Operación y diagnóstico](#14-operación-y-diagnóstico)

---

## 1. Visión general

El sistema tiene **cuatro capas** y un principio que las atraviesa: *el
tiempo real y la persistencia son caminos independientes*. Si la base de
datos se cae, el dashboard sigue mostrando temperaturas; si el dashboard se
cierra, la ingesta sigue guardando.

```mermaid
flowchart LR
    subgraph campo["Campo"]
        N1["ESP32 nodo1"]
        N2["ESP32 nodo2"]
        NX["ESP32 nodo N"]
    end

    subgraph servidor["Laptop / servidor - Docker"]
        B["Mosquitto<br/>broker MQTT"]
        I["Ingesta<br/>Python"]
        DB[("MongoDB")]
        A["API REST<br/>FastAPI"]
    end

    subgraph cliente["Cliente"]
        APP["App Flutter<br/>web · escritorio · móvil"]
    end

    N1 -- "MQTT/TCP 1883" --> B
    N2 -- "MQTT/TCP 1883" --> B
    NX -- "MQTT/TCP 1883" --> B

    B -- "suscripción comodín" --> I
    I -- "insert" --> DB
    A -- "find / aggregate" --> DB

    B -. "MQTT/WebSocket 9001<br/>TIEMPO REAL" .-> APP
    A -- "HTTP 8001<br/>HISTORIAL" --> APP

    style B fill:#1098AD,color:#fff
    style DB fill:#7048E8,color:#fff
    style APP fill:#E8590C,color:#fff
```

| Capa | Qué hace | Dónde vive |
|------|----------|------------|
| **Firmware** | Publica dos temperaturas simuladas cada 5 s en JSON | `arduino_ide/sensor/sensor.ino` |
| **Broker** | Encamina mensajes; dos listeners (TCP y WebSocket) | `infra/mosquitto/` |
| **Backend** | `ingesta` persiste; `api` sirve lectura | `infra/servicios/` |
| **Cliente** | Dashboard multiplataforma | `lib/` |

**La línea de puntos es la clave del diseño.** La app no consulta la base de
datos para ver el tiempo real: se suscribe al broker directamente. La base de
datos solo aporta el histórico del arranque y la vista de datos.

---

## 2. Mapa del repositorio

```mermaid
flowchart TD
    R["termic_guard/"]

    R --> AR["arduino_ide/sensor/sensor.ino<br/><i>firmware del nodo</i>"]
    R --> IN["infra/"]
    R --> LIB["lib/"]
    R --> T["test/vistas_test.dart<br/><i>prueba de humo de las vistas</i>"]
    R --> PY["pyhton/<br/><i>backend de 1ª generación — obsoleto</i>"]

    IN --> DC["docker-compose.yml"]
    IN --> MO["mosquitto/config/mosquitto.conf"]
    IN --> SV["servicios/"]
    SV --> CO["comun/<br/>ajustes · almacen · modelos"]
    SV --> IG["ingesta/<br/>puente MQTT → Mongo"]
    SV --> AP["api/<br/>FastAPI de solo lectura"]
    SV --> HE["herramientas/simulador_nodos.py"]

    LIB --> CF["config/<br/>ajustes · paleta"]
    LIB --> MD["modelos/<br/>lectura · nodo · métricas · estadística · resumen_bd"]
    LIB --> SE["servicios/<br/>api_rest · mqtt/"]
    LIB --> ES["estado/<br/>monitor_controlador · explorador_bd"]
    LIB --> PA["pantallas/<br/>pantalla_principal + vistas/"]
    LIB --> WI["widgets/<br/>gráficos y piezas de UI"]
    LIB --> UT["util/formato.dart"]

    style PY stroke-dasharray: 5 5
```

`pyhton/` (con la errata en el nombre) es el backend original por HTTP. Está
**completamente superado** por `infra/` y nadie lo referencia.

---

## 3. Arquitectura de software

### 3.1 Componentes y responsabilidades

```mermaid
flowchart TB
    subgraph FW["Firmware · C++ / Arduino"]
        direction LR
        FW1["conectarWifi()"]
        FW2["conectarMqtt()<br/>+ Last Will"]
        FW3["publicarLectura()<br/>paseo aleatorio acotado"]
        FW1 --> FW2 --> FW3
    end

    subgraph BR["Broker · Mosquitto 2"]
        BR1["listener 1883<br/>protocol mqtt"]
        BR2["listener 9001<br/>protocol websockets"]
        BR3["retención de mensajes<br/>de estado"]
    end

    subgraph BE["Backend · Python 3"]
        direction LR
        subgraph COM["comun/ — núcleo compartido"]
            C1["ajustes.py<br/>config por entorno"]
            C2["modelos.py<br/>validación Pydantic<br/>+ serialización"]
            C3["almacen.py<br/>ÚNICO módulo que<br/>conoce el esquema"]
        end
        ING["ingesta/__main__.py<br/><b>único escritor</b>"]
        API["api/main.py<br/><b>solo lectura</b>"]
        ING --> C2 --> C3
        API --> C3
        C3 --> C1
    end

    subgraph CL["Cliente · Flutter / Dart"]
        direction TB
        CS["servicios/<br/>MqttServicio · ApiRest"]
        CE["estado/<br/>MonitorControlador · ExploradorBd"]
        CP["pantallas/ + widgets/"]
        CS --> CE --> CP
    end

    FW -->|publica| BR
    BR -->|entrega| ING
    BR <-->|suscribe + sonda| CS
    API -->|JSON| CS
```

**Regla de oro del backend:** `ingesta` es el único proceso con permiso de
escritura. `api` nunca escribe. Eso elimina de raíz las carreras entre
escritores y hace que el esquema solo pueda cambiar desde un sitio
(`almacen.py`).

### 3.2 Capas del cliente

```mermaid
flowchart TD
    V["Vistas<br/><i>VistaResumen, VistaNodos, VistaTiemposRespuesta,<br/>VistaTiemposLlegada, VistaBaseDatos, VistaSistema</i>"]
    W["Widgets reutilizables<br/><i>GraficoTemperaturas, GraficoLatencia, GraficoIntervalos,<br/>TarjetaKpi, TarjetaNodo, LeyendaSeries, Seccion</i>"]
    E["Estado<br/><i>MonitorControlador (ChangeNotifier)<br/>ExploradorBd (ChangeNotifier)</i>"]
    M["Modelos inmutables<br/><i>Lectura, Nodo, MetricasNodo, SerieLatencia,<br/>EstadisticaNodo, ResumenBd</i>"]
    S["Servicios<br/><i>MqttServicio, ApiRest</i>"]
    C["Configuración<br/><i>Ajustes, Paleta, Formato</i>"]

    V --> W
    V --> E
    W --> M
    E --> M
    E --> S
    S --> M
    V -.-> C
    W -.-> C
    E -.-> C
    S -.-> C

    style E fill:#7048E8,color:#fff
    style S fill:#1098AD,color:#fff
```

Las flechas van en un solo sentido: **ninguna capa inferior conoce a la
superior**. Un servicio no sabe que existe una vista; un modelo no sabe que
existe un controlador. Por eso el mismo `MonitorControlador` alimenta seis
vistas distintas sin cambiar una línea.

### 3.3 Modelo de clases del cliente

```mermaid
classDiagram
    class Ajustes {
        <<estático>>
        +String host
        +int puertoMqtt
        +int puertoApi
        +String topicoTelemetria
        +String topicoEstado
        +String topicoSonda
        +Duration refrescoVista
        +Duration intervaloSondeo
        +Duration intervaloNominalNodo
        +int maxPuntosPorNodo
    }

    class Lectura {
        <<inmutable>>
        +String? id
        +String dispositivo
        +double sensor1
        +double sensor2
        +DateTime fecha
        +int? rssi
        +double promedio
        +desdeApi(json)
        +desdeMqtt(json, dispositivo, recibida)
    }

    class Nodo {
        <<inmutable>>
        +String id
        +EstadoNodo estado
        +List~Lectura~ lecturas
        +Lectura? ultima
        +bool activo
        +conLectura(l) Nodo
        +copiarCon(...) Nodo
    }

    class MetricasNodo {
        +String nodo
        +int mensajes
        +DateTime? ultimaLlegada
        +Duration? promedio
        +Duration? jitter
        +Duration? p95
        +Duration? desvioNominal
        +int huecos
        +registrarLlegada(instante)
    }

    class SerieLatencia {
        +String nombre
        +List~MuestraLatencia~ muestras
        +double? ultimaMs
        +double? promedioMs
        +double? p95Ms
        +double? disponibilidad
        +agregar(muestra)
    }

    class MuestraLatencia {
        <<inmutable>>
        +DateTime instante
        +Duration? duracion
        +String? detalle
        +bool ok
    }

    class MqttServicio {
        +Stream~EventoMqtt~ eventos
        +Stream~EstadoConexion~ conexion
        +conectar()
        +sondear() MuestraLatencia
        +liberar()
    }

    class ApiRest {
        +historialPorNodo()
        +estadoDeNodos()
        +lecturas(limite, desplazamiento, dispositivo)
        +estadisticas(horas)
        +resumenBd()
        +sondear() MuestraLatencia
    }

    class MonitorControlador {
        <<ChangeNotifier>>
        +List~Nodo~ nodos
        +SerieLatencia latenciaApi
        +SerieLatencia latenciaBroker
        +VentanaTiempo ventana
        +iniciar()
        +refrescar()
        +metricasDe(id) MetricasNodo
        +lecturasVisibles(nodo) List~Lectura~
    }

    class ExploradorBd {
        <<ChangeNotifier>>
        +ResumenBd? resumen
        +List~EstadisticaNodo~ estadisticas
        +List~Lectura~ lecturas
        +cargar()
        +paginaSiguiente()
        +filtrarPor(dispositivo)
    }

    MonitorControlador --> MqttServicio
    MonitorControlador --> ApiRest
    MonitorControlador --> Nodo
    MonitorControlador --> MetricasNodo
    MonitorControlador --> SerieLatencia
    ExploradorBd --> ApiRest
    Nodo o-- Lectura
    SerieLatencia o-- MuestraLatencia
    MqttServicio ..> Ajustes
    ApiRest ..> Ajustes
```

---

## 4. Arquitectura de red

```mermaid
flowchart TB
    subgraph wifi["Red WiFi local — 2.4 GHz"]
        direction TB

        subgraph nodos["Nodos ESP32 — clientes DHCP"]
            E1["nodo1<br/>PubSubClient<br/>keepalive 15 s"]
            E2["nodo2<br/>PubSubClient<br/>keepalive 15 s"]
        end

        subgraph host["Host 10.137.195.103 — Windows + Docker Desktop"]
            direction TB
            FWALL["Firewall de Windows<br/>reglas de entrada<br/>1883 · 9001 · 8001"]

            subgraph red_docker["Red bridge termic-guard_default"]
                MQ["tg-mosquitto<br/>:1883 :9001"]
                MG["tg-mongo<br/>:27017"]
                IG["tg-ingesta<br/>sin puertos publicados"]
                AP["tg-api<br/>:8001"]
            end
        end

        subgraph clientes["Clientes del dashboard"]
            WEB["Navegador<br/>Flutter web"]
            WIN["App escritorio<br/>Windows"]
            MOV["App móvil<br/>Android"]
        end
    end

    E1 -->|"TCP 1883"| FWALL
    E2 -->|"TCP 1883"| FWALL
    FWALL --> MQ

    MQ <-->|"interno :1883"| IG
    IG -->|"interno :27017"| MG
    AP -->|"interno :27017"| MG

    WEB -->|"WS 9001 + HTTP 8001"| FWALL
    WIN -->|"WS 9001 + HTTP 8001"| FWALL
    MOV -->|"WS 9001 + HTTP 8001"| FWALL
    FWALL --> AP

    style FWALL fill:#F08C00,color:#000
    style MQ fill:#1098AD,color:#fff
    style MG fill:#7048E8,color:#fff
```

### Puertos

| Puerto | Protocolo | Quién lo usa | Publicado al host |
|--------|-----------|--------------|-------------------|
| `1883` | MQTT sobre TCP | ESP32 | Sí |
| `9001` | MQTT sobre WebSocket | App Flutter (todas las plataformas) | Sí |
| `8001` | HTTP / REST | App Flutter, navegador, `curl` | Sí |
| `27017` | Wire protocol de MongoDB | MongoDB Compass | Sí |

**Dos listeners porque son dos protocolos.** Un navegador no puede abrir un
socket TCP; está obligado a usar WebSocket. Para no mantener dos caminos de
código en la app, **todas** las plataformas usan WebSocket — la elección de
implementación la hace `lib/servicios/mqtt/fabrica_cliente.dart` con una
exportación condicional sobre `dart.library.js_interop`.

### Por qué el firewall aparece en el diagrama

Es el fallo más frecuente del sistema. Desde el propio host todo funciona
(`localhost` no atraviesa el firewall), así que el síntoma típico es "en mi
PC va pero en el móvil no". Las tres reglas de entrada son obligatorias.

---

## 5. Arquitectura de despliegue

```mermaid
flowchart LR
    subgraph compose["docker compose — proyecto termic-guard"]
        direction TB

        MQ["<b>tg-mosquitto</b><br/>eclipse-mosquitto:2<br/>restart: unless-stopped"]
        MG["<b>tg-mongo</b><br/>mongo:7<br/>healthcheck: ping"]
        IG["<b>tg-ingesta</b><br/>build ./servicios<br/>python -m ingesta"]
        AP["<b>tg-api</b><br/>build ./servicios<br/>uvicorn api.main:app"]

        V1[("mongo-datos")]
        V2[("mosquitto-datos")]
        V3[("mosquitto-log")]
        CF["./mosquitto/config/<br/>mosquitto.conf<br/><i>montado :ro</i>"]

        MG -.-> V1
        MQ -.-> V2
        MQ -.-> V3
        CF -.-> MQ

        IG ==>|depends_on<br/>service_healthy| MG
        IG ==>|depends_on<br/>service_started| MQ
        AP ==>|depends_on<br/>service_healthy| MG
    end

    style IG fill:#0CA678,color:#fff
    style AP fill:#7048E8,color:#fff
```

**Una imagen, dos entrypoints.** `ingesta` y `api` se construyen del mismo
`infra/servicios/Dockerfile` y solo difieren en el `command`. Comparten el
paquete `comun/`, de modo que el modelo de datos no puede divergir entre el
que escribe y el que lee.

**El orden de arranque importa.** `ingesta` espera a que Mongo esté *healthy*
(no solo arrancado) y además reintenta 30 veces en `esperar_mongo()`. Con
Mosquitto basta `service_started`: si el broker aún no acepta, paho reintenta
solo con backoff de 1 a 16 s.

---

## 6. Modelo de datos

### 6.1 Diagrama entidad-relación

MongoDB no es relacional, pero la relación lógica entre las dos colecciones
es exactamente esta:

```mermaid
erDiagram
    DISPOSITIVOS ||--o{ LECTURAS : "publica"

    DISPOSITIVOS {
        string id PK "_id = id del nodo, ej. nodo1"
        string estado "online u offline"
        date vista_por_ultima_vez "se actualiza en cada lectura"
        date primera_vez "setOnInsert, no se sobrescribe"
        object ultima_lectura "copia desnormalizada"
    }

    LECTURAS {
        ObjectId id PK "_id generado por Mongo"
        string dispositivo FK "indice compuesto con fecha"
        double sensor1 "grados C, validado -50 a 150"
        double sensor2 "grados C, validado -50 a 150"
        date fecha "UTC, la pone el servidor"
        int rssi "dBm, opcional"
        int uptime_ms "opcional"
    }
```

### 6.2 Documentos reales

```javascript
// colección: lecturas
{
  _id:         ObjectId("6ae26925df4b9f131eb1e9d8"),
  dispositivo: "nodo1",
  sensor1:     38.2,
  sensor2:     40.6,
  fecha:       ISODate("2026-10-28T21:29:09.240Z"),  // UTC, del servidor
  rssi:        -51,
  uptime_ms:   1843210
}

// colección: dispositivos   (_id = id del nodo ⇒ upsert idempotente)
{
  _id:                   "nodo1",
  estado:                "online",
  vista_por_ultima_vez:  ISODate("2026-10-28T21:29:09.240Z"),
  primera_vez:           ISODate("2026-10-22T01:13:45.912Z"),
  ultima_lectura: { sensor1: 38.2, sensor2: 40.6,
                    fecha: ISODate("2026-10-28T21:29:09.240Z") }
}
```

### 6.3 Índices y por qué existen

```mermaid
flowchart LR
    subgraph lecturas["colección lecturas"]
        I1["<b>_id_</b><br/>_id:1<br/><i>automático</i>"]
        I2["<b>fecha_desc</b><br/>fecha:-1"]
        I3["<b>dispositivo_fecha</b><br/>dispositivo:1, fecha:-1"]
    end

    Q1["GET /lecturas<br/>sin filtro"] --> I2
    Q2["GET /lecturas<br/>?dispositivo=nodo1"] --> I3
    Q3["GET /estadisticas<br/>$group por dispositivo"] --> I3
    Q4["GET /lecturas/ultima"] --> I2

    style I2 fill:#0CA678,color:#fff
    style I3 fill:#0CA678,color:#fff
```

| Índice | Consulta que cubre |
|--------|--------------------|
| `fecha_desc` | historial global ordenado por fecha descendente |
| `dispositivo_fecha` | historial de un nodo concreto y la agregación por nodo |

Sin `dispositivo_fecha`, filtrar por nodo obligaría a un *collection scan*
completo y la vista de base de datos se degradaría a medida que crece la
serie. `asegurar_indices()` es idempotente y se llama en cada arranque de
los dos servicios.

### 6.4 Por qué `dispositivos` desnormaliza la última lectura

`ultima_lectura` duplica datos que ya están en `lecturas`. Es deliberado: el
endpoint `/dispositivos` responde el estado de toda la flota con **una sola
lectura de dos documentos**, sin tocar la serie temporal. El coste de la
duplicación es un `$set` extra por inserción; el beneficio es que el panel de
estado no depende del tamaño del historial.

---

## 7. Contrato MQTT

```mermaid
flowchart TB
    subgraph topicos["Espacio de nombres: termic_guard/"]
        T1["<b>termic_guard/telemetria/{nodo}</b><br/>JSON · QoS 0 · sin retener<br/><i>publica el ESP32</i>"]
        T2["<b>termic_guard/estado/{nodo}</b><br/>online | offline<br/>QoS 1 · <b>RETENIDO</b> · Last Will<br/><i>publica el ESP32 y el broker</i>"]
        T3["<b>termic_guard/sonda/app</b><br/>id de sonda · QoS 0<br/><i>solo la app; eco para medir RTT</i>"]
    end

    ESP["ESP32"] --> T1
    ESP --> T2
    MOS["Mosquitto<br/><i>al expirar el keepalive</i>"] --> T2

    T1 --> ING["ingesta<br/>+/telemetria/+"]
    T2 --> ING
    T1 --> APP["app Flutter"]
    T2 --> APP
    T3 <--> APP

    style T3 stroke-dasharray: 5 5
```

### Payload de telemetría

```json
{
  "dispositivo": "nodo1",
  "sensor1": 38.2,
  "sensor2": 40.6,
  "rssi": -51,
  "uptime_ms": 1843210
}
```

**No lleva fecha, y es a propósito.** El ESP32 no tiene reloj de tiempo real:
cualquier fecha que enviara sería inventada. La fecha autoritativa la pone
`ingesta` al persistir (`ahora_utc()`), y para la vista en vivo la app usa la
hora de llegada del mensaje.

### Tres reglas que no se pueden romper

1. **La identidad viene del tópico, no del payload.** `ingesta` sobrescribe
   `payload["dispositivo"]` con el segmento del tópico antes de validar. Un
   nodo mal configurado no puede escribir en la serie de otro.
2. **Suscripción con comodín, sin registro de nodos.** Todo el sistema usa
   `termic_guard/telemetria/+`. Añadir un ESP32 es encenderlo: aparece solo.
3. **Los tres strings están duplicados** en firmware (C++), backend (Python)
   y cliente (Dart) por necesidad del lenguaje. Si cambia uno, cambian los
   tres.

### QoS: por qué cada tópico lleva el suyo

| Tópico | QoS | Razón |
|--------|-----|-------|
| telemetría (ESP32 → broker) | 0 | Llega una lectura cada 5 s; reintentar una perdida no aporta y gasta batería y RAM del nodo |
| telemetría (broker → ingesta) | 1 | La ingesta sí debe recibir todo; con `clean_session=False` el broker le guarda los mensajes si se reinicia |
| estado / LWT | 1 + retenido | Un cliente que se conecta después debe enterarse igual del último estado conocido |
| sonda | 0 | Mide el camino rápido; un reintento falsearía la medición |

---

## 8. API REST

Base: `http://10.137.195.103:8001` · Documentación interactiva: `/docs`

| Método | Ruta | Parámetros | Devuelve |
|--------|------|-----------|----------|
| `GET` | `/` | — | Estado del servicio y de la conexión a Mongo |
| `GET` | `/lecturas` | `limite` (1-1000), `dispositivo`, `desplazamiento` | Lecturas **más reciente primero** |
| `GET` | `/lecturas/total` | `dispositivo` | `{"total": n}` para paginar |
| `GET` | `/lecturas/ultima` | `dispositivo` | Última lectura registrada |
| `GET` | `/dispositivos` | — | Nodos conocidos y su estado |
| `GET` | `/estadisticas` | `horas` (1-8760) | Agregados por nodo calculados por Mongo |
| `GET` | `/bd/resumen` | — | Colecciones, documentos, tamaño e índices |

**`/lecturas` devuelve de más nueva a más antigua y el cliente lo invierte**,
porque las gráficas necesitan tiempo creciente mientras que una consulta de
historial quiere lo último primero. `Nodo.lecturas` siempre va de antigua a
reciente. Cambiar cualquiera de los dos extremos rompe las gráficas en
silencio.

CORS está abierto (`allow_origins=["*"]`, solo `GET`) porque Flutter web se
sirve desde otro origen. Es un perfil de LAN; para exponerlo fuera hay que
restringirlo y quitar el acceso anónimo del broker.

---

## 9. Diagramas temporales

### 9.1 Camino completo de una lectura

```mermaid
sequenceDiagram
    autonumber
    participant E as ESP32 nodo1
    participant M as Mosquitto
    participant I as Ingesta
    participant D as MongoDB
    participant A as App Flutter

    Note over E: loop() cada INTERVALO_MS = 5000 ms

    E->>E: siguienteTemperatura()<br/>paseo aleatorio acotado
    E->>M: PUBLISH termic_guard/telemetria/nodo1<br/>{"sensor1":38.2,"sensor2":40.6,...} QoS 0

    par Camino de persistencia
        M->>I: entrega QoS 1
        I->>I: nodo_desde_topico() → "nodo1"
        I->>I: crudo["dispositivo"] = "nodo1"<br/><b>el tópico manda</b>
        I->>I: LecturaEntrante.model_validate()
        alt payload válido
            I->>D: insert_one(lecturas)<br/>fecha = ahora_utc()
            I->>D: update_one(dispositivos, upsert)<br/>estado=online + ultima_lectura
            D-->>I: ok
            I->>I: log "[nodo1] 38.2 C | 40.6 C → guardado"
        else payload corrupto
            I->>I: log warning y descarta<br/><b>el bucle no muere</b>
        end
    and Camino de tiempo real
        M-->>A: entrega por WebSocket QoS 0
        A->>A: Lectura.desdeMqtt(fecha = hora de llegada)
        A->>A: Nodo.conLectura() → recorta a 120 puntos
        A->>A: MetricasNodo.registrarLlegada()
        A->>A: notifyListeners() → repinta
    end

    Note over D,A: Los dos caminos son independientes:<br/>si Mongo cae, la app sigue en vivo
```

### 9.2 Arranque de la aplicación

```mermaid
sequenceDiagram
    autonumber
    participant U as Usuario
    participant P as PantallaPrincipal
    participant C as MonitorControlador
    participant R as ApiRest
    participant Q as MqttServicio
    participant M as Mosquitto

    U->>P: abre la app
    P->>C: new + iniciar()

    rect rgb(240, 240, 250)
        Note over C,R: Fase 1 — historial, para no arrancar con gráficas vacías
        C->>R: GET /lecturas?limite=300
        R-->>C: 300 lecturas → agrupadas por nodo, invertidas
        C->>R: GET /dispositivos
        R-->>C: estado de cada nodo
        alt la API no responde
            C->>C: avisoHistorial = "Sin historial..."<br/><b>sigue adelante</b>
        end
    end

    rect rgb(240, 250, 245)
        Note over C,M: Fase 2 — tiempo real
        C->>Q: conectar()
        Q->>M: CONNECT ws://host:9001<br/>clientId único por instancia
        M-->>Q: CONNACK
        Q->>M: SUBSCRIBE telemetria/+ (QoS 0)
        Q->>M: SUBSCRIBE estado/+ (QoS 1)
        Q->>M: SUBSCRIBE sonda/app (QoS 0)
        M-->>Q: mensajes de estado RETENIDOS
        Q-->>C: EventoEstadoNodo por cada nodo conocido
    end

    rect rgb(250, 245, 240)
        Note over C: Fase 3 — temporizadores
        C->>C: Timer.periodic(1 s) → repinta<br/><i>mueve el eje temporal</i>
        C->>C: Timer.periodic(5 s) → sondea latencias
        C->>C: primer sondeo inmediato
    end

    C-->>P: notifyListeners()
    P-->>U: dashboard con datos
```

### 9.3 Medición de latencias

Las dos sondas se lanzan en paralelo para que midan el mismo instante y una
lenta no retrase a la otra.

```mermaid
sequenceDiagram
    autonumber
    participant C as MonitorControlador
    participant R as ApiRest
    participant A as FastAPI
    participant Q as MqttServicio
    participant M as Mosquitto

    Note over C: cada 5 s — Future.wait([...])

    par Sonda HTTP
        C->>R: sondear()
        R->>R: Stopwatch start
        R->>A: GET /
        A->>A: ping a MongoDB
        A-->>R: 200 {"estado":"ok"}
        R->>R: Stopwatch stop
        R-->>C: MuestraLatencia(12.4 ms)
    and Sonda MQTT — eco de ida y vuelta
        C->>Q: sondear()
        Q->>Q: id = "sonda-<micros>"<br/>Stopwatch start
        Q->>M: PUBLISH termic_guard/sonda/app<br/>payload = id
        M-->>Q: el broker devuelve el mensaje<br/>(estamos suscritos a ese tópico)
        Q->>Q: Stopwatch stop → completa el Completer
        Q-->>C: MuestraLatencia(3.1 ms)
    end

    C->>C: latenciaApi.agregar(...)<br/>latenciaBroker.agregar(...)
    C->>C: notifyListeners()

    Note over Q,M: Si no llega eco en 3 s → MuestraLatencia.fallida<br/>Un fallo es una muestra, no un hueco silencioso
```

**Por qué el eco y no un ping de protocolo.** El RTT medido así atraviesa
exactamente el mismo camino que una lectura real: WebSocket, encolado en
Mosquitto y entrega al suscriptor. Un `PINGREQ` de MQTT mediría solo la capa
de transporte y no detectaría un broker con las colas saturadas.

### 9.4 Caída de un nodo

```mermaid
sequenceDiagram
    autonumber
    participant E as ESP32 nodo2
    participant M as Mosquitto
    participant I as Ingesta
    participant A as App

    Note over E,M: Al conectar, el nodo ya registró su testamento:<br/>LWT → estado/nodo2 = "offline", retenido

    E->>M: PUBLISH estado/nodo2 "online" (retenido)
    loop cada 5 s
        E->>M: telemetría
        M-->>A: lectura → Nodo.activo = true
    end

    Note over E: ⚡ se corta la alimentación

    rect rgb(255, 245, 240)
        Note over A: t + 20 s — Ajustes.tiempoSinSenal
        A->>A: el Timer de 1 s reevalúa Nodo.activo
        A->>A: sin lecturas recientes → activo = false
        A-->>A: la tarjeta pasa a gris "Sin señal"
    end

    rect rgb(255, 235, 235)
        Note over M: t + 30 s — expira el keepalive
        M->>M: el cliente no respondió al PINGREQ
        M->>M: publica el Last Will
        M-->>I: estado/nodo2 = "offline"
        I->>I: marcar_estado("nodo2", "offline")
        M-->>A: EventoEstadoNodo(nodo2, desconectado)
        A-->>A: la tarjeta pasa a rojo "Desconectado"
    end
```

**Los dos umbrales son distintos a propósito** y por eso el dashboard tiene
tres estados y no dos: hay una ventana de ~10 s en la que la app ya sabe que
algo va mal (*Sin señal*) pero el broker todavía no lo ha confirmado
(*Desconectado*). Esa ventana es información útil, no un bug.

---

## 10. Máquinas de estado

### 10.1 Vitalidad de un nodo

```mermaid
stateDiagram-v2
    [*] --> Desconocido : nodo visto por primera vez

    Desconocido --> EnLinea : llega una lectura
    Desconocido --> Desconectado : LWT retenido = offline

    EnLinea --> SinSenal : sin lecturas durante<br/>Ajustes.tiempoSinSenal (20 s)
    SinSenal --> EnLinea : llega una lectura
    SinSenal --> Desconectado : el broker publica el LWT<br/>(keepalive 30 s)

    EnLinea --> Desconectado : LWT = offline
    Desconectado --> EnLinea : llega una lectura<br/><i>una publicación demuestra que está vivo,<br/>aunque el LWT dijera otra cosa</i>

    note right of SinSenal
        Dice "online" pero no publica.
        Gris en el dashboard.
    end note
```

La vitalidad son **dos señales, no una**: `dispositivos.estado` (el LWT) y la
frescura de la última lectura. `Nodo.activo` exige las dos; `Paleta.deNodo()`
y `Paleta.etiquetaDeNodo()` pintan el resultado de tres valores.

### 10.2 Enlace MQTT del cliente

```mermaid
stateDiagram-v2
    [*] --> Desconectado

    Desconectado --> Conectando : conectar()
    Conectando --> Conectado : CONNACK + suscripciones
    Conectando --> Error : excepción o CONNACK negativo

    Conectado --> Conectando : onAutoReconnect<br/><i>autoReconnect = true</i>
    Conectado --> Desconectado : desconectar() / dispose()

    Error --> Conectando : refrescar() desde la UI
    Desconectado --> Conectando : refrescar() desde la UI

    note left of Error
        Pinta "Broker inalcanzable".
        Las sondas devuelven
        MuestraLatencia.fallida.
    end note
```

### 10.3 Ciclo de vida del firmware

```mermaid
stateDiagram-v2
    [*] --> Setup

    Setup --> ConectandoWiFi : nodoId = NODO_ID o MAC
    ConectandoWiFi --> ConectandoWiFi : reintenta cada 400 ms
    ConectandoWiFi --> ConectandoMQTT : WiFi lista

    ConectandoMQTT --> ConectandoMQTT : fallo → espera 3 s<br/><i>sin bloquear el loop</i>
    ConectandoMQTT --> Publicando : CONNACK + "online" retenido

    Publicando --> Publicando : cada 5 s publica
    Publicando --> ConectandoMQTT : se pierde el broker
    Publicando --> ConectandoWiFi : se pierde la WiFi

    note right of ConectandoMQTT
        El reintento no bloquea:
        vuelve al loop() y
        reintenta al siguiente ciclo.
    end note
```

---

## 11. Arquitectura del cliente Flutter

### 11.1 Navegación

```mermaid
flowchart TD
    MAIN["main()<br/>AppTermicGuard"] --> PP["PantallaPrincipal<br/><i>dueña de los dos controladores</i>"]

    PP --> MENU["Menú lateral"]

    MENU --> G1["<b>Monitorización</b>"]
    G1 --> V1["Resumen<br/><i>KPIs + rejilla de nodos + salud del enlace</i>"]
    G1 --> V2["Nodos en vivo<br/><i>gráfica de eje temporal deslizante</i>"]

    MENU --> G2["<b>Rendimiento</b>"]
    G2 --> V3["Tiempos de respuesta<br/><i>latencia API y RTT broker</i>"]
    G2 --> V4["Tiempos de llegada<br/><i>cadencia, jitter y huecos por nodo</i>"]

    MENU --> G3["<b>Datos y sistema</b>"]
    G3 --> V5["Base de datos<br/><i>colecciones, agregados y tabla paginada</i>"]
    G3 --> V6["Sistema<br/><i>configuración efectiva y diagnóstico</i>"]

    V1 -.->|"toca un nodo"| V2

    style PP fill:#1864AB,color:#fff
```

**Adaptación por ancho:** ≥1000 px menú extendido con texto · ≥760 px menú de
iconos · por debajo, cajón lateral (*drawer*) con botón hamburguesa.

**Los controladores viven en `PantallaPrincipal`, no en las vistas.** Cambiar
de pestaña no reconecta el broker ni pierde el histórico acumulado: las seis
vistas son lecturas distintas del mismo estado.

### 11.2 Flujo de datos y repintado

```mermaid
flowchart TB
    subgraph entradas["Entradas"]
        MQ["MqttServicio<br/>Stream&lt;EventoMqtt&gt;"]
        AR["ApiRest<br/>Future&lt;...&gt;"]
        T1["Timer 1 s<br/><i>refrescoVista</i>"]
        T2["Timer 5 s<br/><i>intervaloSondeo</i>"]
    end

    MC["<b>MonitorControlador</b><br/>Map&lt;String, Nodo&gt;<br/>Map&lt;String, MetricasNodo&gt;<br/>SerieLatencia × 2"]

    MQ -->|EventoLectura<br/>EventoEstadoNodo| MC
    AR -->|historial inicial| MC
    T1 -->|notifyListeners| MC
    T2 -->|sondas| MC

    MC -->|ListenableBuilder| UI["Vista activa"]

    subgraph ebd["Carga bajo demanda"]
        EB["<b>ExploradorBd</b><br/>cliente HTTP propio"]
    end

    EB -->|ListenableBuilder| VBD["VistaBaseDatos"]

    style MC fill:#7048E8,color:#fff
    style EB fill:#0CA678,color:#fff
```

**Por qué el repintado a 1 Hz.** La gráfica tiene el eje X anclado a `ahora`:
sin un tick periódico, la ventana solo avanzaría cuando llegara una lectura y
un nodo caído dejaría la gráfica congelada en lugar de mostrar el hueco
creciendo. El mismo tick reevalúa `Nodo.activo` y los "hace N s".

**Por qué `ExploradorBd` está separado.** Una consulta a Mongo no puede
bloquear el tiempo real ni refrescarse a 1 Hz. Se carga la primera vez que se
abre su vista y se queda quieta hasta que el usuario pide otra página. Usa su
propio cliente HTTP para que una consulta lenta no ocupe la conexión que usa
el monitor para sondear.

### 11.3 Memoria acotada

```mermaid
flowchart LR
    L["Lectura nueva"] --> CL["Nodo.conLectura()"]
    CL --> C{"¿length > 120?"}
    C -->|sí| T["sublist(exceso)<br/>descarta las más antiguas"]
    C -->|no| K["conserva todas"]
    T --> N["<b>nuevo</b> Nodo inmutable"]
    K --> N
    N --> UI["la UI lee una lista<br/>que nunca está a medio mutar"]
```

| Estructura | Límite | Constante |
|------------|--------|-----------|
| Lecturas por nodo | 120 puntos | `Ajustes.maxPuntosPorNodo` |
| Muestras de latencia | 120 por serie (≈10 min) | `Ajustes.maxMuestrasLatencia` |
| Intervalos por nodo | 60 huecos | `Ajustes.maxIntervalosPorNodo` |

Con 10 nodos la app estabiliza en unos pocos MB y no crece con el tiempo de
ejecución. `Nodo` es inmutable y se reemplaza entero en cada evento, así que
la UI nunca lee una lista a medio modificar.

---

## 12. Métricas: qué se mide y cómo

### 12.1 Tiempos de respuesta

| Métrica | Definición | Dónde se calcula |
|---------|-----------|------------------|
| **Latencia API** | `GET /` completo, incluido el ping a Mongo | `ApiRest.sondear()` |
| **RTT broker** | PUBLISH → eco del broker al mismo cliente | `MqttServicio.sondear()` |
| **p95** | Percentil 95 de la ventana de 120 muestras | `SerieLatencia.percentil()` |
| **Disponibilidad** | `(muestras − fallos) / muestras × 100` | `SerieLatencia.disponibilidad` |

Umbrales de color, calibrados para LAN (`Paleta.deLatencia`):

| Rango | Estado |
|-------|--------|
| < 150 ms | Buena |
| 150–500 ms | Lenta |
| ≥ 500 ms o sin respuesta | Crítica |

**Un fallo es una muestra.** Si una sonda no responde se guarda como
`MuestraLatencia.fallida` y deja un hueco visible en la gráfica. Descartarla
bajaría la latencia media justo cuando el sistema va peor.

### 12.2 Tiempos de llegada

```mermaid
flowchart LR
    M1["mensaje n-1<br/>t = 10.00 s"] -->|"hueco"| M2["mensaje n<br/>t = 15.08 s"]
    M2 --> D["intervalo = 5.08 s"]
    D --> N{"¿> 1.8 × nominal?<br/>(> 9 s)"}
    N -->|sí| H["cuenta como <b>hueco</b><br/><i>probable pérdida: QoS 0 no reintenta</i>"]
    N -->|no| OK["intervalo normal"]
```

| Métrica | Qué delata |
|---------|-----------|
| **Media** | El ritmo real frente al nominal de 5 s del firmware |
| **Desvío nominal** | `media − 5 s`. Positivo = el nodo va lento |
| **Jitter** | Desviación media absoluta. Alto = la red entrega a ráfagas aunque la media parezca bien |
| **p95** | El hueco que sufre 1 de cada 20 mensajes |
| **Huecos** | Intervalos > 1,8 × nominal ⇒ mensajes perdidos |

**Solo cuenta el tráfico en vivo.** El historial que viene de la API lleva la
fecha que puso el servidor al persistir, no la de llegada a la app; mezclar
las dos falsearía los intervalos. Por eso `MetricasNodo.registrarLlegada()`
se invoca únicamente desde el flujo MQTT.

### 12.3 Agregados de la base de datos

`GET /estadisticas` ejecuta un `$group` **en el servidor**, no en el cliente:

```javascript
[
  { $match: { fecha: { $gte: desde } } },        // opcional, parámetro horas
  { $group: {
      _id: "$dispositivo",
      lecturas:     { $sum: 1 },
      sensor1_min:  { $min: "$sensor1" },
      sensor1_max:  { $max: "$sensor1" },
      sensor1_prom: { $avg: "$sensor1" },
      // ... ídem sensor2 y rssi
      primera:      { $min: "$fecha" },
      ultima:       { $max: "$fecha" }
  }},
  { $sort: { _id: 1 } }
]
```

`intervalo_medio_s = (ultima − primera) / (lecturas − 1)`: el periodo real de
publicación medido sobre lo persistido.

> **Estos números no coinciden con los del dashboard, y está bien.** La app
> guarda 120 puntos por nodo; Mongo agrega sobre la serie completa. El máximo
> de `/estadisticas` es el máximo histórico real; el de la vista de nodos es
> el de la ventana que estás mirando.

---

## 13. Decisiones de diseño

Cada una resuelve un problema concreto. Cambiarlas sin entender el problema
rompe algo que hoy funciona.

| # | Decisión | Problema que resuelve |
|---|----------|----------------------|
| 1 | **Dos caminos de datos** (MQTT en vivo + REST histórico) | Mongo o la API caídos no deben apagar el dashboard. Degrada a "solo en vivo, con banda de aviso" |
| 2 | **Siempre WebSocket**, también en escritorio y móvil | El navegador no puede usar TCP. Un solo listener y un solo camino de código para las cuatro plataformas |
| 3 | **Suscripción con comodín, sin registro de nodos** | Añadir un ESP32 no requiere configurar nada en ningún sitio |
| 4 | **La identidad viene del tópico** | Un nodo mal configurado no puede contaminar la serie de otro |
| 5 | **La fecha la pone el servidor** | El ESP32 no tiene RTC; cualquier fecha suya sería inventada |
| 6 | **`ingesta` es el único escritor** | Sin carreras entre escritores; el esquema solo cambia desde `almacen.py` |
| 7 | **Ventana deslizante de 120 puntos** | Memoria acotada: la app no crece con el tiempo de ejecución |
| 8 | **`Nodo` inmutable, reemplazado entero** | La UI nunca lee una lista a medio mutar |
| 9 | **Vitalidad = LWT + frescura** | Un nodo puede decir "online" y haber dejado de publicar |
| 10 | **Configuración por `--dart-define` / variables de entorno** | Cambiar de IP no obliga a tocar código |
| 11 | **Eje X temporal, no por índice** | Un nodo que se calla deja un hueco visible en vez de dibujar una línea continua falsa |
| 12 | **Múltiplos pequeños en el resumen** | Una gráfica con N series obligaría a inventar colores cuando entra un nodo nuevo y a repintar los demás cuando uno se cae |
| 13 | **Sonda de eco para el RTT** | Recorre el mismo camino que una lectura real; un `PINGREQ` solo mediría el transporte |
| 14 | **`ExploradorBd` separado del monitor** | Una consulta a Mongo no puede frenar el tiempo real |
| 15 | **Paleta validada para daltonismo** | Las series se distinguen sin depender del color; además siempre hay leyenda y tabla |

### Sobre la paleta

| Uso | Color | Nota |
|-----|-------|------|
| Sensor 1 | `#E8590C` naranja | Par validado: ΔE ≥ 19 en protan/deutan/tritan |
| Sensor 2 | `#1098AD` cian | |
| API REST | `#7048E8` violeta | Par distinto del de temperatura a propósito |
| Broker MQTT | `#0CA678` verde azulado | |
| En línea / alerta / caído | `#2F9E44` / `#F08C00` / `#E03131` | **Reservados**: nunca se usan como color de serie |

Los colores de estado siempre van con icono y etiqueta de texto. El valor
numérico se pinta en color de texto, nunca en el de la serie: quien lleva la
identidad es la marca de color que va al lado.

### Lo que está mal a propósito (perfil de LAN)

- `allow_anonymous true` en Mosquitto: **sin autenticación**.
- CORS abierto en la API.
- MongoDB sin credenciales y con el puerto publicado.

Es un perfil de desarrollo en red local de confianza. Para exponerlo fuera
hacen falta `password_file` en el broker, TLS en los tres puertos,
autenticación en Mongo y CORS restringido.

---

## 14. Operación y diagnóstico

### Levantar y comprobar

```bash
cd infra
docker compose up -d --build
docker compose ps                   # 4 servicios: mosquitto, mongo, ingesta, api
docker compose logs -f ingesta      # cada lectura persistida, en vivo
docker compose down -v              # reinicio total, borra todos los datos
```

```bash
flutter pub get
flutter analyze                     # debe salir limpio
flutter test                        # prueba de humo de las seis vistas
flutter run -d chrome
flutter run -d windows
flutter run --dart-define=TG_HOST=10.0.2.2    # emulador de Android
```

Simulador de nodos, que publica el mismo JSON en los mismos tópicos que el
firmware real:

```bash
python infra/servicios/herramientas/simulador_nodos.py --nodos 3
```

> Si lo lanzas dentro de un contenedor, ese contenedor **sigue vivo** aunque
> interrumpas el comando. Comprueba `docker ps | grep sim` antes de fiarte de
> una prueba de caída: un simulador olvidado mantiene un nodo "online".

### Árbol de diagnóstico

```mermaid
flowchart TD
    S["El dashboard no muestra datos"] --> Q1{"¿Qué dice la<br/>barra superior?"}

    Q1 -->|"Broker inalcanzable"| B1{"¿docker compose ps<br/>muestra 4 servicios?"}
    B1 -->|no| F1["docker compose up -d"]
    B1 -->|sí| B2{"¿Desde otro equipo<br/>de la red?"}
    B2 -->|sí| F2["Firewall: abrir 1883, 9001 y 8001<br/>en el perfil de red actual"]
    B2 -->|no| F3["Comprueba TG_HOST:<br/>¿cambió la IP por DHCP?"]

    Q1 -->|"MQTT en vivo,<br/>0 nodos"| C1{"¿Hay alguien<br/>publicando?"}
    C1 -->|no| F4["Enciende un ESP32 o lanza<br/>simulador_nodos.py"]
    C1 -->|sí| F5["Monitor serie a 115200:<br/>¿sale [mqtt] ok?<br/>rc=-2 ⇒ firewall o IP"]

    Q1 -->|"En vivo pero sin<br/>historial"| D1["La API o Mongo están caídos.<br/>Vista Sistema → fila API REST"]
    D1 --> F6["docker compose logs api"]

    style F2 fill:#F08C00,color:#000
    style F3 fill:#F08C00,color:#000
```

La **vista Sistema** de la app muestra la configuración efectiva de esa
compilación (host, puertos, tópicos y parámetros) con el estado de cada
enlace. Es la primera pantalla que hay que mirar cuando alguien dice "no
conecta": evita adivinar contra qué IP se construyó el binario.

### Cambiar de IP

La app se reapunta sin tocar código:

```bash
flutter run   --dart-define=TG_HOST=192.168.1.50
flutter build web --release --dart-define=TG_HOST=192.168.1.50
```

El firmware sí hay que reflashearlo (`MQTT_HOST` en `sensor.ino`). Si la red
es DHCP, conviene reservar la IP en el router: cuando expira el *lease*, los
nodos dejan de encontrar el broker.

---

*Documento de diseño de TermicGuard. Para uso diario, `README.md`; para
modificar el código con seguridad, `CLAUDE.md`.*
