#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 ]] || { echo 'Usage: build.sh FGCConsole.x86_64 DeepSignal-Linux.zip OUTPUT_DIRECTORY' >&2; exit 1; }
source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
binary="$(realpath "$1")"
game="$(realpath "$2")"
mkdir -p "$3"
output="$(realpath "$3")"
docker build -t fgc-os-builder:0.2.0 "$source_root/os"
docker volume create fgc-os-build >/dev/null
docker run --rm --cap-add SYS_ADMIN --security-opt apparmor=unconfined \
  --mount type=volume,source=fgc-os-build,target=/build \
  --mount "type=bind,source=$source_root,target=/src,readonly" \
  --mount "type=bind,source=$binary,target=/artifacts/FGCConsole.x86_64,readonly" \
  --mount "type=bind,source=$game,target=/artifacts/DeepSignal-Linux.zip,readonly" \
  --mount "type=bind,source=$output,target=/out" \
  fgc-os-builder:0.2.0 python3 /src/os/assemble.py
