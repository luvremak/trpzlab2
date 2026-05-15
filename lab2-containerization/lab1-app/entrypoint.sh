#!/usr/bin/env sh
#
# Container entrypoint for the Lab 1 web application.
#
# Mirrors the ExecStartPre step of the Lab 1 systemd unit: run the database
# migration before starting the application. docker-compose already waits
# for PostgreSQL to be healthy (depends_on: condition: service_healthy), but
# a short bounded retry loop is kept as a safety net in case the database
# accepts connections slightly before it is fully ready.
#
set -e

ATTEMPTS=10
DELAY=2

i=1
while [ "$i" -le "$ATTEMPTS" ]; do
    echo "[entrypoint] running database migration (attempt $i/$ATTEMPTS)..."
    if python -m app.migrate; then
        break
    fi
    if [ "$i" -eq "$ATTEMPTS" ]; then
        echo "[entrypoint] migration still failing after $ATTEMPTS attempts, giving up." >&2
        exit 1
    fi
    echo "[entrypoint] migration failed, retrying in ${DELAY}s..."
    sleep "$DELAY"
    i=$((i + 1))
done

echo "[entrypoint] starting mywebapp on 0.0.0.0:5200..."
exec uvicorn app.main:app --host 0.0.0.0 --port 5200
