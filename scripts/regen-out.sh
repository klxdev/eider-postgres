#!/bin/sh
# Rewrites tests/*.out from what the tests print now (needs the same servers as scripts/test.sh).
# Look at the diff before committing it: a .out is the test's expectation.
#
#   sh scripts/regen-out.sh [test.ei ...]      (default: every tests/*_test.ei)
here=$(cd "$(dirname "$0")/.." && pwd -P)
. "$here/scripts/env.sh"
cd "$here" || exit 1
trap 'sh "$here/scripts/pg-down.sh"' EXIT
if [ $# -gt 0 ]; then tests="$*"; else tests=$(ls tests/*_test.ei); fi
sh "$here/scripts/pg-up.sh" > /dev/null || exit 3
for f in $tests; do
  case "$f" in *pg_tls_test.ei) continue ;; esac
  ei run "$f" > "${f%.ei}.out" 2>&1 < /dev/null
  echo "wrote ${f%.ei}.out"
done
sh "$here/scripts/pg-down.sh"
for f in $tests; do
  case "$f" in *pg_tls_test.ei) ;; *) continue ;; esac
  sh "$here/scripts/pg-up.sh" --tls > /dev/null || exit 3
  ei run "$f" > "${f%.ei}.out" 2>&1 < /dev/null
  echo "wrote ${f%.ei}.out"
done
