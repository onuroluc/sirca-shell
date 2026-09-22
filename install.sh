#!/usr/bin/env bash
# Sirca Shell — interactive installer.      ./install.sh            guided, asks before every step that matters
#                                           ./install.sh --dry-run  shows exactly what would run, changes nothing
#                                           ./install.sh --preset shell|look|full --yes      unattended
# It installs for the CURRENT USER. Two optional components need sudo (the KWin effect and the Qt style); you are asked
# before sudo is used, and each component tells you how to undo it. Everything is undone by ./uninstall.sh.
set -uo pipefail
# qdbus is "qdbus6" on Ubuntu / Arch and "qdbus-qt6" on Fedora (exported: the steps run through bash -c)
qdbus6() { if type -P qdbus6 >/dev/null 2>&1; then command qdbus6 "$@"; else qdbus-qt6 "$@"; fi; }
export -f qdbus6
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DRY=0; YES=0; PRESET=""
while [ $# -gt 0 ]; do case "$1" in --dry-run) DRY=1 ;; --yes|-y) YES=1 ;; --preset) PRESET="${2:-}"; shift ;; -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; *) echo "unknown option: $1"; exit 2 ;; esac; shift; done
STATE="$HOME/.local/state/sirca-shell"; mkdir -p "$STATE"; LOG="$STATE/install-$(date +%Y%m%d-%H%M%S).log"
if [ -t 1 ]; then B=$'\e[1m'; D=$'\e[2m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'; else B=""; D=""; R=""; G=""; Y=""; C=""; N=""; fi
say()  { printf '%s\n' "$*"; }
head_() { printf '\n%s%s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }
ask()  { # ask "question" default(y/n)  -> 0 for yes
    local q="$1" d="${2:-n}" a; [ $YES = 1 ] && return $([ "$d" = y ] && echo 0 || echo 1)
    read -r -p "$q [$([ "$d" = y ] && echo Y/n || echo y/N)] " a </dev/tty || a=""; a="${a:-$d}"; case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
run()  { # run "what it does" command...   (logged; in a dry run only printed)
    local what="$1"; shift
    if [ $DRY = 1 ]; then printf '  %s[dry run]%s %s\n            %s%s%s\n' "$C" "$N" "$what" "$D" "$*" "$N"; return 0; fi
    printf '  … %s\n' "$what"; { echo "### $what"; echo "\$ $*"; } >>"$LOG"
    if "$@" >>"$LOG" 2>&1; then ok "$what"; return 0; else bad "$what  (details: $LOG)"; return 1; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------------------------------------ 1. what this is
clear 2>/dev/null || true
cat <<TXT
${B}Sirca Shell${N}  —  a liquid-glass top bar and dock for KDE Plasma, with the themes that go with it.

This installer is a conversation, not a one-liner. It will
  1. look at your system and tell you what will and will not work on it,
  2. tell you plainly what each part changes and what the risks are,
  3. let you pick: only the shell, the shell with the matching look, or the author's full setup,
  4. install what you picked, and tell you how to switch it on and how to undo it.
Nothing is changed before step 4.$( [ $DRY = 1 ] && printf '\n%s(dry run: nothing will be changed at all)%s' "$C" "$N")
TXT

# ------------------------------------------------------------------------------------------------ 2. your system
head_ "1. Your system"
FATAL=0; HAVE_EFFECT_DEPS=1
if [ "${XDG_SESSION_TYPE:-}" = wayland ]; then ok "Wayland session"; else bad "this is not a Wayland session (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}). The shell is made of Wayland layer-shell windows: it cannot run on X11."; FATAL=1; fi
PV="$(plasmashell --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' | head -1)"
case "$PV" in 6.6*) ok "KDE Plasma $PV" ;; 6.7*) warn "KDE Plasma $PV: built and run against 6.7.5 in a headless test session (bar, dock, launcher, quick settings, calendar, power menu, edit mode and both KWin effects came up). Not used day to day on 6.7 yet: please report what you see." ;; 6.*) warn "KDE Plasma $PV: built and used on 6.6. Older 6.x may miss things the shell uses; the KWin effect is version-sensitive." ;;
  "") bad "KDE Plasma was not found. The shell needs KWin and Plasma's libraries (it replaces only Plasma's panels)."; FATAL=1 ;; *) bad "KDE Plasma $PV: Plasma 6 is required."; FATAL=1 ;; esac
