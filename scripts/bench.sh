#!/bin/sh
# Round trips per second and rows per second against a real server (bench/bench.ei).
#
#   sh scripts/bench.sh [N]       N round trips per measure (default 5000)
#
# Starts the container with scripts/pg-up.sh (exit 3 without podman), stops it afterwards.
here=$(cd "$(dirname "$0")/.." && pwd -P)
. "$here/scripts/env.sh"
cd "$here" || exit 1
trap 'sh "$here/scripts/pg-down.sh"' EXIT
sh "$here/scripts/pg-up.sh" || exit 3
mkdir -p target
ei build bench/bench.ei -o target/bench || exit 1
./target/bench "$@"
