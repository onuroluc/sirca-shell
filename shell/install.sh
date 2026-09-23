#!/usr/bin/env bash
# Build Sirca Shell and install it for the current user (~/.local), no root needed.   ./install.sh [--prefix DIR]
# Afterwards:  sirca-shell-switch on    (hands Plasma's panels over; "sirca-shell-switch off" gives them back)
set -euo pipefail
PREFIX="$HOME/.local"; [ "${1:-}" = "--prefix" ] && PREFIX="$2"
cd "$(dirname "$0")"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF
cmake --build build -j"$(nproc)"
cmake --install build
# a user-prefix install puts the units where systemd --user looks for them: as COPIES. A symlink there is a "linked"
# unit to systemd, and `systemctl disable` (sirca-shell-switch off) deletes a linked unit outright; the next `on` then
# found no unit at all (Fedora VM, 2026-09-23).
if [ "$PREFIX" = "$HOME/.local" ]; then mkdir -p "$HOME/.config/systemd/user"; for u in sirca-shell.service sirca-shell-fallback.service; do
    [ -f "$PREFIX/lib/systemd/user/$u" ] && { rm -f "$HOME/.config/systemd/user/$u"; install -m 644 "$PREFIX/lib/systemd/user/$u" "$HOME/.config/systemd/user/$u"; }; done; fi
systemctl --user daemon-reload || true
kbuildsycoca6 >/dev/null 2>&1 || true        # KWin finds the desktop file (and with it the shell's permissions) through this cache
case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) echo "note: $PREFIX/bin is not on your PATH";; esac
echo "Installed to $PREFIX. Switch it on with:  sirca-shell-switch on"
