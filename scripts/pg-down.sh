#!/bin/sh
# Stops and removes the container that scripts/pg-up.sh started. Always exits 0.
NAME=${EIDER_PG_NAME:-eider-pg-test}
if command -v podman >/dev/null 2>&1; then
  podman rm -f "$NAME" >/dev/null 2>&1
elif command -v flatpak-spawn >/dev/null 2>&1; then
  flatpak-spawn --host podman rm -f "$NAME" >/dev/null 2>&1
fi
exit 0
