# gatling - a high performance web server, statically built with dietlibc.
#
# Two stages: the first one fetches dietlibc, libowfat and gatling from
# fefe's CVS and builds a static binary, the second one is a plain Alpine
# image that only carries that binary plus a small entrypoint script.

FROM alpine:3.22 AS build

RUN apk add --no-cache \
      make \
      gcc \
      cvs \
      zlib-dev \
      zlib-static \
      libc-dev \
      linux-headers

WORKDIR /tmp/src

RUN echo "**** fetch sources ****" && \
    cvs -Q -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co dietlibc && \
    cvs -Q -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co libowfat && \
    cvs -Q -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co gatling

RUN echo "**** build dietlibc ****" && \
    cd dietlibc && \
    make && \
    make install "bin-$(uname -m)/diet" && \
    ln -s /opt/diet/bin/diet /usr/local/bin/diet

RUN echo "**** build libowfat ****" && \
    cd libowfat && \
    diet make && \
    make install

RUN echo "**** build gatling ****" && \
    cd gatling && \
    diet make gatling && \
    strip gatling && \
    ./gatling -h 2>&1 | head -1


FROM alpine:3.22

LABEL org.opencontainers.image.title="gatling-webserver" \
      org.opencontainers.image.description="gatling - a high performance web server (static dietlibc build)" \
      org.opencontainers.image.authors="https://github.com/p-w" \
      org.opencontainers.image.source="https://github.com/p-w/gatling-webserver" \
      org.opencontainers.image.licenses="GPL-2.0"

COPY --from=build /tmp/src/gatling/gatling /gatling
COPY docker-entrypoint.sh /docker-entrypoint.sh

# Document root with a placeholder page. Mount your content over /var/www.
RUN mkdir -p /var/www && \
    chmod 755 /var/www /docker-entrypoint.sh && \
    printf '%s\n' \
      '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>gatling</title></head>' \
      '<body><h1>gatling is running</h1><p>Mount your content to <code>/var/www</code>.</p></body></html>' \
      > /var/www/index.html && \
    chmod 644 /var/www/index.html

# GATLING_OPTIONS  options passed to gatling, extra arguments to
#                  "docker run ... image ARGS" are appended
#                  -F no FTP, -S no SMB, -V no virtual hosting, -D no dir index
# GATLING_ROOT     document root, gatling starts there
# GATLING_CHROOT   1: chroot into GATLING_ROOT after binding the ports
# GATLING_USER     uid[:gid] to switch to after binding (empty: stay root)
ENV GATLING_OPTIONS="-F -S -V -D" \
    GATLING_ROOT="/var/www" \
    GATLING_CHROOT="1" \
    GATLING_USER="65534:65534"

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