pgrep -x kwin_wayland >/dev/null 2>&1 && ok "KWin is the compositor" || { bad "kwin_wayland is not running. Other compositors (Hyprland, Sway, GNOME) are not supported."; FATAL=1; }
for t in cmake g++ git python3; do have $t || { bad "missing: $t"; FATAL=1; }; done
[ $FATAL = 0 ] && ok "build tools: cmake, g++, python3"
PYS=/usr/bin/python3; [ -x "$PYS" ] || PYS=python3        # the tools run with the system python
GPU="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/.*: //')"
case "$GPU" in *NVIDIA*|*nvidia*) ok "GPU: ${GPU:0:60}  (what this was developed on)" ;; "") warn "GPU not detected" ;; *) warn "GPU: ${GPU:0:60}  — AMD and Intel are untested by the author. It should work; please report what you see." ;; esac
OUTS="$(kscreen-doctor -j 2>/dev/null | "${PYS:-python3}" -c 'import json,sys; print(sum(1 for o in json.load(sys.stdin).get("outputs", []) if o.get("enabled")))' 2>/dev/null || echo 1)"
[ "${OUTS:-1}" -gt 1 ] && warn "$OUTS screens: the wallpaper goes on every screen; the bar and dock start on the primary one (edit mode > Screens puts them where you want). Tested with virtual screens only: please report." || ok "one screen"
"$PYS" -c 'import PIL, numpy' 2>/dev/null && ok "python: Pillow + numpy (wallpaper tools)" || warn "python Pillow / numpy missing: the bundled wallpapers still work, only re-colouring your own wallpaper will not."
HAVE_PAPIRUS=0; { [ -d /usr/share/icons/Papirus ] || [ -d "$HOME/.local/share/icons/Papirus" ]; } && HAVE_PAPIRUS=1
[ $HAVE_PAPIRUS = 1 ] && ok "Papirus icons (the look uses them; folder colours follow the colour theme)" || warn "Papirus icon theme not installed: the look step installs it into ~/.local/share/icons (about 200 MB, from github.com/PapirusDevelopmentTeam)."
MILOU_OK=0; for d in "$(qtpaths6 --qml-dir 2>/dev/null)" "$(qmake6 -query QT_INSTALL_QML 2>/dev/null)" /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml; do [ -n "$d" ] && [ -f "$d/org/kde/milou/qmldir" ] && MILOU_OK=1; done
[ $MILOU_OK = 1 ] || { bad "the Milou QML module is missing (package: plasma-milou on Fedora, milou on Arch and Ubuntu): the shell's search uses it and the shell exits at start without it."; FATAL=1; }
have gpu-screen-recorder && ok "gpu-screen-recorder (screen recording)" || warn "gpu-screen-recorder not installed: screenshots work, recording will say it is missing."
# KWin's CMake config refuses to be found unless these are installed too, and the distros' kwin dev packages do not pull
# them in (seen on Fedora 44: epoxy and drm; Vulkan from 6.7 on everywhere)
. /etc/os-release 2>/dev/null || true
case "${ID:-}${ID_LIKE:-}" in *fedora*|*rhel*) PK_EPOXY=libepoxy-devel PK_DRM=libdrm-devel PK_VULKAN=vulkan-headers ;; *arch*) PK_EPOXY=libepoxy PK_DRM=libdrm PK_VULKAN=vulkan-headers ;; *) PK_EPOXY=libepoxy-dev PK_DRM=libdrm-dev PK_VULKAN=libvulkan-dev ;; esac
have pkg-config && { pkg-config --exists epoxy || warn "epoxy development files not installed ($PK_EPOXY): the glass KWin effect will not configure without them."; pkg-config --exists libdrm || warn "libdrm development files not installed ($PK_DRM): the glass KWin effect will not configure without them."; }
case "$PV" in 6.6*) ;; *) [ -f /usr/include/vulkan/vulkan.h ] || warn "Vulkan headers not installed ($PK_VULKAN): from 6.7 on, KWin's development files need them, the glass KWin effect will not configure without." ;; esac
[ -f /usr/include/kwin/effect/effect.h ] || [ -f /usr/include/kwin/effect/offscreeneffect.h ] || { HAVE_EFFECT_DEPS=0; warn "KWin's development headers are not installed (kwin-dev / kwin): the glass KWin effect cannot be built until they are."; }
if [ $FATAL = 1 ]; then say; bad "This system cannot run the shell (see the red lines). Nothing was changed."; [ $DRY = 1 ] || exit 1; fi
say "  ${D}Build dependencies are listed in shell/README.md (\"Build dependencies\": Ubuntu, Fedora and Arch names); a failed build names what is missing.${N}"

