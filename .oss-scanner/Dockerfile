# Build environment for Anthropic's OSS Scanner (https://red.anthropic.com/oss-scanner/).
#
# The scanner builds this file with the repository checkout as build context,
# then audits the image without network access. Everything the agent needs is
# therefore fetched and built here: the gatling C sources from fefe's CVS, the
# dietlibc and libowfat libraries it links against, the static gatling binary,
# and the tools to exercise it (curl, php for FastCGI, python3).
#
# Layout inside the image:
#   /src                 this repository (Dockerfile, entrypoint, scenarios, benchmark)
#   /src/vendor/gatling  gatling sources as built (not part of this repo, fetched from CVS)
#   /src/vendor/libowfat libowfat sources
#   /src/vendor/dietlibc dietlibc sources
#   /src/build/gatling   the static binary, unstripped
#   /gatling             same binary at the path the entrypoint expects
#   /var/www             a small document root for manual tests

FROM alpine:3.22

RUN apk add --no-cache \
      make gcc cvs zlib-dev zlib-static libc-dev linux-headers \
      bash curl python3 py3-yaml php83 php83-fpm jq

# scanner contract: the checkout lives inside the image, at /src
COPY . /src
WORKDIR /src

# Fetch the upstream sources (network is available during the build only).
RUN mkdir -p /src/vendor && cd /src/vendor && \
    cvs -Q -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co dietlibc && \
    cvs -Q -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co libowfat && \
    cvs -Q -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co gatling

# Build dietlibc, libowfat and gatling exactly as the production Dockerfile does.
# The binary is kept unstripped so that symbols are available to gdb and valgrind.
RUN cd /src/vendor/dietlibc && make && make install "bin-$(uname -m)/diet" && \
    ln -s /opt/diet/bin/diet /usr/local/bin/diet && \
    cd /src/vendor/libowfat && diet make && make install && \
    cd /src/vendor/gatling && diet make gatling && \
    mkdir -p /src/build && cp gatling /src/build/gatling && cp gatling /gatling && \
    cp /src/docker-entrypoint.sh /docker-entrypoint.sh && chmod 755 /docker-entrypoint.sh

# Minimal document root plus the scenario content, for exercising the server by hand.
RUN mkdir -p /var/www && cp -r /src/scenarios/01-static/www/. /var/www/ && chmod -R a+rX /var/www

# Cheap smoke test so the image is known to work. A failing test must not abort the build.
RUN (cd /var/www && exec /gatling -F -S -V -D -p 8000 -u 65534:65534) & pid=$!; sleep 1; \
    curl -fsS http://127.0.0.1:8000/ | grep -q "statische Dateien" && echo "smoke test ok" \
      || echo "WARNING: smoke test failed"; \
    kill $pid 2>/dev/null || true

ENV GATLING_OPTIONS="-F -S -V -D" \
    GATLING_ROOT="/var/www" \
    GATLING_CHROOT="1" \
    GATLING_USER="65534:65534"
