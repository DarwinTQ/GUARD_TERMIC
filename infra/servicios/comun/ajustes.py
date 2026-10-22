"""Configuracion central de los servicios, leida del entorno.

Un unico sitio donde viven URIs, topicos y nombres de colecciones: los
servicios no vuelven a tocar os.getenv por su cuenta.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

PREFIJO_TOPICO = "termic_guard"

# Comodin MQTT de un nivel: captura todos los nodos sin listarlos.
TOPICO_TELEMETRIA = f"{PREFIJO_TOPICO}/telemetria/+"
TOPICO_ESTADO = f"{PREFIJO_TOPICO}/estado/+"


@dataclass(frozen=True, slots=True)
class Ajustes:
    mongo_uri: str
    base_datos: str
    mqtt_host: str
    mqtt_port: int
    mqtt_usuario: str | None
    mqtt_clave: str | None

    @staticmethod
    def desde_entorno() -> "Ajustes":
        return Ajustes(
            mongo_uri=os.getenv("MONGO_URI", "mongodb://localhost:27017"),
            base_datos=os.getenv("MONGO_DB", "termic_guard"),
            mqtt_host=os.getenv("MQTT_HOST", "localhost"),
            mqtt_port=int(os.getenv("MQTT_PORT", "1883")),
            mqtt_usuario=os.getenv("MQTT_USUARIO") or None,
            mqtt_clave=os.getenv("MQTT_CLAVE") or None,
        )


AJUSTES = Ajustes.desde_entorno()
