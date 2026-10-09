# Benchmark: Energie pro Request für statische Webserver

Reproduzierbarer Vergleich des gatling-Images mit `nginx:alpine`,
`httpd:alpine` und `caddy:alpine` auf identischem Inhalt. Liefert die Zahlen
für das JOSS-Paper in [`../paper/`](../paper/).

## Forschungsfrage

Wie viel elektrische Energie kostet das Ausliefern einer statischen Datei
aus einem Container, und wie stark hängt das vom Server-Image ab? Kennzahl
ist **Joule pro 1000 Requests** nach Abzug der Leerlauf-Grundlast des Hosts,
getrennt nach Dateigröße. Daneben werden Image-Größe, Speicherbedarf,
Durchsatz und Latenz-Perzentile erfasst, damit sich Energie und Leistung
gemeinsam beurteilen lassen.

## Aufbau

| Baustein | Umsetzung |
|---|---|
| Inhalt | `mkdata.sh` erzeugt deterministisch 1 KiB HTML, 100 KiB SVG, 10 MiB Binärdaten |
| Server | `docker-compose.yml`, vier Images mit Standardkonfiguration, nur an 127.0.0.1 gebunden |
| Last | [`oha`](https://github.com/hatoo/oha), feste Dauer und Verbindungszahl, JSON-Ausgabe |
| Energie | RAPL-Zähler des Prozessors über `/sys/class/powercap/intel-rapl:0/energy_uj` |
| Speicher | `docker stats` im Leerlauf und zur Halbzeit jedes Laufs |
| Auswertung | `analyze.py`: Median und Interquartilsabstand, Markdown-Tabelle, Abbildungen |

Messmatrix: 4 Server × 3 Dateien × 5 Wiederholungen × 30 s, dazu 5 s
Aufwärmen je Zelle. Ein voller Lauf dauert etwa 40 Minuten.

## Ausführen

Voraussetzungen: Linux auf echter Hardware (Intel oder AMD mit RAPL), Docker,
`oha`, `jq`, `curl`, `python3`, für die Abbildungen `matplotlib`.

```bash
cd benchmark
sh mkdata.sh
docker compose up -d --build
sudo sh run.sh                   # root fuer den RAPL-Zaehler
python3 analyze.py results/*.csv
docker compose down
```

Kürzerer Testlauf zum Prüfen der Kette:

```bash
DURATION=5 REPEATS=1 FILES=index.html sh run.sh
```

Ohne root läuft alles durch, nur die Energiespalten bleiben leer.

## Was gemessen wird und was nicht

- **RAPL misst Prozessor-Package und DRAM**, nicht Netzwerkkarte, Platte oder
  Netzteilverluste. Die Zahlen sind daher für den Vergleich der Server
  geeignet, nicht als absolute Energie des Gesamtsystems.
- **Lastgenerator auf demselben Host:** `oha` verbraucht selbst Energie, die
  in die Messung einfließt. Sie ist bei allen Servern ähnlich, verschiebt
  aber die Absolutwerte nach oben. Für saubere Zahlen den Lastgenerator auf
  einen zweiten Rechner legen: in der Compose-Datei die Ports an `0.0.0.0`
  binden, dann `TARGET=<ip-des-servers> sh run.sh` auf dem zweiten Rechner.
  Dann fehlt allerdings der RAPL-Zugriff, die Energie muss auf dem
  Server-Host parallel mitgeschrieben werden (zum Beispiel mit
  [Scaphandre](https://github.com/hubblo-org/scaphandre) oder einem
  `while`-Loop über `energy_uj`).
- **Grundlast:** Vor der Serie werden 30 s Leerlauf gemessen und als
  Watt-Wert von jeder Zelle abgezogen. Hintergrunddienste auf dem Host vorher
  beenden, CPU-Frequenzskalierung auf `performance` stellen, Turbo
  deaktivieren, sonst streuen die Werte stark.
- **Virtuelle Maschinen und Docker Desktop** liefern keinen RAPL-Zugriff.
- **Standardkonfigurationen** sind bewusst gewählt. Mit Tuning (Worker-Zahl,
  `sendfile`, Caching) ändern sich die Ergebnisse. Wer tunen will, legt
  pro Server eine Konfigurationsdatei in diesen Ordner und hängt sie in der
  Compose-Datei ein, so bleibt der Vergleich nachvollziehbar.

## Erweitern

Ein weiterer Server ist ein zusätzlicher Service in `docker-compose.yml`
mit eigenem Port und ein Eintrag in `SERVERS`:

```bash
SERVERS="gatling:8081 nginx:8082 lighttpd:8085" sh run.sh
```

Andere Lastprofile (HTTP/1.1 Keep-Alive aus, mehr Verbindungen, Range-
Requests) lassen sich über `CONC` oder durch Anpassen des `oha`-Aufrufs in
`run.sh` abbilden. Für dynamische Inhalte (PHP über FastCGI) eignet sich
das WordPress-Szenario unter `../scenarios/02-wordpress-phpfpm/` als
Vorlage, dann aber mit identischem php-fpm-Backend für alle Server.

## Ergebnisse

`results/` enthält die Rohdaten jedes Laufs (eine Zeile pro Zelle und
Wiederholung) sowie `summary.csv` und `summary.md`. Die Tabelle aus
`summary.md` wird in `paper.md` übernommen, die Abbildungen landen in
`../paper/figures/`. Zu jedem veröffentlichten Ergebnis gehören die
Angaben zu Host (CPU, RAM, Kernel, Docker-Version), Datum und den
Einstellungen `DURATION`, `CONC`, `REPEATS`, am besten als
`results/<zeitstempel>.txt` neben der CSV.