# ------------------------------------------------------------------------------------------------ 3. risks
head_ "2. What you should know before you say yes"
cat <<TXT
  • ${B}It replaces Plasma's panels${N} while it is switched on. Your panel layout is saved first and restored exactly by
    ${C}sirca-shell-switch off${N}. If the shell crashes five times in a minute, Plasma's panels come back by themselves.
  • ${B}It is young software by one person${N}, used daily on ONE machine (Ubuntu 26.04, Plasma 6.6, NVIDIA, one ultrawide
    screen). Expect rough edges elsewhere. There is no warranty (GPL-3.0-or-later).
  • ${B}It takes over some global shortcuts${N} while it runs (Meta, Meta+Space, Meta+V, Meta+A, Print, Meta+Shift+S/R,
    Ctrl+Alt+Del, Alt+Tab) and hands them back when it is switched off.
  • ${B}The glass look needs a KWin effect plugin${N} (optional, needs sudo). A compositor plugin runs INSIDE KWin: a bug in it
    can crash your whole session. It is built for the KWin you have; after a Plasma upgrade it must be rebuilt, and until
    then KWin simply does not load it (you get flat translucent surfaces, nothing breaks).
  • ${B}The app themes change your settings${N}: KDE colour scheme, GTK 3/4 css, icon theme. Each applier backs up what it
    touches and has a revert. The Qt style + window decoration (optional, needs sudo) REPLACES the Darkly style plugin
    if you have Darkly installed (the original is kept as darkly6.so.orig-glass).
  • Nothing is sent anywhere. No telemetry, no network access except what your desktop already does.
TXT
if ! ask "Understood — continue?" y; then say "Nothing was changed."; exit 0; fi

# ------------------------------------------------------------------------------------------------ 4. choose
head_ "3. What do you want?"
cat <<TXT
  ${B}1) Shell only${N}            the bar, dock, launcher, search, notifications, clipboard, screenshots. No root.
                            Without the effect it is translucent but flat (no blur, no lit edge).
  ${B}2) Shell + the look${N}      1 + the glass KWin effect (sudo) + KDE colour scheme and GTK look + light/dark switch
                            with colour themes and the bundled wallpapers + lock screen.
  ${B}3) The author's full setup${N}  2 + the Qt widget style and window decoration (sudo, replaces Darkly) + the author's
                            bar and dock layout. Closest to the screenshots; the most invasive.
  ${B}4) Let me pick${N}           choose each part yourself.
