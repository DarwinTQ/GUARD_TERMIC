"""API REST de solo lectura.

La app Flutter la usa para cargar el historial al abrirse; el tiempo real
va por MQTT/WebSocket directo al broker. Este servicio nunca escribe:
quien persiste es el servicio de ingesta.

Documentacion interactiva: http://<host>:8001/docs
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import timedelta

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from comun.almacen import Almacen, ahora_utc
from comun.modelos import dispositivo_a_json, estadistica_a_json, lectura_a_json

_almacen: Almacen | None = None


def obtener_almacen() -> Almacen:
    if _almacen is None:  # pragma: no cover - solo si se usa fuera del lifespan
        raise HTTPException(status_code=503, detail="Almacen no inicializado")
    return _almacen


@asynccontextmanager
async def ciclo_vida(_app: FastAPI):
    global _almacen
    _almacen = Almacen()
    _almacen.asegurar_indices()
    yield
    _almacen.cerrar()
    _almacen = None


app = FastAPI(
    title="TermicGuard API",
    description="Historial de temperaturas de los nodos ESP32",
    version="2.0.0",
    lifespan=ciclo_vida,
)

# La app web se sirve desde otro origen (o desde file://), asi que CORS abierto.
# Perfil de LAN local; restringir si se publica fuera.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


@app.get("/", summary="Estado del servicio")
def estado(almacen: Almacen = Depends(obtener_almacen)) -> dict:
    conectado = almacen.ping()
    return {
        "estado": "ok" if conectado else "degradado",
        "mongodb": "conectado" if conectado else "sin conexion",
    }


@app.get("/lecturas", summary="Historial de lecturas (mas reciente primero)")
def listar_lecturas(
    limite: int = Query(50, ge=1, le=1000),
    dispositivo: str | None = Query(None, description="Filtra por un nodo concreto"),
    desplazamiento: int = Query(0, ge=0, description="Saltar N lecturas (paginacion)"),
    almacen: Almacen = Depends(obtener_almacen),
) -> list[dict]:
    return [
        lectura_a_json(d)
        for d in almacen.historial(limite, dispositivo, desplazamiento)
    ]


@app.get("/lecturas/total", summary="Numero de lecturas almacenadas")
def total_lecturas(
    dispositivo: str | None = Query(None),
    almacen: Almacen = Depends(obtener_almacen),
) -> dict:
    return {"total": almacen.contar_lecturas(dispositivo)}


@app.get("/lecturas/ultima", summary="Ultima lectura registrada")
def ultima_lectura(
    dispositivo: str | None = Query(None),
    almacen: Almacen = Depends(obtener_almacen),
) -> dict:
    doc = almacen.ultima(dispositivo)
    if doc is None:
        raise HTTPException(status_code=404, detail="Aun no hay lecturas")
    return lectura_a_json(doc)


@app.get("/dispositivos", summary="Nodos conocidos y su estado")
def listar_dispositivos(almacen: Almacen = Depends(obtener_almacen)) -> list[dict]:
    return [dispositivo_a_json(d) for d in almacen.listar_dispositivos()]


@app.get("/estadisticas", summary="Agregados por nodo sobre la serie completa")
def listar_estadisticas(
    horas: int | None = Query(
        None,
        ge=1,
        le=8760,
        description="Limita el calculo a las ultimas N horas; sin valor, todo el historico",
    ),
    almacen: Almacen = Depends(obtener_almacen),
) -> list[dict]:
    desde = ahora_utc() - timedelta(hours=horas) if horas else None
    return [estadistica_a_json(d) for d in almacen.estadisticas(desde)]


@app.get("/bd/resumen", summary="Colecciones, indices y tamaño de la base")
def resumen_bd(almacen: Almacen = Depends(obtener_almacen)) -> dict:
    return almacen.resumen_bd()
