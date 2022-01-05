FROM       alpine:latest
MAINTAINER https://github.com/p-w
LABEL      Description="gatling - a high performance web server (built with dietlibc)"

# avoid starting FTP and SMB if not needed (otherwise on by default)
ENV        GATLING_OPTIONS="-F -S"
EXPOSE     80

RUN \
  echo "**** install build packages ****" && \
  #apk add --no-cache --virtual=build-dependencies \
  apk add --no-cache \
    make \
    gcc \
    cvs \
    zlib \
    zlib-dev \
    zlib-static \
    libc-dev \
    openssl \
    openssl-dev && \
  echo "**** download build packages ****" && \
  cd /tmp && \
  cvs -Q -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co dietlibc && \
  cvs -Q -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co libowfat && \
  cvs -Q -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co gatling && \
  echo "**** build runtime packages ****" && \
  cd dietlibc && \
  make && \
  make install bin-x86_64/diet && \
  ln -s /opt/diet/bin/diet /usr/local/bin/diet && \
  cd ../libowfat && \
  diet make && \
  make install && \
  cd ../gatling && \
  diet make gatling && \
  mv gatling / && \
  echo "**** cleanup ****" && \
  apk del make gcc cvs zlib-dev libc-dev openssl-dev && \
  rm -rf /tmp/*

ENTRYPOINT /gatling ${GATLING_OPTIONS}
