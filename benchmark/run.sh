#!/bin/sh
# Benchmark-Lauf: Durchsatz, Latenz, Speicher und Energie pro Server und Datei.
#
# Voraussetzungen auf dem Host (Linux, bare metal, Intel oder AMD):
#   * docker compose up -d --build   (Server laufen)
#   * oha      https://github.com/hatoo/oha   (Lastgenerator mit JSON-Ausgabe)
#   * jq, python3
#   * root fuer /sys/class/powercap (RAPL). Ohne root laeuft alles, die
#     Energiespalten bleiben dann leer.
#
# Umgebungsvariablen:
#   DURATION   Sekunden pro Messzelle          (Standard 30)
#   CONC       gleichzeitige Verbindungen       (Standard 64)
#   REPEATS    Wiederholungen pro Zelle         (Standard 5)
#   SERVERS    Liste "name:port"                (Standard: alle vier)
#   FILES      Liste der Testdateien            (Standard: index.html figure.svg data.bin)
#   OHA        Pfad/Aufruf von oha              (Standard: oha)
#   TARGET     Host der Server                  (Standard 127.0.0.1; Lastgenerator auf
#              zweitem Rechner: TARGET=<ip> und Ports in compose auf 0.0.0.0 binden)
#
# Ergebnis: results/<zeitstempel>.csv, eine Zeile pro Messzelle und Wiederholung.
set -eu
cd "$(dirname "$0")"

DURATION="${DURATION:-30}"
CONC="${CONC:-64}"
REPEATS="${REPEATS:-5}"
SERVERS="${SERVERS:-gatling:8081 nginx:8082 httpd:8083 caddy:8084}"
FILES="${FILES:-index.html figure.svg data.bin}"
OHA="${OHA:-oha}"
TARGET="${TARGET:-127.0.0.1}"
RAPL="/sys/class/powercap/intel-rapl:0/energy_uj"
RAPL_MAX="/sys/class/powercap/intel-rapl:0/max_energy_range_uj"

mkdir -p results
OUT="results/$(date +%Y%m%d-%H%M%S).csv"
echo "server,image,image_bytes,file,file_bytes,repeat,duration_s,concurrency,requests,success_rate,rps,latency_p50_s,latency_p95_s,latency_p99_s,rss_idle_bytes,rss_load_bytes,energy_j,baseline_w,energy_net_j,j_per_1k_req" > "$OUT"

have_rapl=0
if [ -r "$RAPL" ]; then have_rapl=1; else echo "Hinweis: $RAPL nicht lesbar, Energie wird nicht gemessen (root? RAPL?)" >&2; fi

read_energy() { # Joule als Dezimalzahl, leer ohne RAPL
  [ $have_rapl -eq 1 ] || { echo ""; return; }
  awk -v uj="$(cat "$RAPL")" 'BEGIN { printf "%.6f", uj / 1e6 }'
}
energy_delta() { # start end -> Joule, mit Ueberlauf-Korrektur
  [ $have_rapl -eq 1 ] || { echo ""; return; }
  awk -v a="$1" -v b="$2" -v m="$(cat "$RAPL_MAX")" 'BEGIN { d = b - a; if (d < 0) d += m / 1e6; printf "%.6f", d }'
}
container_id() { docker compose ps -q "$1"; }
rss_bytes() { # aktueller Speicher des Containers in Bytes
  docker stats --no-stream --format '{{.MemUsage}}' "$1" | awk '{
    v=$1; u=v; gsub(/[0-9.]/,"",u); gsub(/[^0-9.]/,"",v);
    m=1; if (u=="KiB") m=1024; if (u=="MiB") m=1024*1024; if (u=="GiB") m=1024*1024*1024;
    printf "%d", v*m }'
}

echo "==> Leerlauf-Grundlast messen ($DURATION s)"
if [ $have_rapl -eq 1 ]; then
  e0=$(read_energy); sleep "$DURATION"; e1=$(read_energy)
  BASELINE_W=$(awk -v j="$(energy_delta "$e0" "$e1")" -v t="$DURATION" 'BEGIN { printf "%.3f", j / t }')
  echo "    Grundlast: $BASELINE_W W"
else
  BASELINE_W=""
fi

for sp in $SERVERS; do
  server="${sp%%:*}"; port="${sp##*:}"
  cid=$(container_id "$server")
  [ -n "$cid" ] || { echo "Container $server laeuft nicht" >&2; exit 1; }
  image=$(docker inspect --format '{{.Config.Image}}' "$cid")
  image_bytes=$(docker image inspect --format '{{.Size}}' "$image")
  base="http://$TARGET:$port"

  echo "==> $server ($image, $image_bytes Bytes)"
  curl -fsS -o /dev/null "$base/index.html" || { echo "$server antwortet nicht" >&2; exit 1; }

  for file in $FILES; do
    file_bytes=$(stat -c %s "www/$file")
    # Aufwaermen
    $OHA -z 5s -c "$CONC" --no-tui "$base/$file" >/dev/null 2>&1 || true
    sleep 2
    rss_idle=$(rss_bytes "$cid")

    r=1
    while [ $r -le "$REPEATS" ]; do
      e0=$(read_energy)
      $OHA -z "${DURATION}s" -c "$CONC" --no-tui -j "$base/$file" > results/.oha.json &
      pid=$!
      sleep $((DURATION / 2))
      rss_load=$(rss_bytes "$cid")
      wait $pid
      e1=$(read_energy)

      # oha-JSON: statusCodeDistribution zaehlt alle Antworten, summary.total
      # ist die Laufzeit in Sekunden, requestsPerSec der Durchsatz
      requests=$(jq '[.statusCodeDistribution[]] | add // 0' results/.oha.json)
      rps=$(jq '.summary.requestsPerSec' results/.oha.json)
      success=$(jq '.summary.successRate' results/.oha.json)
      p50=$(jq '.latencyPercentiles.p50' results/.oha.json)
      p95=$(jq '.latencyPercentiles.p95' results/.oha.json)
      p99=$(jq '.latencyPercentiles.p99' results/.oha.json)

      energy=$(energy_delta "$e0" "$e1")
      if [ -n "$energy" ]; then
        energy_net=$(awk -v j="$energy" -v w="$BASELINE_W" -v t="$DURATION" 'BEGIN { printf "%.6f", j - w * t }')
        jpk=$(awk -v j="$energy_net" -v n="$requests" 'BEGIN { if (n > 0) printf "%.6f", j / n * 1000; else print "" }')
      else
        energy_net=""; jpk=""
      fi

      echo "$server,$image,$image_bytes,$file,$file_bytes,$r,$DURATION,$CONC,$requests,$success,$rps,$p50,$p95,$p99,$rss_idle,$rss_load,$energy,$BASELINE_W,$energy_net,$jpk" >> "$OUT"
      echo "    $file  Lauf $r: $rps req/s, p99 ${p99}s, RSS $rss_load B${jpk:+, $jpk J/1k req}"
      r=$((r+1))
      sleep 3
    done
  done
done
rm -f results/.oha.json
echo "==> fertig: $OUT"
