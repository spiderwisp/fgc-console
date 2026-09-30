#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
dropin=/etc/lightdm/lightdm.conf.d/60-fgc-console.conf
if [[ -f "$dropin" ]] && head -1 "$dropin" | grep -qx '# FGC Console mode'; then
    rm -- "$dropin"
    echo 'FGC automatic login disabled for the next boot. Select your desktop session at login.'
else
    echo 'No FGC automatic-login configuration found.'
fi
