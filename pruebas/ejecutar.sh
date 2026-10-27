#!/usr/bin/env bash
# Crea una base de datos desechable, carga el esquema y pasa las pruebas
# de seguridad. Uso: PGHOST=... PGPORT=... PGUSER=postgres ./pruebas/ejecutar.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DB=gestor_pruebas
dropdb --if-exists "$DB"
createdb "$DB"

psql -q -v ON_ERROR_STOP=1 -d "$DB" -f pruebas/supabase-simulado.sql
for m in supabase/migrations/*.sql; do psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$m"; done
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f pruebas/rls.sql 2>&1 \
  | sed -e 's/^psql:[^:]*:[0-9]*: //' -e 's/^NOTICE:  //' -e 's/^WARNING:  //'

dropdb "$DB"
