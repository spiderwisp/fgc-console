#!/usr/bin/env bash
set -euo pipefail
app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
openbox --sm-disable &
wm_pid=$!
trap 'kill "$wm_pid" 2>/dev/null || true' EXIT
if command -v xset >/dev/null; then xset s off -dpms || true; fi
while true; do
    "$app_dir/FGCConsole.x86_64" --fullscreen -- --kiosk || true
    sleep 2
done