TXT
declare -A ON=([shell]=1 [effect]=0 [look]=0 [mode]=0 [lock]=0 [qt]=0 [setup]=0)
preset() { case "$1" in shell|1) ;; look|2) ON[effect]=1; ON[look]=1; ON[mode]=1; ON[lock]=1 ;; full|3) ON[effect]=1; ON[look]=1; ON[mode]=1; ON[lock]=1; ON[qt]=1; ON[setup]=1 ;; *) return 1 ;; esac; }
if [ -n "$PRESET" ]; then preset "$PRESET" || { echo "unknown preset: $PRESET"; exit 2; }
else
    a=""; [ $YES = 1 ] && a=1 || { read -r -p "Your choice [1-4, default 1]: " a </dev/tty || a=1; }; a="${a:-1}"
    if [ "$a" = 4 ]; then
        ask "  The glass KWin effect: blur, refraction, lit edge (sudo; runs inside KWin)?" y && ON[effect]=1
        ask "  KDE colour scheme + GTK 3/4 look (no root, revertible)?" y && ON[look]=1
        ask "  Light/dark switch, colour themes and the bundled wallpapers (no root)?" y && ON[mode]=1
        ask "  Lock screen in the same look (no root; active from the next login)?" y && ON[lock]=1
        ask "  Qt widget style + window decoration (sudo; replaces the Darkly style plugin if present)?" n && ON[qt]=1
        ask "  The author's bar and dock layout (only look and layout keys; your pinned apps stay)?" n && ON[setup]=1
    else preset "$a" || preset 1; fi
fi
[ ${ON[effect]} = 1 ] && [ $HAVE_EFFECT_DEPS = 0 ] && { warn "The KWin effect was chosen but KWin's headers are missing: it will be skipped. Install them and run this again."; ON[effect]=0; }

# ------------------------------------------------------------------------------------------------ 5. what you will get
head_ "4. With this choice"
say "  ${G}Works:${N} bar, dock, launcher, search (apps, files, sums, units), quick settings, notifications, clipboard history,"
say "         screenshots, tile picker, window switcher, power menu, edit mode, light and dark inside the shell."
[ ${ON[effect]} = 1 ] && say "  ${G}Works:${N} real glass: blur and refraction behind the bar, dock and their popups, the lit edge." \
                     || say "  ${Y}Not:${N}   blur, refraction and the lit edge (the KWin effect was not chosen): flat translucent surfaces instead."
[ ${ON[look]} = 1 ]  && say "  ${G}Works:${N} KDE and GTK apps in the matching colours." || say "  ${Y}Not:${N}   apps keep your current colours."
[ ${ON[mode]} = 1 ]  && say "  ${G}Works:${N} one switch for light / dark and 7 colour themes across shell, apps, icons (Papirus, folders in the theme colour) and wallpaper (cross-faded)." \
                     || say "  ${Y}Not:${N}   the desktop-wide light/dark switch and colour themes (the shell's own light mode still works)."
[ ${ON[qt]} = 1 ]    && say "  ${G}Works:${N} frosted Qt apps (Dolphin, System Settings) and the glass window decoration." \
                     || say "  ${Y}Not:${N}   frosted Qt apps and the glass title bars (Qt style + decoration not chosen)."
say "  ${Y}Not yet, for anyone:${N} more than one screen; X11; other compositors; a vertical dock."
say "  ${D}Optional extras that stay manual: Spotify theme + mini player, Firefox accent, Ghostty styling (see desktop/README.md).${N}"
NEED_SUDO=$(( ON[effect] + ON[qt] ))
[ $NEED_SUDO -gt 0 ] && say "  ${B}sudo will be asked for${N} by: $([ ${ON[effect]} = 1 ] && printf 'the KWin effect  ')$([ ${ON[qt]} = 1 ] && printf 'the Qt style and decoration')"
if ! ask "Install now?" y; then say "Nothing was changed."; exit 0; fi

