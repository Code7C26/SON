#!/bin/bash
# Se ejecuta EN EL SERVIDOR (lo llama publicar.ps1 -ConBase). Carga datos-base.sql en la base nueva.
# Es seguro: si la base ya tiene datos, NO la pisa.
set -euo pipefail
cd /opt/son

docker compose up -d db
echo "Esperando a la base de datos..."
for i in $(seq 1 30); do
    if docker compose exec -T db pg_isready -U sima -d sima_db >/dev/null 2>&1; then break; fi
    sleep 2
done

PSQL="docker compose exec -T db psql -U sima -d sima_db -v ON_ERROR_STOP=1"

if [ -n "$($PSQL -tAc "SELECT to_regclass('public.tecnicos')")" ]; then
    FILAS=$($PSQL -tAc "SELECT (SELECT count(*) FROM tecnicos) + (SELECT count(*) FROM admins)")
    if [ "$FILAS" != "0" ]; then
        echo "La base del servidor ya tiene datos: no se importa nada para no pisarlos."
        exit 0
    fi
else
    echo "Creando las tablas..."
    $PSQL < app/sql/esquema.sql
fi

echo "Importando los datos..."
$PSQL < datos-base.sql
echo "Base importada."
