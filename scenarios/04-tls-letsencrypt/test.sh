#!/bin/sh
# Smoke-Test fuer Szenario 4 (Let's Encrypt via Caddy vor gatling).
# Voraussetzung: docker compose up -d, .env mit DOMAIN, curl und openssl auf
# dem Host, und die Domain zeigt auf diesen Host.
set -u
[ -f .env ] && . ./.env
DOMAIN="${DOMAIN:?DOMAIN fehlt (.env)}"
STAGING=0
case "${ACME_CA:-}" in *staging*) STAGING=1 ;; esac
# Staging-Zertifikate sind nicht vertrauenswuerdig, dann ohne Pruefung der Kette
[ $STAGING -eq 1 ] && K="-k" || K=""
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
status() { curl $K -s -o /dev/null -w '%{http_code}' "$@"; }

echo "warte auf Zertifikat fuer $DOMAIN (Caddy-Log: docker compose logs -f caddy) ..."
for i in $(seq 1 60); do
  [ "$(status --max-time 5 "https://$DOMAIN/")" = 200 ] && break
  sleep 3
done

issuer=$(openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null 2>/dev/null \
         | openssl x509 -noout -issuer 2>/dev/null)
echo "Aussteller: ${issuer:-<kein Zertifikat>}"

check "HTTPS liefert 200"                          '[ "$(status "https://$DOMAIN/")" = 200 ]'
check "Inhalt kommt von gatling"                   'curl $K -s "https://$DOMAIN/" | grep -q "den Inhalt liefert gatling"'
check "Aussteller ist Let's Encrypt"               'echo "$issuer" | grep -qi "Let.s Encrypt"'
if [ $STAGING -eq 1 ]; then
  check "Staging-CA erkannt (STAGING im Aussteller)" 'echo "$issuer" | grep -q "STAGING"'
else
  check "Zertifikatskette wird vom System akzeptiert" 'curl -s -o /dev/null "https://$DOMAIN/"'
fi
check "HTTP leitet auf HTTPS um (308)"             '[ "$(status "http://$DOMAIN/")" = 308 ]'
check "Redirect-Ziel ist https://"                 'curl -sI "http://$DOMAIN/" | tr -d "\r" | grep -qi "^location: https://"'
check "gatling veroeffentlicht keinen Host-Port"   '[ -z "$(docker compose port gatling 80 2>/dev/null)" ]'
check "Zertifikat laeuft noch mindestens 7 Tage"   'openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null 2>/dev/null | openssl x509 -noout -checkend 604800 >/dev/null'

[ $fail -eq 0 ] && echo "alle Tests bestanden" || { echo "es gab Fehler"; exit 1; }
