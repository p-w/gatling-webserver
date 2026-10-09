# Let's-Encrypt-Zertifikate für gatling-webserver

Das Image enthält nur das TLS-freie Binary `gatling`. gatling selbst kann
TLS nur in der Variante `tlsgatling`, die gegen OpenSSL gebaut wird und im
Dockerfile nicht vorgesehen ist. Für Let's Encrypt gibt es deshalb drei
Wege, sortiert nach Aufwand.

| Weg | Wer holt das Zertifikat | Wer terminiert TLS | Aufwand | Empfehlung |
|---|---|---|---|---|
| A: Caddy davor | Caddy, automatisch | Caddy | gering | Standardfall |
| B: certbot mit Webroot | certbot gegen gatling | ein TLS-Proxy oder `tlsgatling` | mittel | wenn schon certbot im Einsatz ist |
| C: certbot mit DNS-01 | certbot über DNS-API | ein TLS-Proxy oder `tlsgatling` | mittel | ohne offenen Port 80, Wildcards |

Voraussetzungen für alle Wege: eine öffentliche Domain mit A- oder
AAAA-Record auf den Host, Port 443 von außen erreichbar, für HTTP-01 auch
Port 80.

## Weg A: Caddy als TLS-Proxy vor gatling (empfohlen)

Caddy beantragt beim ersten Start ein Zertifikat, erneuert es selbst und
leitet HTTP auf HTTPS um. gatling bleibt im internen Compose-Netz und
bekommt nur Klartext-HTTP von Caddy. Der fertige Stack liegt in
[`scenarios/04-tls-letsencrypt`](../scenarios/04-tls-letsencrypt/).

```yaml
services:
  caddy:
    image: caddy:2-alpine
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"          # HTTP/3
    environment:
      DOMAIN: ${DOMAIN}
      ACME_EMAIL: ${ACME_EMAIL}
      ACME_CA: ${ACME_CA:-https://acme-v02.api.letsencrypt.org/directory}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data        # Zertifikate und Account-Schluessel
      - caddy-config:/config
    depends_on:
      - gatling

  gatling:
    image: wilfahrt/gatling-webserver:latest
    volumes:
      - ./www:/var/www:ro
    # kein "ports:", gatling ist nur fuer Caddy erreichbar

volumes:
  caddy-data:
  caddy-config:
```

```
# Caddyfile
{
    email {$ACME_EMAIL}
    acme_ca {$ACME_CA}
}

{$DOMAIN} {
    encode zstd gzip
    reverse_proxy gatling:80
}
```

Ablauf:

1. `.env` anlegen mit `DOMAIN=www.example.org` und `ACME_EMAIL=admin@example.org`.
2. Zum Ausprobieren erst die Staging-CA nehmen, sie hat keine
   Ratenbegrenzung, ihre Zertifikate sind aber nicht vertrauenswürdig:
   `ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory`.
3. `docker compose up -d`, dann `docker compose logs -f caddy` beobachten.
   Nach wenigen Sekunden steht dort `certificate obtained successfully`.
4. Für das echte Zertifikat `ACME_CA` aus der `.env` entfernen, das Volume
   `caddy-data` löschen (`docker compose down -v`) und neu starten.
5. Prüfen: `curl -vI https://www.example.org` zeigt den Aussteller
   `Let's Encrypt`, `curl -I http://www.example.org` antwortet mit 308 auf
   HTTPS.

Erneuerung: Caddy erneuert nach zwei Dritteln der Laufzeit selbst. Es ist
nichts weiter einzurichten, das Volume `caddy-data` darf nur nicht gelöscht
werden.

Hinweise:

- Caddy setzt `X-Forwarded-For` und `X-Forwarded-Proto`. gatling reicht
  alle Header als `HTTP_*` an FastCGI weiter, das WordPress-Szenario wertet
  `X-Forwarded-Proto` bereits aus.
- Im gatling-Zugriffslog steht die IP von Caddy, nicht die des Besuchers.
  Wer die echte IP braucht, muss das Caddy-Log verwenden.
