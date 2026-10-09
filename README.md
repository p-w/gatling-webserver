<div align="center">  
  <h1>gatling<br>a high performance web server</h1>
  Gatling is a <b>small and fast</b> HTTP webserver and reverse proxy that makes deploying microservices or websites easy. Gatling is particularly good in situations with very high load. It's designed to adhere green software standards. The size is only 10% of the next best webserver image, so sustainability is a core priority, just as important as performance, security, cost and accessibility. Let's <b>minimise carbon</b> and <b>maximise trust</b>.

  ![Docker Pulls](https://img.shields.io/docker/pulls/wilfahrt/gatling-webserver) ![Docker Image Size (tag)](https://img.shields.io/docker/image-size/wilfahrt/gatling-webserver/latest) ![GitHub last commit](https://img.shields.io/github/last-commit/p-w/gatling-webserver) ![Docker Image Version (latest by date)](https://img.shields.io/docker/v/wilfahrt/gatling-webserver) ![GitHub](https://img.shields.io/github/license/p-w/gatling-webserver)
</div>

## Quick reference
* Maintained by: [PW](https://github.com/p-w/)
* Get it on [dockerhub](https://hub.docker.com/r/wilfahrt/gatling-webserver)
* Where to get help: [running the docker image](https://github.com/p-w/gatling-webserver), [fefe's gatling](https://www.fefe.de/gatling/), [gatling(1) man page](https://manpages.debian.org/unstable/gatling/gatling.1.en.html)
* If you want to take part in gatling, please subscribe to the gatling mailing list (send an empty email to gatling-subscribe@fefe.de).

## Features
* Small! (125k static Linux-x86 binary with HTTP, FTP and SMB support)
* Fast! (measure for yourself, please)
* Scalable! (see README.performance in the gatling distribution, measured using tools that are included there)
* Uses platform-specific performance and scalability APIs on Linux 2.4, Linux 2.6, NetBSD current (2.0+), FreeBSD 4+, OpenBSD 3.4+, Solaris 9+, AIX 5L, IRIX 6.5+, MacOS X Panther+, HP-UX 11+
* connection keep-alive
* el-cheapo virtual domains (similar to thttpd)
* IPv6 support
* Content-Range
* transparent content negotiation (will serve foo.html.gz if foo.html was asked for and browser indicates it understands deflate)
* With optional directory index generation
* Will only serve world readable files (so you don't export files accidentally)
* Supports FTP and FTP upload as well (upload only to world writable directories and the files won't be downloadable unless you chmod a+r them manually)
* CGI support for HTTP, also SCGI and FastCGI (over IP sockets, not Unix Domain yet)
* El-cheapo .htaccess support (see README.htaccess)
* Quick-and-dirty SSL/TLS support (see README.tls)
* Can detect some common mime types itself, like file(1)
* Read-only SMB1 support (was once good enough to read a specific file from Windows or using smbclient from Samba but now SMB1 is deprecated, so less useful)

## Usage

Pull the image:

```bash
docker pull wilfahrt/gatling-webserver
```

Serve the current directory on port 8080:

```bash
docker run -d --name web -p 8080:80 -v "$PWD":/var/www:ro wilfahrt/gatling-webserver
```

gatling binds port 80 as root, then chroots into `/var/www` and drops to uid 65534 (nobody). Only world readable files are served, so make sure your content is `o+r`.

### Configuration

The entrypoint builds the gatling command line from these variables. Anything you pass after the image name is appended as additional gatling arguments.

| Variable | Default | Meaning |
|---|---|---|
| `GATLING_OPTIONS` | `-F -S -V -D` | base options: no FTP, no SMB, no virtual hosting, no directory index |
| `GATLING_ROOT` | `/var/www` | document root, gatling is started there |
| `GATLING_CHROOT` | `1` | chroot into `GATLING_ROOT` after binding the ports (`0` to disable) |
| `GATLING_USER` | `65534:65534` | uid[:gid] to switch to after binding (empty to stay root) |

Frequently used gatling options:

| Option | Meaning |
|---|---|
| `-d` / `-D` | enable / disable directory index generation |
| `-v` / `-V` | enable / disable virtual hosting (directories named `host:port` or `default` inside the root) |
| `-n` | no access log on stdout |
| `-T seconds` | connection timeout (default 23) |
| `-I index.php` | additionally try this file for directory requests |
| `-O F/ip/port/regex` | forward matching requests to a FastCGI backend (`S` for SCGI, no prefix for HTTP proxy); needs a `.proxy` file in the root, the entrypoint creates it |
| `-A rpm` | tarpit clients with more than `rpm` requests per minute |

Example with directory listing and a longer timeout:

```bash
docker run -d -p 8080:80 -v "$PWD":/var/www:ro -e GATLING_OPTIONS="-F -S -V -d" wilfahrt/gatling-webserver -T 60
```

## Operating scenarios

Each scenario below has a complete, ready-to-run `docker compose` setup with a `test.sh` smoke test under [`scenarios/`](scenarios/). The snippets here show the essential part.

### Static website

The plain case: gatling serves a directory, chrooted, as nobody, without directory listings. Add `-d` to `GATLING_OPTIONS` if you want listings for folders without an `index.html`.

```yaml
services:
  web:
    image: wilfahrt/gatling-webserver
    volumes:
      - ./www:/var/www:ro
    ports:
      - "80:80"
    read_only: true
```

gatling also serves `foo.html.gz` when `foo.html` is requested and the browser accepts gzip, so pre-compressed assets are a cheap win. Full example: [`scenarios/01-static`](scenarios/01-static/).

### WordPress with php-fpm

gatling does not run PHP itself but forwards `.php` requests to php-fpm via FastCGI. Three things to know:

* `-O` needs an IP address, not a host name, so give php-fpm a fixed address in the compose network.
* `SCRIPT_FILENAME` is built from gatling's working directory, so both containers must mount the WordPress volume under the same path and chroot has to be off.
* gatling has no URL rewriting. Use "Plain" permalinks or the PATH_INFO style (`/index.php/%year%/%postname%/`).

```yaml
services:
  php:
    image: wordpress:php8.3-fpm-alpine
    volumes:
      - wp:/var/www/html
    networks:
      backend:
        ipv4_address: 172.28.10.10

  web:
    image: wilfahrt/gatling-webserver
    environment:
      GATLING_ROOT: /var/www/html
      GATLING_CHROOT: "0"
      GATLING_OPTIONS: '-F -S -V -D -I index.php -O F/172.28.10.10/9000/\.php'
    volumes:
      - wp:/var/www/html
    ports:
      - "80:80"
    networks:
      - backend
```

The entrypoint creates the `.proxy` marker that gatling requires for proxy mode. Full stack with MariaDB: [`scenarios/02-wordpress-phpfpm`](scenarios/02-wordpress-phpfpm/).

### Tor hidden service

gatling is a good fit as the web backend of an onion service: it is small, sends no `Server` header, and `-n` switches the access log off so visitors leave no traces in the container. Do not publish a host port, only Tor may reach the web container.

```yaml
services:
  web:
    image: wilfahrt/gatling-webserver
    environment:
      GATLING_OPTIONS: "-F -S -V -D -n"
    volumes:
      - ./site:/var/www:ro
    networks:
      internal:
        ipv4_address: 172.28.20.10

  tor:
    image: alpine:3.22
    command: sh -c "apk add --no-cache tor && chown -R tor:tor /var/lib/tor && chmod 700 /var/lib/tor/hs && exec tor -f /etc/tor/torrc"
    volumes:
      - ./tor/torrc:/etc/tor/torrc:ro
      - tor-keys:/var/lib/tor/hs
    networks:
      - internal
```

```
# torrc
User tor
HiddenServiceDir /var/lib/tor/hs/
HiddenServicePort 80 172.28.20.10:80
```

Tor resolves the target once at startup, hence the fixed IP. Back up `hs_ed25519_secret_key` from the `tor-keys` volume, otherwise the `.onion` address changes when the volume is recreated. Keep the site self-contained (no CDN, fonts or trackers), every request that leaves the Tor circuit can deanonymise a visitor. Full example with test: [`scenarios/03-tor-hidden-service`](scenarios/03-tor-hidden-service/).

### TLS with Let's Encrypt

The image ships the plain `gatling` binary without TLS. Terminate TLS in front of it with Caddy, which obtains and renews Let's Encrypt certificates on its own and redirects HTTP to HTTPS:

```yaml
services:
  caddy:
    image: caddy:2-alpine
    ports: ["80:80", "443:443", "443:443/udp"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data

  web:
    image: wilfahrt/gatling-webserver
    volumes:
      - ./www:/var/www:ro
```

```
# Caddyfile
www.example.org {
    reverse_proxy web:80
}
```

Alternatives (certbot with webroot, DNS-01, `tlsgatling`) and the `/.well-known/` pitfall are covered in [`docs/lets-encrypt.md`](docs/lets-encrypt.md) (German). Full example: [`scenarios/04-tls-letsencrypt`](scenarios/04-tls-letsencrypt/).

## Build

```bash
sh build.sh                 # -> wilfahrt/gatling-webserver:dev
```

The Dockerfile fetches dietlibc, libowfat and gatling from fefe's CVS, builds a static binary and copies it into a fresh Alpine image. The CI workflow in `.github/workflows/build.yml` builds the image and runs the smoke tests of scenarios 1 and 2.

<div align="center">
  <hr>
  <small>a <a href="https://pw.is/" target="_blank">PW</a> project</small>
</div>
