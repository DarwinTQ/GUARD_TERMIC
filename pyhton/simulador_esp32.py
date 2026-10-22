"""
Simulador del ESP32 (para probar sin la placa)
----------------------------------------------
Envía temperaturas falsas al servidor cada 5 segundos, igual que lo haría el ESP32.
Útil para probar MongoDB Compass y la app Flutter antes de tener el hardware listo.

Ejecutar (con el servidor ya corriendo):
    python simulador_esp32.py
"""

import random
import time

import requests

URL = "http://localhost:8001/lecturas"  

t1, t2 = 24.0, 26.0
while True:
    t1 = round(t1 + random.uniform(-0.3, 0.3), 2)
    t2 = round(t2 + random.uniform(-0.3, 0.3), 2)
    try:
        r = requests.post(URL, json={"dispositivo": "simulador", "sensor1": t1, "sensor2": t2}, timeout=5)
        print(f"Enviado {t1} °C | {t2} °C -> {r.status_code}")
    except requests.RequestException as e:
        print("Error: ¿está corriendo el servidor?", e)
    time.sleep(5)
