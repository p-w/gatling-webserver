# Testszenarien für gatling-webserver

Vier Compose-Setups, die das Image aus dem Repo-Root bauen und gatling in
typischen Rollen betreiben. Jedes Szenario bringt ein `test.sh` mit, das per
curl prüft, ob sich der Server wie erwartet verhält.

| Szenario | Ordner | Port auf dem Host | Kern |
|---|---|---|---|
| Statische Dateien | [01-static](01-static/) | 8080 | chroot, Verzeichnisindex, Range-Requests |
| WordPress mit php-fpm | [02-wordpress-phpfpm](02-wordpress-phpfpm/) | 8081 | FastCGI über `-O F/ip/port/regex`, `-I index.php` |
| Tor Hidden Service | [03-tor-hidden-service](03-tor-hidden-service/) | keiner | gatling nur im internen Netz, Tor davor |
| TLS mit Let's Encrypt | [04-tls-letsencrypt](04-tls-letsencrypt/) | 80, 443 | Caddy terminiert TLS, gatling dahinter |

## Image bauen ("übersetzen")

```bash
sh build.sh
```

Das baut `wilfahrt/gatling-webserver:dev` aus dem Dockerfile (dietlibc,
libowfat und gatling werden aus fefes CVS geholt und statisch gebaut) und
prüft danach, dass der Container die Platzhalterseite liefert und
`/etc/passwd` nicht erreichbar ist. Die Compose-Dateien bauen dasselbe
Image bei `docker compose up --build` selbst.

## Szenario ausführen

```bash
cd scenarios/01-static
docker compose up -d --build
sh test.sh
docker compose down
```

Für Szenario 2 vorher `cp .env.example .env` und die Passwörter setzen. Das
Testskript führt beim ersten Lauf die WordPress-Installation per POST durch,
Zugangsdaten stehen in der `.env`.

Für Szenario 3 läuft das Testskript komplett über `docker compose exec`. Der
letzte Test wartet bis zu drei Minuten, bis der Hidden-Service-Descriptor im
Tor-Netz angekommen ist.

Szenario 4 braucht eine öffentliche Domain, die auf den Host zeigt, und
offene Ports 80 und 443. Erst mit der Staging-CA testen (siehe
`.env.example`), dann umschalten. Anleitung: [docs/lets-encrypt.md](../docs/lets-encrypt.md).

## Wie das Image gatling startet

Der Entrypoint `docker-entrypoint.sh` baut die Kommandozeile aus
Umgebungsvariablen zusammen, zusätzliche Argumente hinter dem Image-Namen
werden angehängt:

| Variable | Voreinstellung | Bedeutung |
|---|---|---|
| `GATLING_OPTIONS` | `-F -S -V -D` | Basisoptionen |
| `GATLING_ROOT` | `/var/www` | Doc-Root, gatling wird dort gestartet |
| `GATLING_CHROOT` | `1` | chroot in den Doc-Root nach dem Binden der Ports |
| `GATLING_USER` | `65534:65534` | uid:gid nach dem Binden, leer = root bleiben |

Ist `-O` gesetzt, legt der Entrypoint die Marker-Datei `.proxy` an, ohne die
gatling den Proxy-Modus ignoriert.

## Die gatling-Optionen, die hier benutzt werden

| Option | Bedeutung |
|---|---|
| `-F`, `-S` | FTP und SMB aus (beide sind sonst an) |
| `-V` | kein Virtual Hosting, Doc-Root ist das aktuelle Verzeichnis |
| `-d` / `-D` | Verzeichnisindex an / aus |
| `-n` | kein Zugriffslog (Tor-Szenario) |
| `-c DIR` | chroot nach DIR nach dem Binden der Ports |
| `-u UID:GID` | nach dem Binden zu dieser Kennung wechseln |
| `-I index.php` | bei Verzeichnis-Requests zusätzlich diese Datei probieren |
| `-O F/IP/PORT/REGEX` | Requests, deren Pfad auf REGEX passt, per FastCGI an IP:PORT geben (`S` = SCGI, ohne Präfix = HTTP-Proxy) |

