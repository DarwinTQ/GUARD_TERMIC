"""
Servidor local IoT - Temperaturas ESP32
----------------------------------------
- POST /lecturas         -> el ESP32 envía las temperaturas y se guardan en MongoDB
- GET  /lecturas         -> la app Flutter consulta el historial
- GET  /lecturas/ultima  -> la app Flutter consulta la última lectura
- Documentación automática (para probar y para la presentación): http://localhost:8000/docs

Ejecutar:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

import os
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from pymongo import DESCENDING, MongoClient

# En local usa localhost; en Docker se cambia por variable de entorno
MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")

cliente = MongoClient(MONGO_URI, tz_aware=True)
coleccion = cliente["iot_temperaturas"]["lecturas"]
coleccion.create_index([("fecha", DESCENDING)])

app = FastAPI(title="API Temperaturas ESP32")

# Permite que la app (o una web) consuma la API sin bloqueos
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class LecturaEntrada(BaseModel):
    dispositivo: str = "esp32-01"
    sensor1: float
    sensor2: float


def a_json(doc) -> dict:
    return {
        "id": str(doc["_id"]),
        "dispositivo": doc.get("dispositivo"),
        "sensor1": doc["sensor1"],
        "sensor2": doc["sensor2"],
        "fecha": doc["fecha"].isoformat(),
    }


@app.get("/")
def estado():
    return {"estado": "ok", "mensaje": "API de temperaturas funcionando"}


@app.post("/lecturas", status_code=201)
def guardar_lectura(lectura: LecturaEntrada):
    # La fecha la pone el servidor (el ESP32 no tiene reloj real)
    doc = lectura.model_dump()
    doc["fecha"] = datetime.now(timezone.utc)
    resultado = coleccion.insert_one(doc)
    print(f"Guardado: {lectura.sensor1} °C | {lectura.sensor2} °C")
    return {"id": str(resultado.inserted_id)}


@app.get("/lecturas")
def listar_lecturas(limite: int = Query(50, ge=1, le=1000)):
    docs = coleccion.find().sort("fecha", DESCENDING).limit(limite)
    return [a_json(d) for d in docs]


@app.get("/lecturas/ultima")
def ultima_lectura():
    doc = coleccion.find_one(sort=[("fecha", DESCENDING)])
    if doc is None:
        raise HTTPException(status_code=404, detail="Aún no hay lecturas")
    return a_json(doc)
