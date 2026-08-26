#!/usr/bin/env bash
# Copy the retired Docker volume into the native Codeg data directory.
# This is intentionally kept with the Codeg repository so the native service
# no longer depends on deployment files stored in the Container monorepo.
set -euo pipefail

SRC=/var/lib/docker/volumes/codeg_codeg-data/_data
DST=/home/pieye/.local/share/codeg

[ -d "$SRC" ] || { echo "[migrate] no docker volume at $SRC, nothing to copy"; exit 0; }
mkdir -p "$DST"

need_copy=0
if [ ! -e "$DST/codeg.db" ]; then
  need_copy=1
elif [ -f "$SRC/codeg.db" ] && [ "$SRC/codeg.db" -nt "$DST/codeg.db" ]; then
  need_copy=1
elif [ -f "$SRC/codeg.db-wal" ] && [ -f "$DST/codeg.db-wal" ] && [ "$SRC/codeg.db-wal" -nt "$DST/codeg.db-wal" ]; then
  need_copy=1
fi

if [ "$need_copy" -eq 0 ]; then
  echo "[migrate] native data is current, nothing to copy"
  exit 0
fi

echo "[migrate] copying docker volume state -> $DST"
find "$SRC" -mindepth 1 -maxdepth 1 ! -name .codeg -exec cp -a {} "$DST"/ \;
echo "[migrate] done"
