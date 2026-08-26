#!/usr/bin/env bash
# Native codeg-server launcher for this repository's deployment.
# CODEG_TOKEN comes from the configured Infisical folder /codeg.
set -euo pipefail

if [[ "${WITH_INFISICAL_CHILD:-}" != 1 ]]; then
  export WITH_INFISICAL_CHILD=1
  INFISICAL_WRAPPER="${INFISICAL_WRAPPER:-/home/pieye/Container/scripts/with-infisical}"
  exec "$INFISICAL_WRAPPER" codeg -- "$0" "$@"
fi

export HOME=/home/pieye
REPO_ROOT=/home/pieye/Container/codeg-repo
SERVER_BIN="${CODEG_SERVER_BIN:-$REPO_ROOT/src-tauri/target/release/codeg-server}"
export PATH="$REPO_ROOT/src-tauri/target/release:/home/pieye/.local/bin:/usr/local/bin:/usr/bin:/bin"
export CODEG_HOST=0.0.0.0
export CODEG_PORT=3080
export CODEG_DATA_DIR=/home/pieye/.local/share/codeg
export CODEG_HOME=/home/pieye/.local/share/codeg
export CODEG_STATIC_DIR="${CODEG_STATIC_DIR:-$REPO_ROOT/out}"
export TZ=Asia/Taipei

if [[ ! -x "$SERVER_BIN" ]]; then
  echo "codeg: release server binary not found: $SERVER_BIN" >&2
  echo "codeg: build it from $REPO_ROOT with 'pnpm run server:build'" >&2
  exit 1
fi

exec "$SERVER_BIN" --supervise
