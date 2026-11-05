#!/bin/sh
# Starts a disposable PostgreSQL server in a container for the integration tests.
#
#   sh scripts/pg-up.sh [--tls] [--version N]
#
# The server listens on 127.0.0.1:$EIDER_PG_PORT (default 55432), database `eiderdb`, with these
# roles (the tests know the passwords):
#
#   eider        superuser, password eider_pw, SCRAM-SHA-256
#   scram_user   password scram_pw, SCRAM-SHA-256
#   md5_user     password md5_pw, stored as an MD5 hash, pg_hba method md5
#   pw_user      password clear_pw, pg_hba method password (cleartext)
#   trust_user   no password, pg_hba method trust
#
# --tls turns on ssl with a certificate for localhost and 127.0.0.1 made by eider-tls's
# tests/pki.sh (written to target/pg/pki; root.pem is the CA). --version picks the image tag
# (docker.io/library/postgres:N; default 17, or $EIDER_PG_VERSION).
#
# The container is named $EIDER_PG_NAME (default eider-pg-test) and started with --rm; stop it
# with scripts/pg-down.sh. podman runs on the host through flatpak-spawn when this is a toolbox
# (no podman inside), else directly.
#
# Exit codes: 0 up and ready; 3 no podman, no image or the server did not come up (callers
# skip their database tests and say why); 1 other failures.
here=$(cd "$(dirname "$0")/.." && pwd -P)
NAME=${EIDER_PG_NAME:-eider-pg-test}
PORT=${EIDER_PG_PORT:-55432}
VERSION=${EIDER_PG_VERSION:-17}
TLS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tls) TLS=1 ;;
    --version) shift; VERSION=$1 ;;
    *) echo "usage: pg-up.sh [--tls] [--version N]" >&2; exit 1 ;;
  esac
  shift
done
if command -v podman >/dev/null 2>&1; then
  P() { podman "$@"; }
elif command -v flatpak-spawn >/dev/null 2>&1 && flatpak-spawn --host podman --version >/dev/null 2>&1; then
  P() { flatpak-spawn --host podman "$@"; }
else
  echo "pg-up: no podman (neither here nor on the host through flatpak-spawn)" >&2
  exit 3
fi
IMAGE=docker.io/library/postgres:$VERSION
if ! P image exists "$IMAGE" 2>/dev/null; then
  echo "pg-up: pulling $IMAGE" >&2
  P pull -q "$IMAGE" >/dev/null 2>&1 || { echo "pg-up: image $IMAGE is not available (no network?)" >&2; exit 3; }
fi
P rm -f "$NAME" >/dev/null 2>&1

certs=
if [ "$TLS" = 1 ]; then
  tlsdir=${EIDER_TLS:-$here/../eider-tls}
  pki=$here/target/pg/pki
  rm -rf "$pki"
  if ! sh "$tlsdir/tests/pki.sh" "$pki" >/dev/null 2>&1; then
    echo "pg-up: cannot make the test certificates ($tlsdir/tests/pki.sh needs openssl)" >&2
    exit 3
  fi
  certs=$(cd "$pki" && pwd -P)
fi

# the same shell script starts the server: with --tls it first installs the key where the server
# user can own it (a key file must be mode 0600 and owned by the server's user)
if [ "$TLS" = 1 ]; then
  start='mkdir -p /var/lib/postgresql/certs && cp /certs/ec.pem /var/lib/postgresql/certs/server.crt && cp /certs/ec.key /var/lib/postgresql/certs/server.key && chown postgres:postgres /var/lib/postgresql/certs/* && chmod 600 /var/lib/postgresql/certs/server.key && exec docker-entrypoint.sh postgres -c ssl=on -c ssl_cert_file=/var/lib/postgresql/certs/server.crt -c ssl_key_file=/var/lib/postgresql/certs/server.key -c fsync=off -c synchronous_commit=off -c full_page_writes=off -c max_connections=200'
  P run -d --rm --name "$NAME" -p "127.0.0.1:$PORT:5432" \
    -e POSTGRES_USER=eider -e POSTGRES_PASSWORD=eider_pw -e POSTGRES_DB=eiderdb \
    -v "$certs:/certs:ro" --security-opt label=disable \
    --entrypoint sh "$IMAGE" -c "$start" >/dev/null || { echo "pg-up: cannot start the container" >&2; exit 3; }
else
  P run -d --rm --name "$NAME" -p "127.0.0.1:$PORT:5432" \
    -e POSTGRES_USER=eider -e POSTGRES_PASSWORD=eider_pw -e POSTGRES_DB=eiderdb \
    "$IMAGE" -c fsync=off -c synchronous_commit=off -c full_page_writes=off -c max_connections=200 >/dev/null || { echo "pg-up: cannot start the container" >&2; exit 3; }
fi

# ready: the final server (the init phase listens on the socket only) answers on TCP
i=0
while [ $i -lt 120 ]; do
  if P exec "$NAME" pg_isready -q -h 127.0.0.1 -U eider -d eiderdb >/dev/null 2>&1; then break; fi
  i=$((i + 1))
  sleep 0.5
done
if [ $i -ge 120 ]; then
  echo "pg-up: the server did not become ready" >&2
  P logs "$NAME" 2>&1 | tail -20 >&2
  P rm -f "$NAME" >/dev/null 2>&1
  exit 3
fi
# the roles and pg_hba.conf, over the local socket (trusted)
P exec -i "$NAME" psql -q -v ON_ERROR_STOP=1 -U eider -d eiderdb >/dev/null <<'EOF' || { echo "pg-up: cannot create the roles" >&2; exit 1; }
CREATE ROLE scram_user LOGIN PASSWORD 'scram_pw';
SET password_encryption = 'md5';
CREATE ROLE md5_user LOGIN PASSWORD 'md5_pw';
RESET password_encryption;
CREATE ROLE pw_user LOGIN PASSWORD 'clear_pw';
CREATE ROLE trust_user LOGIN;
EOF
P exec "$NAME" sh -c 'printf "local all all trust\nhost all md5_user all md5\nhost all pw_user all password\nhost all trust_user all trust\nhost all all all scram-sha-256\n" > "$PGDATA/pg_hba.conf"' || { echo "pg-up: cannot write pg_hba.conf" >&2; exit 1; }
P exec "$NAME" psql -q -U eider -d eiderdb -c 'SELECT pg_reload_conf()' >/dev/null || exit 1
echo "pg-up: postgres $VERSION on 127.0.0.1:$PORT (tls=$TLS)"
