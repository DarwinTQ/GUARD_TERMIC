"""Acceso a MongoDB. Unico modulo que conoce el esquema de la base.

Colecciones
-----------
lecturas      : serie temporal de temperaturas (una por publicacion MQTT).
dispositivos  : estado actual de cada nodo, con `_id` = id del dispositivo,
                de modo que los upserts son idempotentes y sin duplicados.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Iterable

from pymongo import ASCENDING, DESCENDING, MongoClient
from pymongo.collection import Collection
from pymongo.database import Database

from .ajustes import AJUSTES
from .modelos import LecturaEntrante


def ahora_utc() -> datetime:
    """Marca de tiempo del servidor: el ESP32 no tiene reloj de tiempo real."""
    return datetime.now(timezone.utc)


class Almacen:
    """Repositorio sobre MongoDB. Instanciar una vez por proceso."""

    def __init__(self, uri: str | None = None, base_datos: str | None = None) -> None:
        self._cliente: MongoClient = MongoClient(
            uri or AJUSTES.mongo_uri,
            tz_aware=True,
            serverSelectionTimeoutMS=5000,
        )
        self._bd: Database = self._cliente[base_datos or AJUSTES.base_datos]

    # ---------------------------------------------------------------- setup

    @property
    def lecturas(self) -> Collection:
        return self._bd["lecturas"]

    @property
    def dispositivos(self) -> Collection:
        return self._bd["dispositivos"]

    def asegurar_indices(self) -> None:
        """Idempotente: se puede llamar en cada arranque."""
        # Historial global, mas reciente primero.
        self.lecturas.create_index([("fecha", DESCENDING)], name="fecha_desc")
        # Historial filtrado por nodo: lo que pide el dashboard por dispositivo.
        self.lecturas.create_index(
            [("dispositivo", ASCENDING), ("fecha", DESCENDING)],
            name="dispositivo_fecha",
        )

    def ping(self) -> bool:
        try:
            self._cliente.admin.command("ping")
            return True
        except Exception:
            return False

    def cerrar(self) -> None:
        self._cliente.close()

    # -------------------------------------------------------------- escritura

    def guardar_lectura(self, lectura: LecturaEntrante) -> datetime:
        """Inserta la lectura y refresca el resumen del nodo.

        Devuelve la fecha asignada por el servidor.
        """
        fecha = ahora_utc()
        documento: dict[str, Any] = {
            "dispositivo": lectura.dispositivo,
            "sensor1": lectura.sensor1,
            "sensor2": lectura.sensor2,
            "fecha": fecha,
        }
        if lectura.rssi is not None:
            documento["rssi"] = lectura.rssi
        if lectura.uptime_ms is not None:
            documento["uptime_ms"] = lectura.uptime_ms

        self.lecturas.insert_one(documento)

        # Una lectura implica que el nodo esta vivo, aunque su LWT dijese otra cosa.
        self.dispositivos.update_one(
            {"_id": lectura.dispositivo},
            {
                "$set": {
                    "estado": "online",
                    "vista_por_ultima_vez": fecha,
                    "ultima_lectura": {
                        "sensor1": lectura.sensor1,
                        "sensor2": lectura.sensor2,
                        "fecha": fecha,
                    },
                },
                "$setOnInsert": {"primera_vez": fecha},
            },
            upsert=True,
        )
        return fecha

    def marcar_estado(self, dispositivo: str, estado: str) -> None:
        """Registra el online/offline que publica el Last Will del nodo."""
        self.dispositivos.update_one(
            {"_id": dispositivo},
            {
                "$set": {"estado": estado, "vista_por_ultima_vez": ahora_utc()},
                "$setOnInsert": {"primera_vez": ahora_utc()},
            },
            upsert=True,
        )

    # --------------------------------------------------------------- lectura

    def historial(self, limite: int = 50, dispositivo: str | None = None) -> list[dict]:
        """Lecturas mas recientes primero (el cliente invierte para graficar)."""
        filtro = {"dispositivo": dispositivo} if dispositivo else {}
        cursor = self.lecturas.find(filtro).sort("fecha", DESCENDING).limit(limite)
        return list(cursor)

    def ultima(self, dispositivo: str | None = None) -> dict | None:
        filtro = {"dispositivo": dispositivo} if dispositivo else {}
        return self.lecturas.find_one(filtro, sort=[("fecha", DESCENDING)])

    def listar_dispositivos(self) -> Iterable[dict]:
        return self.dispositivos.find().sort("_id", ASCENDING)
