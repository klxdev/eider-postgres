#!/bin/sh
# eider-postgres's tests.
#
#   sh scripts/test.sh             scripts/build.sh, then every test
#   NOBUILD=1 sh scripts/test.sh   skip scripts/build.sh (the locks are already fetched)
#   NODB=1 sh scripts/test.sh      only the tests that need no server
#   PG_VERSIONS="16 17 18" sh scripts/test.sh   run the server tests against each (default 17)
#   ASAN=1 sh scripts/test.sh      also run the server-free tests under AddressSanitizer and UBSan
#
# Every tests/*_test.ei is run with the toolchain's compiler (`eider run`) and its output compared
# with the .out next to it. Three kinds:
#
#   no server:   auth_test, wire_test, codec_test, hostile_server_test (a fake server on the
#                loopback interface that sends broken and hostile messages)
#   a server:    pg_*_test, against a real PostgreSQL in a container that scripts/pg-up.sh starts
#                (podman; docker.io/library/postgres:$VERSION) and scripts/pg-down.sh removes, also
#                when a test fails or this script is interrupted. pg_tls_test runs against a second
#                server with ssl=on. When there is no podman or no image, they are `skip`ped with
#                the reason and the exit code is still 0.
#   TSan:        the tests that use tasks (hostile_server_test, pg_pool_test, pg_tls_test) are built
#                once under ThreadSanitizer and run once more, when $CC can build such a program.
#
# Prints `ok   <test>`, `skip <test>: why` or `FAIL <test>` with a diff, then `ALL OK`; exits 1 on a
# failure, 2 when there is no usable toolchain (scripts/env.sh).
NOSERVER="tests/auth_test.ei tests/wire_test.ei tests/codec_test.ei tests/hostile_server_test.ei"
SERVER="tests/pg_query_test.ei tests/pg_tx_test.ei tests/pg_auth_test.ei tests/pg_cancel_test.ei tests/pg_copy_test.ei tests/pg_typed_test.ei tests/pg_pool_test.ei"
TLSTEST="tests/pg_tls_test.ei"
TSAN_NOSERVER="tests/hostile_server_test.ei"
TSAN_SERVER="tests/pg_pool_test.ei"
TSAN_TLS="tests/pg_tls_test.ei"
here=$(cd "$(dirname "$0")/.." && pwd -P)
if [ -z "$NOBUILD" ]; then
  sh "$here/scripts/build.sh" || exit $?
fi
. "$here/scripts/env.sh"
cd "$here" || exit 1
fail=0
T=$(mktemp -d)
cleanup() { sh "$here/scripts/pg-down.sh"; rm -rf "$T"; }
trap cleanup EXIT
trap 'exit 130' INT TERM

run() { # <test>: run with eider and compare
  f=$1
  got=$(ei run "$f" 2>&1 < /dev/null)
  if [ "$got" = "$(cat "${f%.ei}.out")" ]; then echo "ok   $f"; else echo "FAIL $f"; echo "$got" | diff "${f%.ei}.out" - | head -10; fail=1; fi
}

tsan_ok=
tsan_probe() {
  if [ -z "$tsan_ok" ]; then
    printf 'int main(void) { return 0; }\n' > "$T/probe.c"
    if ${CC:-cc} -fsanitize=thread -o "$T/probe" "$T/probe.c" 2>/dev/null && "$T/probe"; then tsan_ok=yes; else tsan_ok=no; fi
  fi
  [ "$tsan_ok" = yes ]
}

tsan() { # <tests>
  if tsan_probe; then
    for f in "$@"; do
      if ! (EIDER_CACHE=off EIDER_CFLAGS="-fsanitize=thread -g"; export EIDER_CACHE EIDER_CFLAGS; ei build "$f" -o "$T/t") > "$T/log" 2>&1; then
        echo "FAIL $f (tsan): build"; cat "$T/log"; fail=1; continue
      fi
      got=$(TSAN_OPTIONS="halt_on_error=1 exitcode=66" "$T/t" < /dev/null 2>&1)
      if [ "$got" = "$(cat "${f%.ei}.out")" ]; then echo "ok   $f (tsan)"; else echo "FAIL $f (tsan)"; echo "$got" | diff "${f%.ei}.out" - | head -20; fail=1; fi
    done
  else
    echo "skip tsan runs ($*): ${CC:-cc} cannot build a -fsanitize=thread program"
  fi
}

for f in $NOSERVER; do run "$f"; done
tsan $TSAN_NOSERVER

if [ -n "$NODB" ]; then
  echo "skip the server tests: NODB is set"
else
  for v in ${PG_VERSIONS:-17}; do
    echo "-- PostgreSQL $v"
    sh "$here/scripts/pg-up.sh" --version "$v" > "$T/up.log" 2>&1
    rc=$?
    if [ $rc = 0 ]; then
      cat "$T/up.log"
      for f in $SERVER; do run "$f"; done
      tsan $TSAN_SERVER
      sh "$here/scripts/pg-down.sh"
      sh "$here/scripts/pg-up.sh" --tls --version "$v" > "$T/up.log" 2>&1
      rc=$?
      if [ $rc = 0 ]; then
        cat "$T/up.log"
        for f in $TLSTEST; do run "$f"; done
        tsan $TSAN_TLS
      elif [ $rc = 3 ]; then
        echo "skip $TLSTEST: $(tail -1 "$T/up.log")"
      else
        echo "FAIL pg-up --tls (exit $rc)"; cat "$T/up.log"; fail=1
      fi
      sh "$here/scripts/pg-down.sh"
    elif [ $rc = 3 ]; then
      for f in $SERVER $TLSTEST; do echo "skip $f: $(tail -1 "$T/up.log")"; done
    else
      echo "FAIL pg-up (exit $rc)"; cat "$T/up.log"; fail=1
    fi
  done
fi

# the sanitized crypto backend is built by an eider-lang checkout's scripts/crypto-build.sh
if [ -n "$ASAN" ] && [ ! -f "$toolchain/scripts/crypto-build.sh" ]; then
  echo "skip asan runs: $toolchain is an installed toolchain (the sanitized crypto backend needs an eider-lang checkout: EIDER_TOOLCHAIN=...)"
  ASAN=
fi
if [ -n "$ASAN" ]; then
  for f in $NOSERVER; do
    if ! (EIDER_CACHE=off EIDER_CRYPTO_SAN=1 EIDER_CFLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g"; export EIDER_CACHE EIDER_CRYPTO_SAN EIDER_CFLAGS; ei build "$f" -o "$T/a") > "$T/log" 2>&1; then
      echo "FAIL $f (asan): build"; cat "$T/log"; fail=1; continue
    fi
    got=$(ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 "$T/a" < /dev/null 2>&1)
    if [ "$got" = "$(cat "${f%.ei}.out")" ]; then echo "ok   $f (asan+ubsan)"; else echo "FAIL $f (asan+ubsan)"; echo "$got" | diff "${f%.ei}.out" - | head -20; fail=1; fi
  done
fi
[ $fail = 0 ] && echo "ALL OK"
exit $fail
