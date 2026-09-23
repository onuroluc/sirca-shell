#!/usr/bin/env bash
# update.sh — pull the newest version and re-run the installer with the parts you chose last time (no questions asked).
# The shell's "Update now" button runs this in a terminal; you can run it yourself any time.
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; STATE="$HOME/.local/state/sirca-shell"
cd "$ROOT" || exit 1
echo "== Sirca Shell update in $ROOT"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "this folder is not a git clone; download the new version by hand"; read -r -p "Enter to close" _; exit 1; fi
before="$(git rev-parse --short HEAD)"
if ! git pull --ff-only; then echo; echo "git pull failed (local changes? no network?). Nothing was changed."; read -r -p "Enter to close" _; exit 1; fi
after="$(git rev-parse --short HEAD)"
if [ "$before" = "$after" ]; then echo "already at $after, nothing to do"; read -r -p "Enter to close" _; exit 0; fi
echo "== $before -> $after"; git --no-pager log --oneline "$before..$after" | head -30; echo
parts="$(cat "$STATE/parts.txt" 2>/dev/null || echo shell)"
# "setup" is the author's bar and dock layout: a first-install choice, never re-imported over your own layout on an update
parts="$(printf '%s\n' $parts | grep -vx setup | tr '\n' ' ')"
echo "== re-installing: $parts"
./install.sh --parts "$parts" --yes; rc=$?
echo
if [ $rc = 0 ]; then
    # the running shell is the old binary: restart it (a symlinked unit was removed by "disable" in 0.6.x; put a copy back if so)
    for u in sirca-shell.service sirca-shell-fallback.service; do [ -e "$HOME/.config/systemd/user/$u" ] || { [ -f "$HOME/.local/lib/systemd/user/$u" ] && install -m 644 "$HOME/.local/lib/systemd/user/$u" "$HOME/.config/systemd/user/$u"; }; done
    systemctl --user daemon-reload 2>/dev/null
    if systemctl --user is-enabled -q sirca-shell.service 2>/dev/null; then systemctl --user restart sirca-shell.service && sleep 4; fi
    if systemctl --user is-active -q sirca-shell.service; then echo "== done: the shell restarted ($(~/.local/bin/sirca-shell --version 2>/dev/null || echo new build) is running)"
    else echo "== done. The shell is not running; switch it on with: sirca-shell-switch on"; fi
    case " $parts " in *" effect "*|*" qt "*) echo "== the KWin effect / window decoration were rebuilt: they take effect after you log out and back in";; esac
else echo "== the installer reported problems (see above)"; fi
read -r -p "Enter to close" _
