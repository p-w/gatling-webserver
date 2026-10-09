#!/bin/sh
# Smoke-Test fuer Szenario 2 (WordPress + php-fpm hinter gatling).
# Voraussetzung: docker compose up -d   und   curl auf dem Host.
# Fuehrt beim ersten Lauf die WordPress-Installation per POST aus und testet
# damit gleichzeitig FastCGI mit Request-Body.
set -u
BASE="${BASE:-http://localhost:8081}"
[ -f .env ] && . ./.env
WP_ADMIN_USER="${WP_ADMIN_USER:-admin}"
WP_ADMIN_PASSWORD="${WP_ADMIN_PASSWORD:-admin-change-me}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:-admin@example.invalid}"
fail=0

check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
header() { curl -sI "$1" | tr -d '\r' | grep -i "^$2:" | head -1 | cut -d' ' -f2-; }

echo "warte auf $BASE (WordPress-Image kopiert beim ersten Start die Dateien) ..."
code=000
for i in $(seq 1 90); do
  code=$(status "$BASE/wp-login.php")
  [ "$code" = 200 ] && break
  sleep 2
done
echo "wp-login.php -> HTTP $code"

# --- FastCGI-Grundfunktion --------------------------------------------------
check "wp-login.php wird von PHP gerendert (200)"     '[ "$(status "$BASE/wp-login.php")" = 200 ]'
check "PHP-Antwort enthaelt WordPress-Markup"         'curl -s "$BASE/wp-login.php" | grep -qi "wordpress"'
check "Verzeichnis / geht per -I an index.php"        '[ "$(status "$BASE/")" != 404 ]'
check "Startseite ist HTML von PHP (kein Dir-Index)"  '! curl -sL "$BASE/" | grep -q "Index of"'

# --- Statisches direkt von gatling ----------------------------------------
check "statisches JS direkt (200)"                    '[ "$(status "$BASE/wp-includes/js/wp-embed.min.js")" = 200 ]'
check "statisches JS hat JS-Content-Type"             'header "$BASE/wp-includes/js/wp-embed.min.js" content-type | grep -qi "javascript"'
check "readme.html statisch (200)"                    '[ "$(status "$BASE/readme.html")" = 200 ]'
check "CSS statisch (text/css)"                       'header "$BASE/wp-includes/css/dashicons.min.css" content-type | grep -qi "text/css"'

# --- Sicherheit ----------------------------------------------------------
check "wp-config.php wird nicht als Quelltext geliefert" '! curl -s "$BASE/wp-config.php" | grep -q "DB_PASSWORD"'
check ".proxy-Marker nicht abrufbar"                  '[ "$(status "$BASE/.proxy")" != 200 ]'

# --- Installation per POST (testet FastCGI mit Request-Body) ---------------
if curl -s "$BASE/wp-admin/install.php" | grep -q 'name="weblog_title"'; then
  echo "WordPress ist noch nicht installiert, fuehre Installation aus ..."
  out=$(curl -s -X POST "$BASE/wp-admin/install.php?step=2" \
      --data-urlencode "weblog_title=gatling Testblog" \
      --data-urlencode "user_name=$WP_ADMIN_USER" \
      --data-urlencode "admin_password=$WP_ADMIN_PASSWORD" \
      --data-urlencode "admin_password2=$WP_ADMIN_PASSWORD" \
      --data-urlencode "pw_weak=on" \
      --data-urlencode "admin_email=$WP_ADMIN_EMAIL" \
      --data-urlencode "blog_public=0" \
      --data-urlencode "Submit=Install WordPress" \
      --data-urlencode "language=")
  check "Installation per POST erfolgreich"           'echo "$out" | grep -qi "success\|erfolg\|wp-login.php"'
else
  echo "WordPress ist bereits installiert."
fi

check "Startseite nach Installation 200"              '[ "$(status -L "$BASE/")" = 200 ]'
check "Startseite enthaelt Blogtitel"                 'curl -sL "$BASE/" | grep -q "gatling Testblog"'
check "REST-API antwortet (JSON)"                     'curl -sL "$BASE/?rest_route=/" | grep -q "\"namespaces\""'
check "PATH_INFO-Permalink /index.php/... liefert kein 404" '[ "$(status -L "$BASE/index.php/hello-world/")" != 404 ]'
check "Login-Formular per POST antwortet (302 oder 200)" 'c=$(status -X POST -d "log=x&pwd=y&wp-submit=1" "$BASE/wp-login.php"); [ "$c" = 200 ] || [ "$c" = 302 ]'

[ $fail -eq 0 ] && echo "alle Tests bestanden" || { echo "es gab Fehler"; exit 1; }