Die Optionen stammen aus der Usage-Ausgabe und dem Quelltext von gatling
(`gatling.c`, `http.c`).

## Stolpersteine

- **`-O` nimmt nur IP-Adressen**, keine Compose-Servicenamen. Daher die
  festen IPs über `ipam` in den Compose-Netzen. Alternative: Unix-Socket per
  `-O 'F/|/pfad/zum/socket|\.php'` über ein gemeinsames Volume.
- **Der Proxy-Modus ist nur mit einer Datei `.proxy` im Doc-Root aktiv.**
  Der Entrypoint legt sie an, dafür muss der Doc-Root beschreibbar sein.
  Ohne sie liefert gatling `.php`-Dateien als Download aus, falls sie
  weltlesbar sind.
- **`SCRIPT_FILENAME` ist `<cwd von gatling>/<Pfad>`.** Mit chroot wird das
  `/<Pfad>`, ohne chroot der Pfad des Doc-Roots. php-fpm muss die Datei
  unter genau diesem Pfad sehen, deshalb hängt Szenario 2 das Volume in
  beiden Containern gleich ein und setzt `GATLING_CHROOT=0`.
- **Kein URL-Rewrite.** gatling kennt kein `try_files`. WordPress-Permalinks
  funktionieren nur als "Einfach" (`?p=123`) oder im PATH_INFO-Format
  (`/index.php/%year%/%postname%/`), einzustellen unter Einstellungen,
  Permalinks. Die Regex in `-O` steht deshalb ohne `$`, damit
  `index.php/...` noch matcht. Solange "Einfach" aktiv ist, leitet
  WordPress `/index.php/<pfad>` selbst auf `/<pfad>` um, was gatling dann
  mit 404 beantwortet; das ist WordPress-Verhalten, kein gatling-Fehler.
- **Pfade mit `/.` werden intern zu `/:` umgeschrieben.** Dotfiles wie
  `.proxy`, `.htaccess` oder `.secret` sind so nie abrufbar. Das gilt aber
  auch für `/.well-known/`, was für ACME-Challenges relevant ist. Der
  Ausweg (Verzeichnis `:well-known` auf der Platte) steht in
  [docs/lets-encrypt.md](../docs/lets-encrypt.md).
- **Nur weltlesbare Dateien werden ausgeliefert.** Bind-Mounts von Linux-Hosts
  brauchen `o+r` auf den Dateien. Auf Windows- und macOS-Hosts ist das durch
  Docker Desktop automatisch der Fall.
- **`Server: Gatling/0.17` wird immer gesendet.** gatling hat keine Option,
  den Header abzuschalten, in der CI bestätigt. Wer das Fingerprinting im
  Tor-Szenario vermeiden will, braucht einen Reverse Proxy davor, der den
  Header entfernt.
- **Tor löst das Ziel in `HiddenServicePort` einmal beim Start auf.** Deshalb
  hat der Web-Container in Szenario 3 eine feste IP, ein Neustart von `web`
  bleibt so für Tor unsichtbar.
- **Container ohne root starten?** Dann `GATLING_USER=""` setzen und einen
  Port ab 1024 wählen (`-p 8000`), weil gatling ohne root weder Port 80
  binden noch die Kennung wechseln kann. `GATLING_CHROOT=0` ist dann
  ebenfalls nötig.

## Stand der Prüfung

Der Workflow unter `.github/workflows/build.yml` baut das Image und lässt
die Szenarien 1 und 2 bei jedem Push laufen. Beide sind in GitHub Actions
grün, inklusive WordPress-Installation per POST über FastCGI. Die Szenarien
3 (Tor) und 4 (Let's Encrypt) werden dort nur auf gültige Compose-Syntax
geprüft, weil sie das Tor-Netz beziehungsweise eine öffentliche Domain
brauchen. Ihre Testskripte sind bisher nicht real gelaufen.
