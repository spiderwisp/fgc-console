#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 && $# -eq 1 ]] || { echo 'Usage: sudo ./linux/enable-console-mode.sh USERNAME' >&2; exit 1; }
console_user="$1"
[[ "$console_user" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid username.' >&2; exit 1; }
console_uid="$(id -u "$console_user")"
[[ "$console_uid" -ge 1000 ]] || { echo 'Use a regular desktop account.' >&2; exit 1; }
console_home="$(getent passwd "$console_user" | cut -d: -f6)"
[[ -x "$console_home/.local/share/fgc-console/fgc-session" ]] || { echo 'Run install.sh as the console user first.' >&2; exit 1; }
command -v openbox >/dev/null || { echo 'Install openbox first.' >&2; exit 1; }
[[ "$(readlink -f /etc/systemd/system/display-manager.service)" == *lightdm* ]] || { echo 'This console session requires LightDM as the active display manager.' >&2; exit 1; }
dropin=/etc/lightdm/lightdm.conf.d/60-fgc-console.conf
if [[ -f "$dropin" ]] && ! head -1 "$dropin" | grep -qx '# FGC Console mode'; then
    echo 'Existing configuration was not created by FGC; leaving it unchanged.' >&2; exit 1
fi
mkdir -p /etc/lightdm/lightdm.conf.d /usr/share/xsessions /usr/local/bin
cat > /usr/local/bin/fgc-session <<'EOF'
#!/bin/sh
exec "$HOME/.local/share/fgc-console/fgc-session"
EOF
chmod 755 /usr/local/bin/fgc-session
cat > /usr/share/xsessions/fgc.desktop <<'EOF'
[Desktop Entry]
Name=FGC Console
Comment=Framework Gaming Console
Exec=/usr/local/bin/fgc-session
Type=Application
DesktopNames=FGC
EOF
cat > "$dropin" <<EOF
# FGC Console mode
[Seat:*]
autologin-user=$console_user
autologin-user-timeout=0
autologin-session=fgc
user-session=fgc
EOF
echo 'Console mode enabled. At the next boot, LightDM will log in automatically and open FGC Home.'
echo 'The current session has not been restarted.'
