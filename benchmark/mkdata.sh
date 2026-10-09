#!/bin/sh
# Erzeugt die drei Testdateien fuer den Benchmark. Deterministischer Inhalt,
# damit jeder Lauf dieselben Bytes ausliefert.
#
#   1 KiB    index.html   eine kleine HTML-Seite
#   100 KiB  figure.svg   eine Abbildung
#   10 MiB   data.bin     ein Daten-Download
set -eu
cd "$(dirname "$0")"
mkdir -p www

# 1 KiB HTML: gueltiges Dokument, mit Leerzeichen auf exakt 1024 Bytes aufgefuellt
head='<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>benchmark</title></head><body><h1>gatling-webserver benchmark</h1><p>'
tail='</p></body></html>
'
fill=$((1024 - ${#head} - ${#tail}))
{
  printf '%s' "$head"
  i=0; while [ $i -lt $fill ]; do printf 'x'; i=$((i+1)); done
  printf '%s' "$tail"
} > www/index.html

# 100 KiB SVG: viele Rechtecke, Groesse auf 102400 Bytes beschnitten
{
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000">\n'
  i=0; while [ $i -lt 1800 ]; do
    printf '<rect x="%d" y="%d" width="9" height="9" fill="#%02x%02x%02x"/>\n' $((i%100*10)) $((i/100*10)) $((i%256)) $((i*7%256)) $((i*13%256))
    i=$((i+1))
  done
  printf '</svg>\n'
} > www/figure.svg
head -c 102400 www/figure.svg > www/figure.tmp && mv www/figure.tmp www/figure.svg

# 10 MiB deterministische Binaerdaten (kein /dev/urandom, damit reproduzierbar)
if command -v python3 >/dev/null 2>&1; then
  python3 -c "import random; random.seed(42); open('www/data.bin','wb').write(random.randbytes(10485760))"
else
  LC_ALL=C awk 'BEGIN { srand(42); for (i = 0; i < 10485760; i++) printf "%c", int(rand() * 256) }' > www/data.bin
fi

chmod 644 www/index.html www/figure.svg www/data.bin
ls -l www/
