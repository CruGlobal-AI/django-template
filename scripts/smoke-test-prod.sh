#!/usr/bin/env bash
# Smoke test for the prod image, run the way Coolify will use it:
# migrate as the post-deployment command, then curl /health and / inside the container.
# Usage: scripts/smoke-test-prod.sh
set -uo pipefail

cd "$(dirname "$0")/.."

SUFFIX="$$"
IMAGE="django-template-prod-smoke:${SUFFIX}"
NETWORK="django-template-smoke-net-${SUFFIX}"
DB="django-template-smoke-db-${SUFFIX}"
APP="django-template-smoke-app-${SUFFIX}"

STEP="setup"

cleanup() {
  docker rm -f "$APP" "$DB" >/dev/null 2>&1
  docker network rm "$NETWORK" >/dev/null 2>&1
  docker rmi "$IMAGE" >/dev/null 2>&1
}

fail() {
  echo "SMOKE TEST FAILED at step: $STEP" >&2
  [ -n "${1:-}" ] && echo "$1" >&2
  exit 1
}

trap cleanup EXIT
trap 'fail "Interrupted"' INT TERM

STEP="1: build prod image"
echo "==> $STEP"
docker build --target prod -t "$IMAGE" . || fail "docker build failed"

STEP="2: start Postgres 17 and the prod container"
echo "==> $STEP"
docker network create "$NETWORK" >/dev/null || fail "could not create network"
docker run -d --name "$DB" --network "$NETWORK" \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=smoke \
  postgres:17 >/dev/null || fail "could not start Postgres"

# Check over TCP: during first init Postgres only listens on a unix socket.
db_ready() { docker exec "$DB" pg_isready -h 127.0.0.1 -U app -d app >/dev/null 2>&1; }
for _ in $(seq 1 60); do
  db_ready && break
  sleep 1
done
db_ready || fail "Postgres did not become ready in 60s"

# ALLOWED_HOSTS deliberately leaves out the container's address.
docker run -d --name "$APP" --network "$NETWORK" \
  -e DEBUG=False -e SECRET_KEY=smoke-test-secret-key \
  -e ALLOWED_HOSTS=smoke.example.com \
  -e DB_HOST="$DB" -e DB_NAME=app -e DB_USER=app -e DB_PASSWORD=smoke \
  "$IMAGE" >/dev/null || fail "could not start prod container"

STEP="3: python manage.py migrate --noinput"
echo "==> $STEP"
docker exec "$APP" python manage.py migrate --noinput \
  || fail "migrate failed inside the prod container"

STEP="4: curl /health inside the container"
echo "==> $STEP"
docker exec "$APP" sh -c 'command -v curl >/dev/null' \
  || fail "curl is missing from the prod image (Coolify health check needs it)"

BODY=""
for _ in $(seq 1 15); do
  BODY=$(docker exec "$APP" curl -fsS http://localhost:8080/health 2>/dev/null) && break
  sleep 1
done
[ "$BODY" = "ok" ] || fail "expected /health to return 'ok', got: '${BODY}'"

STEP="5: curl / (home page) inside the container"
echo "==> $STEP"
HOME_BODY=$(docker exec "$APP" curl -fsS -H "Host: smoke.example.com" http://localhost:8080/) \
  || fail "home page did not return 200"
echo "$HOME_BODY" | grep -q "Django Template" \
  || fail "home page did not contain 'Django Template'"

STEP="done"
echo "SMOKE TEST PASSED"
