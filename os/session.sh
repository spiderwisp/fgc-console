#!/bin/sh
set -eu
umask 077
export XDG_CURRENT_DESKTOP=FGC
export XDG_SESSION_DESKTOP=fgc
export SDL_JOYSTICK_HIDAPI=1
mkdir -p "$HOME/.config/openbox" "$XDG_RUNTIME_DIR"
python3 -c 'import os,json,pathlib;pathlib.Path(os.environ["XDG_RUNTIME_DIR"],"fgc-display.json").write_text(json.dumps({k:os.environ.get(k,"") for k in ("DISPLAY","XAUTHORITY")}))'
systemctl --user import-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP || true
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber.service || true
xset s off -dpms || true
xsetroot -solid '#091320'
openbox --config-file /usr/share/fgc/openbox.xml --sm-disable &
wm=$!
trap 'kill "$wm" 2>/dev/null || true' EXIT
python3 - <<'PY'
import json,subprocess
from pathlib import Path
try:
    p=json.loads(Path.home().joinpath('.config/fgc-display.json').read_text())
    subprocess.run(['xrandr','--output',p['output'],'--mode',p['mode']],timeout=10,check=False)
except Exception:pass
PY
if grep -qw 'fgc.graphics=safe' /proc/cmdline; then export LIBGL_ALWAYS_SOFTWARE=1; fi
while true; do
    /opt/fgc/current/FGCConsole.x86_64 --fullscreen -- --kiosk --appliance || true
    sleep 2
done
