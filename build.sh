#!/bin/sh
# Uebersetzt gatling (dietlibc + libowfat + gatling aus fefes CVS) in ein
# Docker-Image und prueft danach, dass der Container eine Seite ausliefert.
#
#   sh build.sh                      # -> wilfahrt/gatling-webserver:dev
#   sh build.sh wilfahrt/gatling-webserver:latest
#
# Die Compose-Dateien unter scenarios/ bauen dasselbe Image ueber
# "build: context: ../.." selbst, dieses Skript ist nur die Kurzform.
set -eu
cd "$(dirname "$0")"

TAG="${1:-wilfahrt/gatling-webserver:dev}"
PORT="${PORT:-8089}"

echo "==> baue $TAG (linux/amd64)"
docker build --platform linux/amd64 -t "$TAG" .

echo "==> Image-Groesse"
docker image inspect "$TAG" --format '{{.Size}} Bytes'

echo "==> Smoke-Test: gatling -h"
# gatling schreibt die Hilfe nach stderr und beendet sich mit 0.
docker run --rm --entrypoint /gatling "$TAG" -h 2>&1 | head -1

echo "==> Smoke-Test: Platzhalterseite und kein Zugriff auf das Container-Root"
CID=$(docker run -d --rm -p "127.0.0.1:$PORT:80" "$TAG")
trap 'docker stop "$CID" >/dev/null 2>&1 || true' EXIT
for i in $(seq 1 20); do
  curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null && break
  sleep 0.5
done
curl -fsS "http://127.0.0.1:$PORT/" | grep -q "gatling is running"
if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/etc/passwd" 2>/dev/null; then
  echo "FEHLER: /etc/passwd ist erreichbar, chroot greift nicht" >&2
  exit 1
fi
echo "==> fertig: $TAG"
