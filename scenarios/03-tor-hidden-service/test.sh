#!/bin/sh
# Smoke-Test fuer Szenario 3 (Tor Hidden Service mit gatling).
# Voraussetzung: docker compose up -d. Laeuft komplett ueber docker compose exec,
# auf dem Host wird nichts ausser docker benoetigt.
set -u
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
tor() { docker compose exec -T tor "$@"; }

echo "warte, bis Tor die Hidden-Service-Schluessel angelegt hat ..."
for i in $(seq 1 60); do
  ONION=$(tor cat /var/lib/tor/hs/hostname 2>/dev/null | tr -d '\r\n')
  [ -n "$ONION" ] && break
  sleep 2
done
echo "onion: ${ONION:-<nicht gefunden>}"

# --- Isolation --------------------------------------------------------------
check "web veroeffentlicht keinen Host-Port"     '[ -z "$(docker compose port web 80 2>/dev/null)" ]'
check "hostname-Datei existiert"                 '[ -n "$ONION" ]'
check "Adresse ist v3-Onion (56 Zeichen + .onion)" 'echo "$ONION" | grep -Eq "^[a-z2-7]{56}\.onion$"'
check "HiddenServiceDir hat Modus 700"           '[ "$(tor stat -c %a /var/lib/tor/hs | tr -d "\r")" = 700 ]'

# --- gatling im internen Netz -------------------------------------------------
check "web liefert 200 im internen Netz"         '[ "$(tor curl -s -o /dev/null -w "%{http_code}" http://172.28.20.10/)" = 200 ]'
check "Seiteninhalt stimmt"                      'tor curl -s http://172.28.20.10/ | grep -q "gatling hinter Tor"'
echo "Hinweis: gatling sendet $(tor curl -sI http://172.28.20.10/ | tr -d '\r' | grep -i '^server:' || echo 'keinen Server-Header'); das laesst sich in gatling nicht abschalten."
check "kein Verzeichnisindex (-D)"               '[ "$(tor curl -s -o /dev/null -w "%{http_code}" http://172.28.20.10/nicht-da/)" != 200 ]'
check "Seite laedt keine externen Ressourcen"    '! tor curl -s http://172.28.20.10/ | grep -Eqi "(src|href)=\"https?://"'

# --- Ende-zu-Ende ueber das Tor-Netz (Descriptor-Upload dauert oft 1 bis 3 Minuten) ---
if [ -n "$ONION" ]; then
  echo "pruefe Erreichbarkeit ueber Tor: http://$ONION/ ..."
  code=000
  for i in $(seq 1 36); do
    code=$(tor curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
           --socks5-hostname 127.0.0.1:9050 "http://$ONION/" 2>/dev/null | tr -d '\r')
    [ "$code" = 200 ] && break
    sleep 5
  done
  check "Seite ueber .onion erreichbar (HTTP $code)" '[ "$code" = 200 ]'
fi

[ $fail -eq 0 ] && echo "alle Tests bestanden" || { echo "es gab Fehler"; exit 1; }
