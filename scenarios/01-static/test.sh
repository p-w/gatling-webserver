#!/bin/sh
# Smoke-Test fuer Szenario 1 (statische Dateien).
# Voraussetzung: docker compose up -d   und   curl auf dem Host.
set -u
BASE="${BASE:-http://localhost:8080}"
fail=0

check() { # check <Beschreibung> <Bedingung als Shell-Ausdruck>
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}

echo "warte auf $BASE ..."
for i in $(seq 1 30); do
  curl -fsS -o /dev/null "$BASE/" 2>/dev/null && break
  sleep 1
done

status()  { curl -s -o /dev/null -w '%{http_code}' "$@"; }
header()  { curl -sI "$1" | tr -d '\r' | grep -i "^$2:" | head -1 | cut -d' ' -f2-; }

echo "Antwort-Header von GET /:"; curl -sI "$BASE/" | tr -d '\r' | sed 's/^/    /'

check "GET / liefert 200"                       '[ "$(status "$BASE/")" = 200 ]'
check "GET / hat Content-Type text/html"        'header "$BASE/" content-type | grep -qi "text/html"'
check "GET / enthaelt den Seitentitel"          'curl -s "$BASE/" | grep -q "gatling liefert statische Dateien"'
check "CSS wird als text/css ausgeliefert"      'header "$BASE/assets/style.css" content-type | grep -qi "text/css"'
check "robots.txt ist text/plain"               'header "$BASE/robots.txt" content-type | grep -qi "text/plain"'
check "unbekannte Datei liefert 404"            '[ "$(status "$BASE/gibt-es-nicht.html")" = 404 ]'
check "Verzeichnisindex fuer /downloads/"       'curl -s "$BASE/downloads/" | grep -q "lorem.txt"'
check "Range-Request liefert 206"               '[ "$(status -H "Range: bytes=0-99" "$BASE/downloads/lorem.txt")" = 206 ]'
check "Range-Request liefert genau 100 Bytes"   '[ "$(curl -s -H "Range: bytes=0-99" "$BASE/downloads/lorem.txt" | wc -c | tr -d " ")" = 100 ]'
check "HEAD liefert Content-Length"             'header "$BASE/downloads/lorem.txt" content-length | grep -q "^[0-9]"'
check "Keep-Alive: zweiter Request nutzt Verbindung wieder" 'curl -s -o /dev/null -o /dev/null -w "%{num_connects}\n" "$BASE/" "$BASE/robots.txt" | tail -1 | grep -q "^0$"'
check "Dotfile /.secret ist nicht erreichbar"   '[ "$(status "$BASE/.secret")" != 200 ]'
check "Pfad-Ausbruch /../etc/passwd liefert kein 200" '[ "$(status --path-as-is "$BASE/../etc/passwd")" != 200 ]'
check "Server-Header ist Gatling/<version>"      'header "$BASE/" server | grep -Eq "^Gatling/[0-9]+\.[0-9]+"'

[ $fail -eq 0 ] && echo "alle Tests bestanden" || { echo "es gab Fehler"; exit 1; }
