#!/bin/bash
# apply_kde.sh apply|revert — installs the generated colour scheme + Darkly settings for the current user (no root).
# apply keeps a dated backup of every file it touches in ~/.local/state/glass-desktop/kde-backup/ (first apply only).
set -euo pipefail
# qdbus is "qdbus6" on Ubuntu / Arch and "qdbus-qt6" on Fedora
qdbus6() { if type -P qdbus6 >/dev/null 2>&1; then command qdbus6 "$@"; else qdbus-qt6 "$@"; fi; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; B="$HOME/.local/state/glass-desktop/kde-backup"; SCHEMES="$HOME/.local/share/color-schemes"
case "${1:-}" in
  apply)
    python3 "$ROOT/tools/gen_kde.py"
    if [ ! -d "$B" ]; then mkdir -p "$B"; cp "$HOME/.config/darklyrc" "$B/darklyrc" 2>/dev/null || true; kreadconfig6 --file kdeglobals --group General --key ColorScheme > "$B/colorscheme.txt"; kreadconfig6 --file kdeglobals --group General --key accentColorFromWallpaper > "$B/accent-from-wallpaper.txt"; kreadconfig6 --file kdeglobals --group General --key AccentColor > "$B/accent.txt"; fi
    mkdir -p "$SCHEMES"; cp "$ROOT/build/kde/Glass.colors" "$SCHEMES/Glass.colors"
    python3 - "$ROOT/build/kde/darkly.json" <<'PY'
import json, subprocess, sys
for group, kv in json.load(open(sys.argv[1])).items():
    for k, v in kv.items(): subprocess.run(["kwriteconfig6", "--file", "darklyrc", "--group", group, "--key", k, str(v)], check=True)
PY
    # a custom accent colour overrides the scheme's selection colours (blue highlights everywhere): the look is monochrome
    kwriteconfig6 --file kdeglobals --group General --key AccentColor --delete
    kwriteconfig6 --file kdeglobals --group General --key accentColorFromWallpaper false
    plasma-apply-colorscheme BreezeDark >/dev/null; plasma-apply-colorscheme Glass >/dev/null   # toggle so the change is picked up even if Glass was already set
    qdbus6 org.kde.KWin /KWin reconfigure >/dev/null
    echo "applied. Restart Qt apps to see the widget-style part. Revert: $0 revert" ;;
  revert)
    [ -d "$B" ] || { echo "no backup in $B"; exit 1; }
    if [ -f "$B/darklyrc" ]; then cp "$B/darklyrc" "$HOME/.config/darklyrc"; else rm -f "$HOME/.config/darklyrc"; fi   # (issue #6: none before = none after)
    a="$(cat "$B/accent.txt" 2>/dev/null || true)"; [ -n "$a" ] && kwriteconfig6 --file kdeglobals --group General --key AccentColor "$a"
    plasma-apply-colorscheme Glass >/dev/null 2>&1 || true; prev="$(cat "$B/colorscheme.txt" 2>/dev/null)"; [ -n "$prev" ] || prev=BreezeLight; plasma-apply-colorscheme "$prev" >/dev/null 2>&1 || true; afw="$(cat "$B/accent-from-wallpaper.txt" 2>/dev/null)"; if [ -n "$afw" ]; then kwriteconfig6 --file kdeglobals --group General --key accentColorFromWallpaper "$afw"; else kwriteconfig6 --file kdeglobals --group General --key accentColorFromWallpaper --delete; fi
    qdbus6 org.kde.KWin /KWin reconfigure >/dev/null
    rm -f "$SCHEMES/Glass.colors" "$SCHEMES/GlassLight.colors"
    rm -rf "$B"; echo "reverted to $(kreadconfig6 --file kdeglobals --group General --key ColorScheme)" ;;
  *) echo "usage: $0 apply|revert"; exit 2 ;;
esac