# ------------------------------------------------------------------------------------------------ 6. install
head_ "5. Installing   ${D}(log: $LOG)${N}"
FAILED=()
step() { "$@" || FAILED+=("$1"); }
i_shell() { run "build and install the shell to ~/.local (a few minutes)" "$ROOT/shell/install.sh"; }
i_effect() {
    run "configure the KWin effect" cmake -S "$ROOT/kwin-effects" -B "$ROOT/kwin-effects/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr || return 1
    run "build the KWin effect" cmake --build "$ROOT/kwin-effects/build" -j"$(nproc)" || return 1
    say "  ${B}sudo:${N} copying the effect plugins into KWin's plugin folder"
    run "install the KWin effect (sudo)" sudo cmake --install "$ROOT/kwin-effects/build" || return 1
    [ $DRY = 1 ] || cp "$ROOT/kwin-effects/build/install_manifest.txt" "$STATE/effect-manifest.txt" 2>/dev/null
    run "switch KWin's own blur off, the glass effect on" bash -c 'kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false; kwriteconfig6 --file kwinrc --group Plugins --key glassEnabled true; kwriteconfig6 --file kwinrc --group Plugins --key glasskeyEnabled true; qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect blur >/dev/null; qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect glass >/dev/null; qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect glasskey >/dev/null; true'; }
i_look() { run "KDE colour scheme and GTK look (backups in ~/.local/state/glass-desktop)" "$ROOT/desktop/tools/apply_all.sh" apply; }
i_mode() {
    if [ "$HAVE_PAPIRUS" = 0 ]; then
        # Papirus's installer downloads with wget; some minimal systems only have curl. Either does here.
        run "Papirus icon theme into ~/.local/share/icons (no root; the official installer, about 200 MB)" bash -c 'set -e; command -v wget >/dev/null || command -v curl >/dev/null || { echo "neither wget nor curl is installed"; exit 1; }; mkdir -p "$HOME/.local/share/icons"; T=$(mktemp -d); cd "$T"; url=https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/refs/heads/master.tar.gz; if command -v wget >/dev/null; then wget -qO papirus.tar.gz "$url"; else curl -fsSL -o papirus.tar.gz "$url"; fi; tar -xzf papirus.tar.gz; for t in Papirus Papirus-Dark Papirus-Light; do rm -rf "$HOME/.local/share/icons/$t"; cp -r papirus-icon-theme-master/$t "$HOME/.local/share/icons/"; done; cd /; rm -rf "$T"; gtk-update-icon-cache -q "$HOME/.local/share/icons/Papirus" 2>/dev/null || true' || return 1
    fi
    run "bundled wallpapers to ~/.local/share/wallpapers/sirca" bash -c 'mkdir -p "$HOME/.local/share/wallpapers/sirca" && cp -n "$0"/wallpapers/*.jpg "$HOME/.local/share/wallpapers/sirca/"' "$ROOT" || return 1
    run "glass-mode and its helpers on your PATH (links into this folder: keep it)" bash -c 'mkdir -p "$HOME/.local/bin" && ln -sfn "$0/desktop/tools/mode.sh" "$HOME/.local/bin/glass-mode" && ln -sfn "$0/desktop/tools/lock_state.sh" "$HOME/.local/bin/glass-lock-sync" && ln -sfn "$0/desktop/tools/folder_color.sh" "$HOME/.local/bin/glass-folder-color"' "$ROOT" || return 1
    run "seven colour themes in the shell's config (kept if you already have themes)" python3 "$ROOT/setups/write_themes.py" "$HOME/.local/share/wallpapers/sirca" || return 1
    # The icon theme itself. glass-mode only switches BETWEEN Papirus variants (and colours the folders) when a Papirus
    # theme is already in use, so on a fresh system nothing ever selected it: the bar and dock kept drawing Breeze's icons.
    run "icon theme: Papirus-Dark (your previous choice is kept in $STATE/icon-theme.txt)" bash -c 'cur=$(kreadconfig6 --file kdeglobals --group Icons --key Theme); [ -f "$0/icon-theme.txt" ] || echo "${cur:-breeze}" > "$0/icon-theme.txt"; case "$cur" in Papirus*|Glass-Papirus*) exit 0;; esac; t=Papirus-Dark; [ "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(\"mode\",\"dark\"))" "$HOME/.config/sirca-shell/config.json" 2>/dev/null)" = light ] && t=Papirus; for h in /usr/lib/x86_64-linux-gnu/libexec/plasma-changeicons /usr/lib/libexec/plasma-changeicons /usr/libexec/plasma-changeicons /usr/lib64/libexec/plasma-changeicons; do [ -x "$h" ] && { "$h" "$t" >/dev/null 2>&1 && exit 0; }; done; kwriteconfig6 --file kdeglobals --group Icons --key Theme "$t"' "$STATE"
    # and the colour theme once, so the folder icons wear the accent from the start (glass-mode derives Glass-Papirus-<colour>)
    run "apply the colour theme once (folder icons in the theme colour)" bash -c '"$HOME/.local/bin/glass-mode" theme "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(\"theme\",\"blue\"))" "$HOME/.config/sirca-shell/config.json" 2>/dev/null || echo blue)" >/dev/null 2>&1 || true'; }
