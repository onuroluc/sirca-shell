#!/bin/bash
# apply_gtk.sh apply|revert — GTK 3, GTK 4/libadwaita and Flatpak apps get the generated Glass look (user level, no root).
set -euo pipefail
# qdbus is "qdbus6" on Ubuntu / Arch and "qdbus-qt6" on Fedora
qdbus6() { if type -P qdbus6 >/dev/null 2>&1; then command qdbus6 "$@"; else qdbus-qt6 "$@"; fi; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; B="$HOME/.local/state/glass-desktop/gtk-backup"; C="$HOME/.config"
FILES=(gtk-3.0/gtk.css gtk-3.0/settings.ini gtk-4.0/gtk.css gtk-4.0/gtk-dark.css gtk-4.0/settings.ini)
case "${1:-}" in
  apply)
    python3 "$ROOT/tools/gen_gtk.py"
    if [ ! -d "$B" ]; then
      mkdir -p "$B/gtk-3.0" "$B/gtk-4.0"
      for f in "${FILES[@]}"; do [ -e "$C/$f" ] && cp -a "$C/$f" "$B/$f"; done
      gsettings get org.gnome.desktop.interface gtk-theme > "$B/gtk-theme.txt" 2>/dev/null || true
      [ -f "$HOME/.local/share/flatpak/overrides/global" ] && cp "$HOME/.local/share/flatpak/overrides/global" "$B/flatpak-global" || true
    fi
    # GTK 3 base theme: adw-gtk3 (libadwaita's look for GTK 3, same named colours) — bundled copy, user themes dir
    mkdir -p "$HOME/.themes"; for t in adw-gtk3 adw-gtk3-dark; do [ -d "$HOME/.themes/$t" ] || { cp -r "$ROOT/third_party/adw-gtk3/$t" "$HOME/.themes/$t"; touch "$B/added-theme-$t"; }; done
    mkdir -p "$C/gtk-3.0" "$C/gtk-4.0"
    cp "$ROOT/build/gtk/gtk-3.0.css" "$C/gtk-3.0/gtk.css"
    cp "$ROOT/build/gtk/gtk-4.0.css" "$C/gtk-4.0/gtk.css"; cp "$ROOT/build/gtk/gtk-4.0.css" "$C/gtk-4.0/gtk-dark.css"
    for i in 1 2 3; do qdbus6 org.kde.GtkConfig /GtkConfig org.kde.GtkConfig.setGtkTheme adw-gtk3-dark >/dev/null 2>&1 && break; sleep 1; done   # KDE's GTK sync owns settings.ini
    gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    # KDE's sync may have rewritten gtk.css (it prepends its colours import): put ours back on top of whatever it wrote
    cp "$ROOT/build/gtk/gtk-3.0.css" "$C/gtk-3.0/gtk.css"; cp "$ROOT/build/gtk/gtk-4.0.css" "$C/gtk-4.0/gtk.css"
    # Flatpak apps cannot see the user's themes or GTK config unless told to
    if command -v flatpak >/dev/null; then
      flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --filesystem="$HOME/.themes":ro --filesystem=xdg-data/icons:ro --env=GTK_THEME=adw-gtk3-dark
    fi
    echo "applied. Restart GTK apps. Revert: $0 revert" ;;
  revert)
    [ -d "$B" ] || { echo "no backup in $B"; exit 1; }
    for f in "${FILES[@]}"; do if [ -e "$B/$f" ]; then cp -a "$B/$f" "$C/$f"; else rm -f "$C/$f"; fi; done
    old="$(tr -d "'" < "$B/gtk-theme.txt" 2>/dev/null || true)"
    [ -n "$old" ] && { qdbus6 org.kde.GtkConfig /GtkConfig org.kde.GtkConfig.setGtkTheme "$old" >/dev/null 2>&1 || true; gsettings set org.gnome.desktop.interface gtk-theme "$old" 2>/dev/null || true; }
    if command -v flatpak >/dev/null; then
      if [ -f "$B/flatpak-global" ]; then cp "$B/flatpak-global" "$HOME/.local/share/flatpak/overrides/global"; else rm -f "$HOME/.local/share/flatpak/overrides/global"; fi
    fi
    for m in "$B"/added-theme-*; do [ -e "$m" ] && rm -rf "$HOME/.themes/${m##*/added-theme-}"; done; rmdir "$HOME/.themes" 2>/dev/null || true   # (issue #6, leissa: only the themes WE added)
    rm -rf "$B"; echo "reverted (GTK theme: ${old:-unchanged})" ;;
  *) echo "usage: $0 apply|revert"; exit 2 ;;
esac
