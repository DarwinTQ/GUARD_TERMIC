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

    def historial(
        self,
        limite: int = 50,
        dispositivo: str | None = None,
        desplazamiento: int = 0,
    ) -> list[dict]:
        """Lecturas mas recientes primero (el cliente invierte para graficar).

        `desplazamiento` pagina hacia atras en el tiempo: la vista de base de
        datos recorre la tabla sin traerse la coleccion entera.
        """
        filtro = {"dispositivo": dispositivo} if dispositivo else {}
        cursor = (
            self.lecturas.find(filtro)
            .sort("fecha", DESCENDING)
            .skip(desplazamiento)
            .limit(limite)
        )
        return list(cursor)

    def contar_lecturas(self, dispositivo: str | None = None) -> int:
        filtro = {"dispositivo": dispositivo} if dispositivo else {}
        return self.lecturas.count_documents(filtro)

    def ultima(self, dispositivo: str | None = None) -> dict | None:
        filtro = {"dispositivo": dispositivo} if dispositivo else {}
        return self.lecturas.find_one(filtro, sort=[("fecha", DESCENDING)])

    def listar_dispositivos(self) -> Iterable[dict]:
        return self.dispositivos.find().sort("_id", ASCENDING)

    # ------------------------------------------------------------ agregados

    def estadisticas(self, desde: datetime | None = None) -> list[dict]:
        """Resumen por nodo calculado en el servidor, no en el cliente.

        Mongo agrega sobre toda la serie; la app solo guarda una ventana de
        120 puntos, asi que estos minimos y maximos son los reales, no los
        de lo que hay en pantalla.

        El indice `dispositivo_fecha` cubre el $match por fecha y el $group.
        """
        etapas: list[dict[str, Any]] = []
        if desde is not None:
            etapas.append({"$match": {"fecha": {"$gte": desde}}})
        etapas.append(
            {
                "$group": {
                    "_id": "$dispositivo",
                    "lecturas": {"$sum": 1},
                    "sensor1_min": {"$min": "$sensor1"},
                    "sensor1_max": {"$max": "$sensor1"},
                    "sensor1_prom": {"$avg": "$sensor1"},
                    "sensor2_min": {"$min": "$sensor2"},
                    "sensor2_max": {"$max": "$sensor2"},
                    "sensor2_prom": {"$avg": "$sensor2"},
                    "rssi_prom": {"$avg": "$rssi"},
                    "primera": {"$min": "$fecha"},
                    "ultima": {"$max": "$fecha"},
                }
            }
        )
        etapas.append({"$sort": {"_id": ASCENDING}})
        return list(self.lecturas.aggregate(etapas))

    def resumen_bd(self) -> dict:
        """Metadatos de la base para la vista de base de datos del dashboard.

        `collStats` no existe en todos los despliegues (Atlas serverless lo
        restringe), asi que el tamaño es opcional: el conteo y los indices
        se obtienen siempre.
        """
        colecciones = []
        for nombre in ("lecturas", "dispositivos"):
            coleccion = self._bd[nombre]
            info: dict[str, Any] = {
                "nombre": nombre,
                "documentos": coleccion.count_documents({}),
                "indices": [
                    {
                        "nombre": clave,
                        "campos": [
                            f"{campo}:{orden}" for campo, orden in valor["key"]
                        ],
                    }
                    for clave, valor in coleccion.index_information().items()
                ],
                "bytes": None,
                "bytes_indices": None,
            }
            try:
                estadisticas = self._bd.command("collstats", nombre)
                info["bytes"] = estadisticas.get("size")
                info["bytes_indices"] = estadisticas.get("totalIndexSize")
            except Exception:  # pragma: no cover - depende del despliegue
                pass
            colecciones.append(info)

        return {
            "base_datos": self._bd.name,
            "servidor": self._version_servidor(),
            "colecciones": colecciones,
        }

    def _version_servidor(self) -> str | None:
        try:
            return self._cliente.server_info().get("version")
        except Exception:  # pragma: no cover - Mongo caido
            return None
