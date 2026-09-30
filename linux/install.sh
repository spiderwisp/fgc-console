#!/usr/bin/env bash
set -euo pipefail
package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$HOME/.local/share/fgc-console"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
[[ -f "$package_dir/FGCConsole.x86_64" ]] || { echo 'Run this from the extracted Linux release.' >&2; exit 1; }
mkdir -p "$app_dir" "$HOME/.local/share/applications" "$config_dir/autostart"
install -m 755 "$package_dir/FGCConsole.x86_64" "$app_dir/FGCConsole.x86_64"
install -m 755 "$package_dir/linux/run-session.sh" "$app_dir/fgc-session"
install -m 644 "$package_dir/fgc.svg" "$app_dir/fgc.svg"
desktop_path="${app_dir//\\/\\\\}"
desktop_path="${desktop_path//\"/\\\"}"
desktop_path="${desktop_path//%/%%}"
cat > "$HOME/.local/share/applications/fgc-console.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=FGC Console
Comment=Framework Gaming Console
Exec="$desktop_path/FGCConsole.x86_64" --fullscreen
Icon=$app_dir/fgc.svg
Terminal=false
Categories=Game;
StartupNotify=false
EOF
cp "$HOME/.local/share/applications/fgc-console.desktop" "$config_dir/autostart/fgc-console.desktop"
echo 'FGC Console is installed and will open at your next desktop login.'
echo 'For direct power-on boot, enable the supplied LightDM console session.'
