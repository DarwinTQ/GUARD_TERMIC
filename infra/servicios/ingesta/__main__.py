"""Puente MQTT -> MongoDB.

Se suscribe a los topicos de todos los nodos con un comodin, valida cada
payload y lo persiste. Es el unico proceso con permiso de escritura sobre
la base, asi que añadir nodos no requiere tocar nada: basta que publiquen
en `termic_guard/telemetria/<nodo>`.

Detalles que importan:
  * Sesion persistente (clean_session=False) + QoS 1: si este servicio se
    reinicia, el broker le guarda los mensajes y no se pierden lecturas.
  * El id del nodo se toma del topico, no del payload: un nodo mal
    configurado no puede escribir en la serie de otro.
"""

from __future__ import annotations

import json
import logging
import signal
import sys
import time
from types import FrameType

import paho.mqtt.client as mqtt
from pydantic import ValidationError

from comun.ajustes import AJUSTES, TOPICO_ESTADO, TOPICO_TELEMETRIA
from comun.almacen import Almacen
from comun.modelos import LecturaEntrante

ID_CLIENTE = "tg-ingesta"
ESTADOS_VALIDOS = {"online", "offline"}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("ingesta")


def esperar_mongo(almacen: Almacen, intentos: int = 30) -> None:
    for intento in range(1, intentos + 1):
        if almacen.ping():
            log.info("MongoDB disponible en %s", AJUSTES.mongo_uri)
            return
        log.warning("MongoDB no responde (%d/%d), reintento en 2 s", intento, intentos)
        time.sleep(2)
    raise SystemExit("No se pudo conectar a MongoDB")


def nodo_desde_topico(topico: str) -> str | None:
    """`termic_guard/telemetria/esp32-01` -> `esp32-01`."""
    partes = topico.split("/")
    return partes[2] if len(partes) == 3 and partes[2] else None


class Ingesta:
    def __init__(self, almacen: Almacen) -> None:
        self._almacen = almacen
        self._cliente = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=ID_CLIENTE,
            clean_session=False,  # el broker nos guarda los mensajes si caemos
        )
        if AJUSTES.mqtt_usuario:
            self._cliente.username_pw_set(AJUSTES.mqtt_usuario, AJUSTES.mqtt_clave)

        self._cliente.reconnect_delay_set(min_delay=1, max_delay=16)
        self._cliente.on_connect = self._al_conectar
        self._cliente.on_disconnect = self._al_desconectar
        self._cliente.on_message = self._al_recibir

    # ------------------------------------------------------------ callbacks

    def _al_conectar(self, cliente, _datos, _flags, codigo, _props=None) -> None:
        if codigo != 0:
            log.error("Conexion MQTT rechazada: %s", codigo)
            return
        log.info("Conectado a MQTT %s:%d", AJUSTES.mqtt_host, AJUSTES.mqtt_port)
        # Resuscribirse aqui (y no en run) cubre tambien las reconexiones.
        cliente.subscribe([(TOPICO_TELEMETRIA, 1), (TOPICO_ESTADO, 1)])
        log.info("Suscrito a %s y %s", TOPICO_TELEMETRIA, TOPICO_ESTADO)

    def _al_desconectar(self, _cliente, _datos, _flags, codigo, _props=None) -> None:
        if codigo != 0:
            log.warning("Desconectado de MQTT (%s); paho reintentara", codigo)

    def _al_recibir(self, _cliente, _datos, mensaje: mqtt.MQTTMessage) -> None:
        nodo = nodo_desde_topico(mensaje.topic)
        if nodo is None:
            log.warning("Topico ignorado: %s", mensaje.topic)
            return

        try:
            if "/telemetria/" in mensaje.topic:
                self._procesar_telemetria(nodo, mensaje.payload)
            elif "/estado/" in mensaje.topic:
                self._procesar_estado(nodo, mensaje.payload)
        except Exception:
            # Un payload corrupto no debe matar el bucle de ingesta.
            log.exception("Error procesando mensaje de %s", mensaje.topic)

    # ------------------------------------------------------------ procesado

    def _procesar_telemetria(self, nodo: str, payload: bytes) -> None:
        try:
            crudo = json.loads(payload)
        except json.JSONDecodeError:
            log.warning("[%s] payload no es JSON valido: %r", nodo, payload[:120])
            return

        if not isinstance(crudo, dict):
            log.warning("[%s] se esperaba un objeto JSON", nodo)
            return

        crudo["dispositivo"] = nodo  # el topico manda sobre el payload
        try:
            lectura = LecturaEntrante.model_validate(crudo)
        except ValidationError as error:
            log.warning("[%s] lectura descartada: %s", nodo, error.errors()[0]["msg"])
            return

        fecha = self._almacen.guardar_lectura(lectura)
        log.info(
            "[%s] %.1f C | %.1f C  -> guardado %s",
            nodo,
            lectura.sensor1,
            lectura.sensor2,
            fecha.strftime("%H:%M:%S"),
        )

    def _procesar_estado(self, nodo: str, payload: bytes) -> None:
        estado = payload.decode("utf-8", errors="replace").strip().lower()
        if estado not in ESTADOS_VALIDOS:
            log.warning("[%s] estado desconocido: %r", nodo, estado)
            return
        self._almacen.marcar_estado(nodo, estado)
        log.info("[%s] estado -> %s", nodo, estado)

    # ----------------------------------------------------------------- ciclo

    def ejecutar(self) -> None:
        self._cliente.connect(AJUSTES.mqtt_host, AJUSTES.mqtt_port, keepalive=30)
        self._cliente.loop_forever(retry_first_connection=True)

    def detener(self) -> None:
        self._cliente.disconnect()
        self._cliente.loop_stop()


def main() -> int:
    almacen = Almacen()
    esperar_mongo(almacen)
    almacen.asegurar_indices()

    ingesta = Ingesta(almacen)

    def apagar(_senal: int, _marco: FrameType | None) -> None:
        log.info("Apagando ingesta...")
        ingesta.detener()

    signal.signal(signal.SIGINT, apagar)
    signal.signal(signal.SIGTERM, apagar)

    try:
        ingesta.ejecutar()
    finally:
        almacen.cerrar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
