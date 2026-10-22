"""Simulador de N nodos ESP32 sobre MQTT (para probar sin hardware).

Publica exactamente el mismo JSON y en los mismos topicos que el firmware
`arduino_ide/sensor/sensor.ino`, incluido el Last Will, de modo que la
pila no distingue un nodo simulado de uno real.

Uso (con la pila levantada):
    pip install paho-mqtt
    python simulador_nodos.py --nodos 3
    python simulador_nodos.py --nodos 2 --host 10.103.180.103 --intervalo 2
"""

from __future__ import annotations

import argparse
import json
import random
import signal
import time

import paho.mqtt.client as mqtt

PREFIJO = "termic_guard"
TEMP_MIN, TEMP_MAX = 32.0, 42.0
PASO_MAX = 0.4

_corriendo = True


class NodoSimulado:
    """Mantiene su propio paseo aleatorio y su conexion MQTT."""

    def __init__(self, nodo_id: str, host: str, puerto: int) -> None:
        self.id = nodo_id
        self.topico_telemetria = f"{PREFIJO}/telemetria/{nodo_id}"
        self.topico_estado = f"{PREFIJO}/estado/{nodo_id}"
        self.sensor1 = random.uniform(TEMP_MIN, TEMP_MAX)
        self.sensor2 = random.uniform(TEMP_MIN, TEMP_MAX)
        self.inicio = time.time()

        self.cliente = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=nodo_id)
        self.cliente.will_set(self.topico_estado, "offline", qos=1, retain=True)
        self.cliente.connect(host, puerto, keepalive=30)
        self.cliente.loop_start()
        self.cliente.publish(self.topico_estado, "online", qos=1, retain=True)

    def _siguiente(self, actual: float) -> float:
        return min(TEMP_MAX, max(TEMP_MIN, actual + random.uniform(-PASO_MAX, PASO_MAX)))

    def publicar(self) -> None:
        self.sensor1 = self._siguiente(self.sensor1)
        self.sensor2 = self._siguiente(self.sensor2)
        payload = json.dumps(
            {
                "dispositivo": self.id,
                "sensor1": round(self.sensor1, 1),
                "sensor2": round(self.sensor2, 1),
                "rssi": random.randint(-75, -45),
                "uptime_ms": int((time.time() - self.inicio) * 1000),
            }
        )
        self.cliente.publish(self.topico_telemetria, payload, qos=0)
        print(f"[{self.id}] {payload}")

    def cerrar(self) -> None:
        self.cliente.publish(self.topico_estado, "offline", qos=1, retain=True)
        time.sleep(0.1)
        self.cliente.loop_stop()
        self.cliente.disconnect()


def main() -> None:
    parser = argparse.ArgumentParser(description="Simula nodos ESP32 por MQTT")
    parser.add_argument("--host", default="localhost", help="broker MQTT")
    parser.add_argument("--puerto", type=int, default=1883)
    parser.add_argument("--nodos", type=int, default=2, help="cuantos nodos simular")
    parser.add_argument("--intervalo", type=float, default=5.0, help="segundos")
    args = parser.parse_args()

    def apagar(*_):
        global _corriendo
        _corriendo = False

    signal.signal(signal.SIGINT, apagar)
    signal.signal(signal.SIGTERM, apagar)

    nodos = [
        NodoSimulado(f"sim-{i:02d}", args.host, args.puerto)
        for i in range(1, args.nodos + 1)
    ]
    print(f"Simulando {len(nodos)} nodo(s) cada {args.intervalo}s. Ctrl+C para parar.\n")

    try:
        while _corriendo:
            for nodo in nodos:
                nodo.publicar()
            time.sleep(args.intervalo)
    finally:
        for nodo in nodos:
            nodo.cerrar()
        print("\nNodos detenidos.")


if __name__ == "__main__":
    main()