- Statt Caddy funktioniert auch nginx mit certbot (Weg B), Caddy ist nur
  der kürzeste Weg.

## Weg B: certbot mit Webroot gegen gatling

Hier liefert gatling die HTTP-01-Challenge selbst aus und certbot legt
die Zertifikate auf dem Host ab. Eine Besonderheit von gatling muss dabei
umgangen werden.

**Stolperstein `/.well-known/`:** gatling schreibt in Anfragepfaden jedes
`/.` zu `/:` um, damit versteckte Dateien nie ausgeliefert werden. Die
Anfrage `GET /.well-known/acme-challenge/TOKEN` sucht auf der Platte also
nach `:well-known/acme-challenge/TOKEN`. Der Webroot für certbot heißt
deshalb auf der Platte `:well-known` statt `.well-known`:

```bash
# im Doc-Root von gatling, zum Beispiel /srv/www
mkdir -p ':well-known/acme-challenge'
chmod 755 ':well-known' ':well-known/acme-challenge'
```

certbot schreibt fest nach `<webroot>/.well-known/acme-challenge/`. Ein
Symlink löst das:

```bash
ln -s ':well-known' .well-known
```

gatling folgt Symlinks innerhalb des Doc-Roots, certbot schreibt in
`.well-known/...`, gatling liest aus `:well-known/...`, beides ist dasselbe
Verzeichnis. Die Token-Dateien müssen weltlesbar sein (certbot legt sie mit
0644 an).

Zertifikat holen (gatling läuft auf Port 80 mit diesem Doc-Root):

```bash
docker run --rm -it \
  -v /srv/www:/srv/www \
  -v letsencrypt:/etc/letsencrypt \
  certbot/certbot certonly --webroot -w /srv/www \
  -d www.example.org --email admin@example.org --agree-tos --no-eff-email
```

Die Dateien liegen danach im Volume `letsencrypt` unter
`live/www.example.org/fullchain.pem` und `privkey.pem`.

Erneuerung als Compose-Service, der alle zwölf Stunden prüft:

```yaml
  certbot:
    image: certbot/certbot
    volumes:
      - ./www:/srv/www
      - letsencrypt:/etc/letsencrypt
    entrypoint: sh -c 'trap exit TERM; while :; do certbot renew --webroot -w /srv/www --deploy-hook "touch /etc/letsencrypt/renewed"; sleep 12h; done'
```

Der Proxy, der TLS terminiert (Abschnitt "Zertifikat einsetzen"), muss
nach einer Erneuerung neu laden. Der `--deploy-hook` kann dafür statt der
Marker-Datei auch direkt `docker compose kill -s HUP proxy` aufrufen, wenn
der certbot-Container Zugriff auf den Docker-Socket hat.

## Weg C: certbot mit DNS-01

Ohne offenen Port 80, auch für Wildcard-Zertifikate. certbot braucht ein
DNS-Plugin für den Provider (zum Beispiel `certbot/dns-cloudflare`,
`certbot/dns-route53`, für andere Anbieter das Plugin `certbot-dns-*` aus
PyPI oder `lego`). Beispiel Cloudflare:

```bash
docker run --rm -it \
  -v letsencrypt:/etc/letsencrypt \
  -v ./cloudflare.ini:/cloudflare.ini:ro \
  certbot/dns-cloudflare certonly \
  --dns-cloudflare --dns-cloudflare-credentials /cloudflare.ini \
  -d example.org -d '*.example.org' --email admin@example.org --agree-tos
```

Das Zertifikat wird wie in Weg B eingesetzt. Caddy kann DNS-01 ebenfalls,
braucht dafür aber ein selbst gebautes Image mit dem passenden DNS-Modul
(`xcaddy build --with github.com/caddy-dns/cloudflare`).

## Zertifikat einsetzen (Weg B und C)

### Variante 1: TLS-Proxy mit vorhandenem Zertifikat

Caddy nimmt auch fremde Zertifikate an und übernimmt dann nur noch das
Terminieren:

