#!/bin/sh
# Entrypoint for the gatling-webserver image.
#
# Builds the gatling command line from environment variables and appends
# any extra arguments given to "docker run ... image ARGS":
#
#   GATLING_OPTIONS  base options            (default: -F -S -V -D)
#   GATLING_ROOT     document root           (default: /var/www)
#   GATLING_CHROOT   1 = chroot into root    (default: 1)
#   GATLING_USER     uid[:gid] after binding (default: 65534:65534, "" = none)
#
# gatling serves the directory it is started in, so the script changes into
# GATLING_ROOT first. Without this, the old image served the container's
# root file system.
set -eu

ROOT="${GATLING_ROOT:-/var/www}"
if ! cd "$ROOT"; then
  echo "gatling: GATLING_ROOT=$ROOT does not exist" >&2
  exit 1
fi

# word splitting of GATLING_OPTIONS is intended, quotes are not interpreted
# shellcheck disable=SC2086
set -- ${GATLING_OPTIONS:-} "$@"

if [ "${GATLING_CHROOT:-1}" = "1" ]; then
  set -- -c "$ROOT" "$@"
fi

if [ -n "${GATLING_USER:-}" ]; then
  set -- -u "$GATLING_USER" "$@"
fi

# Proxy/FastCGI mode (-O) only works when a ".proxy" marker file exists in
# the document root. Create it if it is missing and the root is writable.
case " $* " in
  *" -O"*)
    if [ ! -e .proxy ]; then
      if touch .proxy 2>/dev/null; then
        echo "gatling: created $ROOT/.proxy to enable -O proxy mode" >&2
      else
        echo "gatling: warning: -O given but $ROOT/.proxy is missing and cannot be created (read-only root?)" >&2
      fi
    fi
    ;;
esac

exec /gatling "$@"
