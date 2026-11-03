#!/bin/bash
# Copia de seguridad de SON: la base de datos y los informes PDF. Corre solo todos los días (cron).
# Guarda 14 días en /opt/son/backups.
set -euo pipefail
cd /opt/son
mkdir -p backups
FECHA=$(date +%Y-%m-%d_%H%M)

docker compose exec -T db pg_dump -U sima -d sima_db | gzip > "backups/base_$FECHA.sql.gz"
gzip -t "backups/base_$FECHA.sql.gz"   # verifica que el archivo no quedó dañado
tar czf "backups/informes_$FECHA.tgz" -C datos storage

find backups -type f -mtime +14 -delete
echo "$(date '+%F %T') copia $FECHA lista"
