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
echo "== re-installing: $parts"
./install.sh --parts "$parts" --yes; rc=$?
echo; [ $rc = 0 ] && echo "== done. If the shell did not restart by itself: sirca-shell-switch off; sirca-shell-switch on" || echo "== the installer reported problems (see above)"
read -r -p "Enter to close" _
