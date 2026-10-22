FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY comun ./comun
COPY ingesta ./ingesta
COPY api ./api

# El comando real lo define docker-compose (ingesta o api).
CMD ["python", "-m", "ingesta"]
