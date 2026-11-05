#!/bin/sh
# Runs one program or test with the package's toolchain and dependencies:
#
#   sh scripts/run.sh tests/auth_test.ei [args...]     (eiderc run)
#   sh scripts/run.sh --test tests/foo.ei              (eiderc test)
#
# Useful while developing; scripts/test.sh runs them all and compares the output.
here=$(cd "$(dirname "$0")/.." && pwd -P)
. "$here/scripts/env.sh"
cd "$here" || exit 1
if [ "$1" = "--test" ]; then
  shift
  exec_cmd="test"
else
  exec_cmd="run"
fi
ei "$exec_cmd" "$@"
