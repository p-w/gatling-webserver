# Threat model for gatling-webserver

## What this project is

`gatling-webserver` is a container image that packages `gatling`, a small
static HTTP/FTP/SMB server by Felix von Leitner written in C against
`dietlibc` and `libowfat`. This repository contains the Dockerfile, a POSIX
shell entrypoint that assembles the gatling command line from environment
variables, `docker compose` scenarios (static files, WordPress via FastCGI,
Tor onion service, TLS via a reverse proxy), a benchmark harness and
documentation. The gatling C sources are not part of this repository; the
build fetches them from upstream CVS into `/src/vendor/gatling`.

## Where untrusted input enters

- **HTTP requests** on the port gatling listens on. Request line, headers,
  URL-encoded paths, `Host` header (used for virtual host directory
  selection), `Range` headers, `Accept-Encoding`, request bodies forwarded
  to FastCGI/SCGI/HTTP backends. Every byte of a request is adversarial.
- **FTP and SMB** are disabled by the image defaults (`-F -S`) but remain in
  the binary. Treat them as in scope with lower priority; a finding there
  matters only if it is reachable with the default options or trivially
  enabled.
- **Backend responses** in proxy mode (`-O`): the FastCGI/SCGI/HTTP backend
  is semi-trusted, but malformed backend responses should not crash gatling.
- **Environment variables** `GATLING_OPTIONS`, `GATLING_ROOT`,
  `GATLING_CHROOT`, `GATLING_USER` are set by the operator and trusted.
  Word splitting in the entrypoint is intended.
- **Files in the document root** are trusted content, but file names,
  symlinks and permissions are relevant: gatling promises to serve only
  world-readable files and to never serve paths containing `/.`.

## Components that matter most

1. `/src/vendor/gatling/http.c` and `gatling.c`: request parsing, path
   decoding and the `/.` to `/:` rewrite, virtual host `chdir`, `Range`
   handling, directory index generation, CGI/proxy environment
   construction (`fmt_cgivars`), FastCGI/SCGI framing.
2. `/src/vendor/libowfat`: the string, buffer and socket primitives
   gatling relies on (`scan_urlencoded`, `fmt_*`, `io_*`, `array_*`).
3. `/src/docker-entrypoint.sh`: privilege handling (chroot, uid switch),
   the `.proxy` marker creation and option assembly.
4. `/src/Dockerfile`: supply chain of the production image (CVS over
   unauthenticated pserver is a known, accepted limitation; report it only
   if you have a concrete improvement).

Out of scope: `/src/benchmark/`, `/src/paper/`, `/src/docs/`, the
`scenarios/*/test.sh` scripts, the third-party images referenced by the
compose files (nginx, caddy, mariadb, wordpress, tor), and the `dl`,
`bench`, `httpbench` and other auxiliary tools in the gatling tree.

## How to exercise it

- Static serving: `cd /var/www && /gatling -F -S -V -d -p 8000` then
  `curl -v http://127.0.0.1:8000/`. `/var/www` contains `index.html`,
  `assets/`, `downloads/` and a `.secret` file that must never be served.
- Path handling: use `curl --path-as-is` for `/../`, `/./`, `%2e%2e`,
  overlong and NUL-containing encodings.
- Virtual hosting: create directories named `host:8000` and `default`,
  start without `-V`, vary the `Host` header.
- FastCGI: `php-fpm83` is installed. Point it at a directory with a PHP
  file, `touch .proxy`, start gatling with `-I index.php -O
  'F/127.0.0.1/9000/\.php'` and send requests with PATH_INFO, query
  strings, large bodies and odd headers.
- Directory index (`-d`), `Range` and multi-range requests, pre-compressed
  `.gz` negotiation, keep-alive pipelining, `.htaccess` basic auth.
- The binary is unstripped; `gdb`, `strace` and `valgrind` are useful.
  gatling is single-process and event driven, so a crash or hang affects
  all clients.

## How to rate severity

- **Critical:** remote code execution or memory corruption controllable by
  an unauthenticated HTTP client with the image defaults
  (`-F -S -V -D`, chroot, uid 65534).
- **High:** reading files outside the document root or files that are not
  world-readable; escaping the chroot; serving a path containing `/.`;
  memory corruption that is only reachable with non-default options
  (FTP, SMB, proxy mode, virtual hosting); privilege escalation back to
  root after the uid switch.
- **Medium:** denial of service by a single client (crash, infinite loop,
  unbounded memory) against the defaults; directory listing or
  information disclosure beyond what the operator published; request
  smuggling or header injection toward a FastCGI backend.
- **Low:** denial of service that needs many connections; issues only in
  FTP upload or SMB; weaknesses in the auxiliary tools; hardening
  suggestions for the entrypoint without a demonstrated impact.

Do not report: the absence of TLS in the image (documented, handled by a
reverse proxy), the `Server: Gatling/0.17` header (known, not
configurable), the lack of HTTP/2, the use of HTTP/1.x only, and the
unauthenticated CVS checkout unless you can show a practical attack during
the build.

## Reports and patches

One report per root cause, deduplicated by the function where the bug is.
Include a reproducer as a shell snippet using `curl` or `printf | nc`
against a locally started gatling, the exact command line used to start
it, and the observed crash or output. Patches against the gatling sources
should be minimal unified diffs against `/src/vendor/gatling`; patches to
this repository's own files (entrypoint, Dockerfile) can be merge-ready.
Upstream gatling issues will be forwarded to Felix von Leitner; please
state clearly whether a finding lies in gatling, libowfat, dietlibc or in
this repository.
