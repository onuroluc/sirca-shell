#!/usr/bin/env bash
# Sirca Shell — remove what ./install.sh installed. Asks before each part; your own config and wallpapers are kept unless
# you say otherwise.      ./uninstall.sh [--dry-run] [--yes]
set -uo pipefail
# qdbus is "qdbus6" on Ubuntu / Arch and "qdbus-qt6" on Fedora (exported: the steps run through bash -c)
qdbus6() { if type -P qdbus6 >/dev/null 2>&1; then command qdbus6 "$@"; else qdbus-qt6 "$@"; fi; }
export -f qdbus6
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; STATE="$HOME/.local/state/sirca-shell"; DRY=0; YES=0
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; --yes|-y) YES=1 ;; esac; done      # --yes: remove everything without asking
ask() { local a; [ $YES = 1 ] && return 0; read -r -p "$1 [y/N] " a </dev/tty || a=""; case "$a" in y|Y|yes) return 0 ;; *) return 1 ;; esac; }
run() { local what="$1"; shift; if [ $DRY = 1 ]; then echo "  [dry run] $what:  $*"; else echo "  … $what"; "$@" || echo "    (that step reported a problem; continuing)"; fi; }
echo "This gives Plasma's panels back first, then removes the parts you confirm."
SW="$HOME/.local/bin/sirca-shell-switch"; command -v sirca-shell-switch >/dev/null && SW="$(command -v sirca-shell-switch)"
if [ -x "$SW" ]; then run "switch the shell off (Plasma's panels come back)" "$SW" off
elif systemctl --user is-enabled sirca-shell.service >/dev/null 2>&1; then echo "sirca-shell-switch is missing but the shell is still enabled: refusing to remove it while Plasma's panels are handed over. Reinstall the shell, switch it off, then uninstall."; exit 1; fi
if [ -f "$STATE/effect-manifest.txt" ] && ask "Remove the glass KWin effect (sudo) and switch KWin's own blur back on?"; then
    run "unload the effect" bash -c 'for e in glasskey glass; do qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect $e >/dev/null; kwriteconfig6 --file kwinrc --group Plugins --key ${e}Enabled false; done; b=$(cat "$0/blur-was.txt" 2>/dev/null || echo true); kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled "$b"; [ "$b" = true ] && qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect blur >/dev/null; true' "$STATE"
    run "delete the installed plugin files (sudo)" sudo xargs -a "$STATE/effect-manifest.txt" rm -f
fi
QTP="$(qtpaths6 --plugin-dir 2>/dev/null || qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null)"
[ -x "$ROOT/desktop/tools/install_qt.sh" ] && { [ -f "$STATE/widget-style.txt" ] || ls "$QTP"/org.kde.kdecoration3/org.kde.glass*.so >/dev/null 2>&1; } && ask "Remove the glass Qt style and decoration (sudo; the stock Darkly comes back if there was one)?" && {
    [ -f "$STATE/widget-style.txt" ] && run "widget style back to $(cat "$STATE/widget-style.txt")" bash -c 'kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle "$(cat "$0/widget-style.txt")"; rm -f "$HOME/.local/share/kstyle/themes/darkly.themerc"; qdbus6 org.kde.KGlobalSettings /KGlobalSettings org.kde.KGlobalSettings.notifyChange 2 0 >/dev/null 2>&1 || true' "$STATE"
    run "back to the Darkly decoration" "$ROOT/desktop/tools/use_decoration.sh" darkly; run "restore the plugins (sudo)" sudo "$ROOT/desktop/tools/install_qt.sh" --undo; }
ask "Revert the KDE colour scheme and GTK look to what you had before?" && run "revert the look" "$ROOT/desktop/tools/apply_all.sh" revert
ask "Remove the lock screen (Plasma's own from the next login)?" && run "remove the lock screen" "$ROOT/desktop/tools/install_lock.sh" --undo
[ -f "$STATE/icon-theme.txt" ] && ask "Icon theme back to what you had ($(cat "$STATE/icon-theme.txt"))?" && run "restore the icon theme" bash -c 't=$(cat "$0/icon-theme.txt"); for h in /usr/lib/x86_64-linux-gnu/libexec/plasma-changeicons /usr/lib/libexec/plasma-changeicons /usr/libexec/plasma-changeicons /usr/lib64/libexec/plasma-changeicons; do [ -x "$h" ] && { "$h" "$t" >/dev/null 2>&1 && exit 0; }; done; kwriteconfig6 --file kdeglobals --group Icons --key Theme "$t"' "$STATE"
[ -f "$STATE/papirus-added.txt" ] && ask "Remove the Papirus icon themes the installer downloaded ($(tr '\n' ' ' < "$STATE/papirus-added.txt")) and the generated folder-colour themes?" && run "remove icon themes" bash -c 'while read -r t; do [ -n "$t" ] && rm -rf "$HOME/.local/share/icons/$t"; done < "$0/papirus-added.txt"; rm -rf "$HOME"/.local/share/icons/Glass-Papirus*' "$STATE"
ask "Remove glass-mode and its helper links from ~/.local/bin?" && run "remove the links" rm -f "$HOME/.local/bin/glass-mode" "$HOME/.local/bin/glass-lock-sync" "$HOME/.local/bin/glass-folder-color"
run "remove the shell itself" "$ROOT/shell/uninstall.sh"
ask "Also delete your shell config (~/.config/sirca-shell) and the bundled wallpapers?" && run "delete config and wallpapers" rm -rf "$HOME/.config/sirca-shell" "$HOME/.local/share/wallpapers/sirca"
echo "Done. Log out and in once so every app forgets the old look."
