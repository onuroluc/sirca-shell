#!/bin/bash
# Run once per login (glass-desktop-ensure.service). Re-asserts every piece of the look, repairing only what drifted
# (a KDE update resetting the GTK css, another theme applied by accident, …). Only acts while Sirca Shell is switched on.
# qdbus is "qdbus6" on Ubuntu / Arch and "qdbus-qt6" on Fedora
qdbus6() { if type -P qdbus6 >/dev/null 2>&1; then command qdbus6 "$@"; else qdbus-qt6 "$@"; fi; }
systemctl --user is-enabled -q sirca-shell.service 2>/dev/null || exit 0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; fixed=()
[ "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)" = Glass ] || { plasma-apply-colorscheme Glass >/dev/null 2>&1 && fixed+=("colour scheme"); }
for v in 3.0 4.0; do head -1 "$HOME/.config/gtk-$v/gtk.css" 2>/dev/null | grep -q "glass-desktop" || { "$ROOT/tools/apply_gtk.sh" apply >/dev/null 2>&1; fixed+=("GTK $v css"); break; }; done
[ "$(qdbus6 org.kde.GtkConfig /GtkConfig org.kde.GtkConfig.gtkTheme 2>/dev/null)" = adw-gtk3-dark ] || { qdbus6 org.kde.GtkConfig /GtkConfig org.kde.GtkConfig.setGtkTheme adw-gtk3-dark >/dev/null 2>&1; fixed+=("GTK theme"); }
P="$(qtpaths6 --plugin-dir 2>/dev/null || qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null)"; [ -d "$P" ] || P=/usr/lib/x86_64-linux-gnu/qt6/plugins
deco="$(ls "$P/org.kde.kdecoration3/" 2>/dev/null | grep -o 'org\.kde\.glass[0-9]*' | sort -V | tail -1)"
[ -n "$deco" ] && [ "$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key library)" != "$deco" ] && { kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "$deco"; qdbus6 org.kde.KWin /KWin reconfigure >/dev/null; fixed+=("window decoration"); }
[ ${#fixed[@]} -gt 0 ] && notify-send -a "Glass Desktop" -i preferences-desktop-theme "Look repaired at login" "Re-applied: ${fixed[*]}"
exit 0