i_lock() { run "lock screen (active from the next login)" "$ROOT/desktop/tools/install_lock.sh"; }
i_qt() {
    run "configure the Qt style and decoration" cmake -S "$ROOT/desktop/qt/darkly-fork" -B "$ROOT/desktop/qt/darkly-fork/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_QT5=OFF || return 1
    run "build the Qt style and decoration (several minutes)" cmake --build "$ROOT/desktop/qt/darkly-fork/build" -j"$(nproc)" || return 1
    run "stage the built plugins" bash -c 'mkdir -p "$0/desktop/build" && cp "$0"/desktop/qt/darkly-fork/build/bin/darkly6.so "$0"/desktop/qt/darkly-fork/build/bin/org.kde.glass*.so "$0/desktop/build/"' "$ROOT" || return 1
    say "  ${B}sudo:${N} installing the style and decoration plugins (the stock Darkly plugin is kept as darkly6.so.orig-glass)"
    run "install the Qt style and decoration (sudo)" sudo "$ROOT/desktop/tools/install_qt.sh" || return 1
    run "use the glass window decoration" "$ROOT/desktop/tools/use_decoration.sh" glass; }
i_setup() { run "the author's bar and dock layout (your config is backed up first)" "$HOME/.local/bin/sirca-shell-setup" import "$ROOT/setups/author.json"; }
[ ${ON[shell]}  = 1 ] && step i_shell
[ ${ON[effect]} = 1 ] && step i_effect
[ ${ON[look]}   = 1 ] && step i_look
[ ${ON[mode]}   = 1 ] && step i_mode
[ ${ON[lock]}   = 1 ] && step i_lock
[ ${ON[qt]}     = 1 ] && step i_qt
[ ${ON[setup]}  = 1 ] && step i_setup
[ $DRY = 1 ] || printf '%s\n' "$(for k in "${!ON[@]}"; do echo "$k=${ON[$k]}"; done)" > "$STATE/installed-components"

# ------------------------------------------------------------------------------------------------ 7. what now
head_ "6. Done"
if [ ${#FAILED[@]} -gt 0 ]; then bad "These parts did not finish: ${FAILED[*]}   (log: $LOG). The rest is installed; fix the cause and run this again."; fi
cat <<TXT
  Switch it on:      ${C}sirca-shell-switch on${N}        (saves your Plasma panels and hands over)
  Switch it off:     ${C}sirca-shell-switch off${N}       (your panels come back exactly as they were)
  First start:       a welcome card names the things worth knowing. Right-click the bar or dock to edit them.
$( [ ${ON[mode]} = 1 ] && printf '  Light / dark:      %sglass-mode toggle%s,  colour themes:  %sglass-mode theme next%s   (or the buttons in quick settings)\n' "$C" "$N" "$C" "$N")
  Remove everything: ${C}$ROOT/uninstall.sh${N}
  Problems:          the log above, and ${C}journalctl --user -u sirca-shell -b${N}
TXT
[ ${ON[mode]} = 1 ] && say "  ${Y}Keep this folder${N} ($ROOT): glass-mode and the theme generators run from it."
exit 0