```
{$DOMAIN} {
    tls /certs/live/{$DOMAIN}/fullchain.pem /certs/live/{$DOMAIN}/privkey.pem
    reverse_proxy gatling:80
}
```

Mit dem Volume `letsencrypt:/certs:ro`. Nach einer Erneuerung
`docker compose kill -s HUP caddy` oder `docker compose restart caddy`.
nginx oder haproxy funktionieren mit denselben Dateien.

### Variante 2: tlsgatling (experimentell)

gatling kann TLS selbst, wenn es als `tlsgatling` gebaut wird. Aus
`README.tls` und dem Quelltext (`ssl.c`, `gatling.c`) ergibt sich:

- `tlsgatling` erwartet im Doc-Root eine Datei `server.pem` mit Zertifikat
  und Schlüssel hintereinander. Für Let's Encrypt also
  `cat fullchain.pem privkey.pem > server.pem`.
- Diffie-Hellman-Parameter kommen optional aus `dhparams.pem` oder werden
  ans Ende von `server.pem` angehängt. Ohne eigene Datei nutzt gatling
  eingebaute Parameter.
- HTTPS läuft auf Port 443 (4433 ohne root), Option `-e` schaltet es ein.
- Im chroot muss `/dev/urandom` vorhanden sein, sonst scheitert der
  Handshake.
- Cipher-Suites lassen sich über die Umgebungsvariable `TLSCIPHERS`
  setzen, Vorgabe ist `HIGH:!DSS:!RC4:!MD5:!aNULL:!eNULL:@STRENGTH`.
- Eine Erneuerung braucht einen Neustart, gatling liest `server.pem` nur
  beim Start. `SIGHUP` schließt die Server-Sockets, so dass ein neuer
  Prozess dieselben Ports übernehmen kann.

Offene Punkte, die vor einem Einsatz zu klären wären:

- Der Build. `diet make tlsgatling` braucht ein OpenSSL, das gegen dietlibc
  gebaut wurde, das Alpine-OpenSSL (musl) passt nicht dazu. Das ist der
  Grund, warum das Image nur `gatling` enthält.
- Ob `server.pem` mit Modus 0600 gelesen wird, bevor gatling die Rechte
  auf `GATLING_USER` abgibt. Ist das nicht der Fall, müsste die Datei
  lesbar für uid 65534 sein. Weltlesbar darf sie keinesfalls sein, gatling
  würde sie sonst als `/server.pem` ausliefern. Da gatling nur weltlesbare
  Dateien ausliefert, reicht Modus 0640 mit Gruppe 65534 als Kompromiss.
- Kein OCSP-Stapling, kein HTTP/2, keine Umleitung von HTTP auf HTTPS.

Solange diese Punkte offen sind, ist Weg A die robustere Wahl.

## Sonderfall Tor Hidden Service

Ein `.onion`-Dienst braucht kein Let's-Encrypt-Zertifikat, Tor
verschlüsselt und authentifiziert die Verbindung selbst. Let's Encrypt
stellt für `.onion`-Namen auch keine Zertifikate aus. Wer eine Clearnet-Seite
zusätzlich als Onion anbietet, kann per Caddy den Header
`Onion-Location: http://xyz.onion` setzen, dann bietet der Tor Browser
den Wechsel an:

```
{$DOMAIN} {
    header Onion-Location "http://{$ONION}"
    reverse_proxy gatling:80
}
```

## Prüfen

```bash
curl -vI https://www.example.org 2>&1 | grep -E "issuer|expire|HTTP/"
openssl s_client -connect www.example.org:443 -servername www.example.org </dev/null 2>/dev/null | openssl x509 -noout -issuer -dates
```

Der Aussteller lautet `C=US, O=Let's Encrypt, CN=...`, bei der Staging-CA
enthält er `(STAGING)`. Ein externer Check ist zum Beispiel
https://www.ssllabs.com/ssltest/ oder https://crt.sh/?q=www.example.org
für die ausgestellten Zertifikate.
