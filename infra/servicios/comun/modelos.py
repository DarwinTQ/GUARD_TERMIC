"""Contrato de datos compartido entre el ESP32, Mongo y la app Flutter.

`LecturaEntrante` valida lo que llega por MQTT; `a_json` define la forma
exacta que consume la app. Cambiar un nombre aqui obliga a cambiarlo en
`lib/modelos/` del cliente Flutter.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field

# Margen generoso: filtra basura (NaN, sensor desconectado) sin asumir el
# rango exacto del firmware.
TEMP_MINIMA_VALIDA = -50.0
TEMP_MAXIMA_VALIDA = 150.0


class LecturaEntrante(BaseModel):
    """Payload JSON publicado por un nodo ESP32."""

    dispositivo: str = Field(min_length=1, max_length=64)
    sensor1: float = Field(ge=TEMP_MINIMA_VALIDA, le=TEMP_MAXIMA_VALIDA)
    sensor2: float = Field(ge=TEMP_MINIMA_VALIDA, le=TEMP_MAXIMA_VALIDA)
    rssi: int | None = None
    uptime_ms: int | None = None


def lectura_a_json(doc: dict[str, Any]) -> dict[str, Any]:
    """Documento de Mongo -> JSON de la API."""
    return {
        "id": str(doc["_id"]),
        "dispositivo": doc.get("dispositivo", ""),
        "sensor1": doc["sensor1"],
        "sensor2": doc["sensor2"],
        "fecha": _iso(doc["fecha"]),
        "rssi": doc.get("rssi"),
    }


def dispositivo_a_json(doc: dict[str, Any]) -> dict[str, Any]:
    """Documento de la coleccion `dispositivos` -> JSON de la API."""
    return {
        "dispositivo": doc["_id"],
        "estado": doc.get("estado", "desconocido"),
        "vista_por_ultima_vez": _iso(doc.get("vista_por_ultima_vez")),
        "ultima_lectura": (
            {
                "sensor1": doc["ultima_lectura"]["sensor1"],
                "sensor2": doc["ultima_lectura"]["sensor2"],
                "fecha": _iso(doc["ultima_lectura"]["fecha"]),
            }
            if doc.get("ultima_lectura")
            else None
        ),
    }


def estadistica_a_json(doc: dict[str, Any]) -> dict[str, Any]:
    """Resultado del `$group` de `Almacen.estadisticas` -> JSON de la API.

    `intervalo_medio_s` es el periodo real de publicacion del nodo medido
    sobre lo persistido: con N lecturas hay N-1 huecos entre la primera y
    la ultima. Permite comparar el ritmo real con el nominal del firmware
    sin que la app tenga que recalcularlo.
    """
    lecturas = doc.get("lecturas", 0)
    primera = doc.get("primera")
    ultima = doc.get("ultima")

    intervalo = None
    if lecturas > 1 and isinstance(primera, datetime) and isinstance(ultima, datetime):
        intervalo = (ultima - primera).total_seconds() / (lecturas - 1)

    return {
        "dispositivo": doc["_id"],
        "lecturas": lecturas,
        "sensor1": _resumen_sensor(doc, "sensor1"),
        "sensor2": _resumen_sensor(doc, "sensor2"),
        "rssi_prom": _redondear(doc.get("rssi_prom"), 1),
        "primera": _iso(primera),
        "ultima": _iso(ultima),
        "intervalo_medio_s": _redondear(intervalo, 2),
    }


def _resumen_sensor(doc: dict[str, Any], sensor: str) -> dict[str, Any]:
    return {
        "minimo": _redondear(doc.get(f"{sensor}_min"), 1),
        "maximo": _redondear(doc.get(f"{sensor}_max"), 1),
        "promedio": _redondear(doc.get(f"{sensor}_prom"), 2),
    }


def _redondear(valor: float | None, decimales: int) -> float | None:
    return round(valor, decimales) if isinstance(valor, (int, float)) else None


def _iso(valor: datetime | None) -> str | None:
    return valor.isoformat() if isinstance(valor, datetime) else None
