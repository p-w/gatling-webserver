# gatling - a high performance web server

Gatling is a small and fast HTTP webserver and reverse proxy that makes deploying microservices or websites easy.
Gatling is particularly good in situations with very high load.

![Docker Pulls](https://img.shields.io/docker/pulls/wilfahrt/gatling-webserver) ![Docker Image Size (tag)](https://img.shields.io/docker/image-size/wilfahrt/gatling-webserver/latest) ![GitHub last commit](https://img.shields.io/github/last-commit/p-w/gatling-webserver) ![Docker Image Version (latest by date)](https://img.shields.io/docker/v/wilfahrt/gatling-webserver) 

## Quick reference
* Maintained by: [PW](https://github.com/p-w/)
* Where to get help: [running the docker image](https://github.com/p-w/gatling-webserver), [fefe's gatling](https://www.fefe.de/gatling/)
* If you want to take part in gatling, please subscribe to the gatling mailing list (send an empty email to gatling-subscribe@fefe.de).

## Features
* Small! (125k static Linux-x86 binary with HTTP, FTP and SMB support)
* Fast! (measure for yourself, please)
* Scalable! (see this document, measured using tools that are included in the gatling distribution.
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

## gatling v0.17 - Example usage

Enable `docker` provider:

```yml
## gatling-webserver.yml

# Docker configuration backend
providers:
  docker:
    defaultRule: "Host(`{{ trimPrefix `/` .Name }}.docker.localhost`)"
```

Start gatling:

```bash
docker run -d -p 8080:8080 -p 80:80 \
-v /var/run/docker.sock:/var/run/docker.sock \
wilfahrt/gatling-webserver:latest
```

Start a backend server, named `test` with [traefik/whoami](https://hub.docker.com/r/traefik/whoami) (i.e. a tiny Go webserver that prints os information and HTTP request to output):

```bash
docker run -d --name test traefik/whoami
```

And finally, you can access to your `whoami` server through gatling, on the domain name `test.docker.localhost`:
