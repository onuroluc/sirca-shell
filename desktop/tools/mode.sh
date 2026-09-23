#!/usr/bin/env bash
# glass-mode light|dark|toggle|status | theme NAME|next|list|wallpaper [FILE] — switch the whole desktop between the light
#   and the dark look: Sirca Shell (config key "mode"), KDE colour scheme (Glass / GlassLight: Qt apps, window decorations),
#   GTK 3 / 4 + libadwaita + the portal's colour-scheme (Firefox, Electron, Ghostty follow that), icon theme, and the wallpaper.
# Wallpapers per mode live in the shell's config: "wallpaperDark" / "wallpaperLight" (set with:  glass-mode wallpaper light FILE).
# `theme wallpaper [FILE]` derives the accent from the wallpaper (FILE, else the one showing now; tools/palette.py, the
#   same maths as the shell's Palette) and applies it like any other theme, as the theme named "wallpaper".
set -euo pipefail
# qdbus is "qdbus6" on Ubuntu / Arch and "qdbus-qt6" on Fedora
qdbus6() { if type -P qdbus6 >/dev/null 2>&1; then command qdbus6 "$@"; else qdbus-qt6 "$@"; fi; }
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; CFG="$HOME/.config/sirca-shell/config.json"; C="$HOME/.config"
PY=/usr/bin/python3
cfg_get() { $PY - "$CFG" "$1" <<'P'
import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2],""))
except Exception: print("")
P
}
cfg_set() { $PY - "$CFG" "$@" <<'P'
import json,os,sys
p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True)
try: o=json.load(open(p))
except Exception: o={}
for k,v in zip(sys.argv[2::2],sys.argv[3::2]):
    if v=="": o.pop(k,None)
    else: o[k]=v
json.dump(o,open(p,"w"),indent=4)
P
}
now="$(cfg_get mode)"; [ -n "$now" ] || now=dark
# ---- ONE smooth transition for the whole screen -------------------------------------------------------------------------
# Every toolkit repaints in its own time (the shell at once, Qt apps a moment later, decorations, GTK, icons, the wallpaper,
# each panel of an app on its own): a switch looked like a cascade with a hitch in the middle. KWin's "blend changes" effect
# does what macOS does: it keeps showing a snapshot of every window as it WAS, lets everything change underneath unseen, and
# after `delay` ms cross-fades each window from its snapshot to its new look, all together. (Full-screen windows are left
# alone by the effect; a second start while one is running is ignored, so the re-exec after a theme switch is harmless.)
# Off: "modeBlend": false in the shell config. How long the old look is held: "modeBlendDelay" (ms, default 1100).
blend_start() {
    [ "$(cfg_get modeBlend)" = "False" ] && return 0
    local d; d="$(cfg_get modeBlendDelay)"; case "$d" in ''|*[!0-9]*) d=1100 ;; esac
    qdbus6 org.kde.KWin /org/kde/KWin/BlendChanges org.kde.KWin.BlendChanges.start "$d" >/dev/null 2>&1 || true
}
case "${1:-status}" in light|dark|toggle|theme) [ "${2:-}" = list ] || blend_start ;; esac
case "${1:-status}" in
  status) echo "$now"; exit 0 ;;
  toggle) want=$([ "$now" = light ] && echo dark || echo light) ;;
  light|dark) want="$1" ;;
  theme)   # glass-mode theme NAME|next|list : a colour theme from the shell config ("themes": {name: {accent, light, dark}})
     if [ "${2:-}" = wallpaper ]; then
        # the theme "wallpaper" is (re)written first: accent from the picture, the current mode's wallpaper slot = the picture,
        # the other mode keeps what it has (or gets the same picture); then it is applied below like a hand-made theme
        img="${3:-}"; [ -n "$img" ] || img="$(cfg_get wallpaper)"
        [ -n "$img" ] || img="$(grep -m1 -oP '^Image=\K.*' "$C/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null | sed 's|^file://||' || true)"
        [ -f "$img" ] || { echo "glass-mode theme wallpaper: no picture to read (give a FILE)"; exit 2; }
        img="$(readlink -f "$img")"
        acc="$($PY "$ROOT/tools/palette.py" "$img")" || { echo "glass-mode: tools/palette.py failed (needs python3-pil and python3-numpy)"; exit 1; }
        dark="$(cfg_get wallpaperDark)"; light="$(cfg_get wallpaperLight)"
        if [ "$now" = light ]; then light="$img"; else dark="$img"; fi
        [ -n "$dark" ] || dark="$img"; [ -n "$light" ] || light="$img"
        $PY - "$CFG" "$acc" "$dark" "$light" <<'P'
import json,os,sys
p,acc,dark,light=sys.argv[1:5]; os.makedirs(os.path.dirname(p),exist_ok=True)
try: o=json.load(open(p))
except Exception: o={}
o.setdefault("themes",{})["wallpaper"]={"accent":acc,"dark":dark,"light":light}
json.dump(o,open(p,"w"),indent=4)
P
        echo "wallpaper accent: $acc ($img)"
     fi
     rc=0; $PY - "$CFG" "${2:-list}" <<'P' || rc=$?
import json,sys
p,arg=sys.argv[1],sys.argv[2]
try: o=json.load(open(p))
except Exception: o={}
th=o.get("themes",{}); names=list(th)
if arg=="list" or not names: print("\n".join(("* " if n==o.get("theme") else "  ")+n for n in names) or "no themes in the config"); sys.exit(3)
names=sorted(names,key=lambda n:(lambda h:h-1 if h>0.93 else h)(__import__("colorsys").rgb_to_hls(*[int(th[n].get("accent","#888888").lstrip("#")[i:i+2],16)/255 for i in (0,2,4)])[0]))
if arg=="next": arg=names[(names.index(o.get("theme"))+1)%len(names)] if o.get("theme") in names else names[0]
if arg not in th: print("unknown theme:",arg); sys.exit(2)
t=th[arg]; o["theme"]=arg
if t.get("accent"): o["accent"]=t["accent"]
if t.get("light"): o["wallpaperLight"]=t["light"]
if t.get("dark"): o["wallpaperDark"]=t["dark"]
json.dump(o,open(p,"w"),indent=4); print("theme:",arg)
# the terminal follows the colour theme: its accent entries (blue slot of the palette, its bright twin, the cursor) in both
# Glass theme files. A running Ghostty re-reads them on the reload signal sent at the end of the switch; no window closes.
import os,re,colorsys
acc=t.get("accent")
if acc:
    r,g,b=[int(acc.lstrip("#")[i:i+2],16)/255 for i in (0,2,4)]; h,l,sat=colorsys.rgb_to_hls(r,g,b)
    hexof=lambda L,S: "#%02x%02x%02x" % tuple(round(v*255) for v in colorsys.hls_to_rgb(h,max(0,min(1,L)),max(0,min(1,S))))
    sets={"glass-dark":{"4":acc,"12":hexof(l+0.13,sat),"cursor":acc},"glass-light":{"4":hexof(l-0.08,sat),"12":hexof(l+0.04,sat),"cursor":hexof(l-0.08,sat)}}
    # one line "R;G;B" that anything may read: the bash prompt reads it at every prompt, the fastfetch galaxy at render time
    rgb=";".join(str(round(v*255)) for v in (r,g,b)); d=os.path.expanduser("~/.config/sirca-shell"); os.makedirs(d,exist_ok=True); open(d+"/accent-rgb","w").write(rgb+"\n")
    # fastfetch: key / title colour in its config, and the galaxy logo re-rendered in the new gradient (its cache cleared)
    ff=os.path.expanduser("~/.config/fastfetch/config.jsonc") if os.environ.get("GLASS_NO_EXTRAS","0")!="1" else "/nonexistent"
    if os.path.isfile(ff):
        c=open(ff).read(); c2=re.sub(r'("(?:keys|title)":\s*"1;38;2;)\d+;\d+;\d+(")', lambda m: m.group(1)+rgb+m.group(2), c)
        if c2!=c: open(ff,"w").write(c2)
    # ten palette slots (176..185) for art that must re-colour while it is already on screen (the fastfetch galaxy): a radial
    # gradient core -> rim derived from the accent: pale core, the accent, the hue drifting on while it sinks into dark glass
    def grad(tt):
        stops=[(0.00,(h,0.87,min(1,sat+0.15))),(0.18,(h,l,sat)),(0.42,(h+0.03,l*0.85,sat*0.75)),(0.70,(h+0.10,l*0.66,sat*0.58)),(1.00,(h+0.125,0.30,0.20))]
        for (t0,a),(t1,b_) in zip(stops,stops[1:]):
            if tt<=t1:
                f_=(tt-t0)/(t1-t0); hh,ll,ss=[a[i]+(b_[i]-a[i])*f_ for i in range(3)]
                return "#%02x%02x%02x" % tuple(round(v*255) for v in colorsys.hls_to_rgb(hh%1.0,max(0,min(1,ll)),max(0,min(1,ss))))
        return "#333"
    slots={176+i: grad((i+0.5)/10) for i in range(10)}
    for name,v in sets.items():
        f=os.path.expanduser("~/.config/ghostty/themes/"+name) if os.environ.get("GLASS_NO_EXTRAS","0")!="1" else "/nonexistent"
        if not os.path.isfile(f): continue
        s=open(f).read()
        s=re.sub(r"(?m)^palette = 1[78]\d=.*\n","",s)                       # our ten slots, rewritten below
        s=s.rstrip("\n")+"\n"+"".join("palette = %d=%s\n" % kv for kv in sorted(slots.items()))
        s=re.sub(r"(?m)^palette = 4=.*$","palette = 4="+v["4"],s); s=re.sub(r"(?m)^palette = 12=.*$","palette = 12="+v["12"],s); s=re.sub(r"(?m)^cursor-color = .*$","cursor-color = "+v["cursor"],s)
        open(f,"w").write(s)
P
     [ $rc -eq 0 ] || exit $(( rc == 3 ? 0 : rc )); exec "$0" "$now" ;;      # re-apply the current mode with the new wallpapers
  wallpaper) [ -f "${3:-}" ] || { echo "usage: glass-mode wallpaper light|dark FILE"; exit 2; }
     cfg_set "wallpaper$([ "$2" = light ] && echo Light || echo Dark)" "$(readlink -f "$3")"; [ "$2" = "$now" ] && exec "$0" "$now"; exit 0 ;;
  *) echo "usage: glass-mode light|dark|toggle|status | theme NAME|next|list|wallpaper [FILE] | wallpaper light|dark FILE"; exit 2 ;;
esac
# remember the wallpaper of the mode we are leaving (first switch: whatever is showing now becomes that mode's picture)
cur="$(cfg_get wallpaper)"; [ -n "$cur" ] || cur="$(grep -m1 -oP '^Image=\K.*' "$C/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null | sed 's|^file://||' || true)"
key_now="wallpaper$([ "$now" = light ] && echo Light || echo Dark)"; [ -n "$(cfg_get "$key_now")" ] || { [ -n "$cur" ] && [ "$now" != "$want" ] && cfg_set "$key_now" "$cur"; }
key_want="wallpaper$([ "$want" = light ] && echo Light || echo Dark)"; wall="$(cfg_get "$key_want")"

# ---- order matters for how it FEELS: what you look at changes first, the slow desktop-wide steps run side by side after it
# 1. the shell (its config is watched: it starts cross-fading at once) and the wallpaper
if [ -n "$wall" ] && [ -f "$wall" ]; then cfg_set mode "$want" wallpaper "$wall"; plasma-apply-wallpaperimage "$wall" >/dev/null 2>&1 & else cfg_set mode "$want"; fi
SCHEME=$([ "$want" = light ] && echo GlassLight || echo Glass); SUF=$([ "$want" = light ] && echo "-light" || echo "")
THEME=$([ "$want" = light ] && echo adw-gtk3 || echo adw-gtk3-dark)
"$(dirname "$(readlink -f "$0")")/lock_state.sh" >/dev/null 2>&1 || true        # the lock screen wears the same look
[ "${GLASS_NO_EXTRAS:-0}" = 1 ] || ( /usr/bin/python3 "$(dirname "$(readlink -f "$0")")/gen_spotify.py" --apply >/dev/null 2>&1 || true ) &        # Spotify (Spicetify): accent at its next start, light / dark live
# the generated files only change when the tokens do: build them when missing or older than tokens.json, not on every switch
T="$ROOT/design/tokens.json"
{ [ "$ROOT/build/kde/$SCHEME.colors" -nt "$T" ] && [ "$ROOT/build/kde/$SCHEME.colors" -nt "$ROOT/tools/gen_kde.py" ]; } || $PY "$ROOT/tools/gen_kde.py" "$want" >/dev/null
{ [ "$ROOT/build/gtk/gtk-4.0$SUF.css" -nt "$T" ] && [ "$ROOT/build/gtk/gtk-4.0$SUF.css" -nt "$ROOT/tools/gen_gtk.py" ]; } || $PY "$ROOT/tools/gen_gtk.py" "$want" >/dev/null
# 2. KDE colour scheme (Qt apps, decorations, and through the portal everything that asks "light or dark?")
( mkdir -p "$HOME/.local/share/color-schemes"; cmp -s "$ROOT/build/kde/$SCHEME.colors" "$HOME/.local/share/color-schemes/$SCHEME.colors" || cp "$ROOT/build/kde/$SCHEME.colors" "$HOME/.local/share/color-schemes/"
  plasma-apply-colorscheme "$SCHEME" >/dev/null 2>&1 || true ) &
# 2b. how much tint the frosted app chrome carries differs per mode (light needs far less): only the opacity keys of the
#     widget style + decoration, and the window shadow (light mode needs a stronger one), then tell running Qt apps and
#     KWin to re-read them
( J="$ROOT/build/kde/$([ "$want" = light ] && echo darkly-light.json || echo darkly.json)"
  if [ -f "$J" ] && [ -f "$HOME/.config/darklyrc" ]; then
    $PY - "$J" <<'P'
import json,subprocess,sys
for group,kv in json.load(open(sys.argv[1])).items():
    for k,v in kv.items():
        if k.endswith("Opacity") or k.startswith("Shadow"): subprocess.run(["kwriteconfig6","--file","darklyrc","--group",group,"--key",k,str(v)])
P
    for o in /DarklyStyle /DarklyDecoration; do dbus-send --session --type=signal "$o" org.kde.Darkly.Style.reparseConfiguration 2>/dev/null || true; done
  fi ) &
# 3. GTK
( if head -1 "$C/gtk-3.0/gtk.css" 2>/dev/null | grep -q glass-desktop; then     # only if our GTK look is the one applied
    cp "$ROOT/build/gtk/gtk-3.0$SUF.css" "$C/gtk-3.0/gtk.css"; cp "$ROOT/build/gtk/gtk-4.0$SUF.css" "$C/gtk-4.0/gtk.css"; cp "$ROOT/build/gtk/gtk-4.0$SUF.css" "$C/gtk-4.0/gtk-dark.css"; fi
  qdbus6 org.kde.GtkConfig /GtkConfig org.kde.GtkConfig.setGtkTheme "$THEME" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface gtk-theme "$THEME" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme "prefer-$want" 2>/dev/null || true
  command -v flatpak >/dev/null && flatpak override --user --env=GTK_THEME="$THEME" 2>/dev/null || true ) &
# 4. icons: Papirus for light surfaces, Papirus-Dark for dark ones (only when a Papirus variant is in use). Last and on its
#    own: every running app reloads its icons on this one, it is the heaviest step, so it must not delay the others
( if kreadconfig6 --file kdeglobals --group Icons --key Theme | grep -Eq '^(Glass-)?Papirus'; then
    ICONS=$([ "$want" = light ] && echo Papirus || echo Papirus-Dark)      # (no head start for the other steps any more: the blend hides the order)
    # folders wear the colour theme: the theme's "folders" key, else a Papirus colour by the theme's name, else the nearest
    # Papirus colour to the accent.
    FC="$($PY - "$CFG" <<'P'
import colorsys, json, sys
try: o = json.load(open(sys.argv[1]))
except Exception: o = {}
t = o.get("themes", {}).get(o.get("theme", ""), {})
byname = {"blue": "blue", "violet": "violet", "rose": "pink", "pink": "pink", "red": "red", "amber": "orange", "orange": "orange", "yellow": "yellow", "green": "green", "teal": "teal", "cyan": "cyan", "indigo": "indigo", "magenta": "magenta", "grey": "grey", "gray": "grey"}
pal = {"blue": "5294e2", "indigo": "5c6bc0", "violet": "7e57c2", "magenta": "ca71df", "pink": "f06292", "red": "e25252", "deeporange": "eb6637", "orange": "ee923a", "yellow": "f9bd30", "green": "87b158", "teal": "16a085", "cyan": "00bcd4"}
def hue(h): r, g, b = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]; return colorsys.rgb_to_hls(r, g, b)[0]
acc = str(o.get("accent", "")).lstrip("#")
near = min(pal, key=lambda k: min(abs(hue(pal[k]) - hue(acc)), 1 - abs(hue(pal[k]) - hue(acc)))) if len(acc) == 6 else ""
print(t.get("folders") or byname.get(str(o.get("theme", "")).lower()) or near)
P
)"
    # The colour is its own icon theme (tools/folder_theme.py: Glass-<Papirus variant>-<colour>, inherits the variant).
    # Relinking the files inside Papirus kept the theme NAME, and running apps kept their cached folders (Dolphin had to
    # be restarted). A different theme name is a real icon-theme change: every toolkit reloads.
    if [ -n "$FC" ]; then DER="$($PY "$ROOT/tools/folder_theme.py" "$ICONS" "$FC" 2>/dev/null || true)"; [ -n "$DER" ] && ICONS="$DER"; fi
    done_icons=0; for h in /usr/lib/x86_64-linux-gnu/libexec/plasma-changeicons /usr/lib/libexec/plasma-changeicons /usr/libexec/plasma-changeicons /usr/lib64/libexec/plasma-changeicons /usr/lib/plasma-changeicons "$(qtpaths6 --query QT_INSTALL_LIBEXECS 2>/dev/null)/plasma-changeicons"; do [ -x "$h" ] && { "$h" "$ICONS" >/dev/null 2>&1 || true; done_icons=1; break; }; done
    [ $done_icons = 1 ] || kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ICONS"      # no changer found (Arch keeps it in /usr/lib): the key at least, apps pick it up on restart
    gsettings set org.gnome.desktop.interface icon-theme "$ICONS" 2>/dev/null || true
    # Dolphin keeps the pictures of the items it has already drawn, whatever the icon theme does: ask every open window to
    # reload its view (its own Reload action, exported on D-Bus like every KDE action; the location and tabs stay)
    # Dolphin (and other Qt apps) keep the pictures they have drawn in an in-process cache keyed by icon NAME and SIZE, not
    # by icon theme: folders in a view kept the old colour. Measured on a test window: a reload, fresh thumbnail workers,
    # KDE's change signals with an unchanged palette and zooming in and out all leave the stale pictures; a REAL palette
    # change (a light/dark switch) makes the app drop them. A colour-theme switch does not change the palette (the desktop
    # is monochrome by design), so it gets a palette change nobody can see: the tooltip text colour moves by one step of
    # 255 and back on the next switch, then apps are told the palette changed.
    ( sleep 0.8; ST="$HOME/.local/state/glass-desktop"; mkdir -p "$ST"
      if [ -n "$FC" ] && [ "$(cat "$ST/folder-colour" 2>/dev/null)" != "$FC" ]; then echo "$FC" > "$ST/folder-colour"
          cur="$(kreadconfig6 --file kdeglobals --group Colors:Tooltip --key ForegroundNormal)"
          nudged="$($PY -c 'import sys; v=[int(x) for x in sys.argv[1].split(",")]; v[2] = v[2]-1 if v[2] % 2 else (v[2]+1 if v[2] < 255 else 254); print(",".join(map(str,v)))' "${cur:-239,240,241}" 2>/dev/null)"
          [ -n "$nudged" ] && kwriteconfig6 --file kdeglobals --group Colors:Tooltip --key ForegroundNormal "$nudged"
          dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 2>/dev/null || true      # 0 = palette changed
          # Folders that show a PEEK at their contents are thumbnails, drawn by KDE's long-lived thumbnail workers with the
          # icon theme those had when they started, and kept by the view until it reloads: stop the workers (stateless, KIO
          # starts new ones on demand, with the new theme), then ask every open Dolphin window to reload its view.
          for wp in $(pgrep -u "$(id -u)" -f 'kio/thumbnail\.so' 2>/dev/null); do kill "$wp" 2>/dev/null || true; done; sleep 0.4
          # twice: the first reload's preview requests can still land on the workers that are going away, and the view then
          # shows those folders as plain icons (right colour, no peek) until something reloads it again
          for pass in 1 2; do
            for svc in $(qdbus6 2>/dev/null | grep -o "org.kde.dolphin-[0-9]*"); do for o in $(qdbus6 "$svc" 2>/dev/null | grep -o "^/dolphin/Dolphin_[0-9]*/actions/view_redisplay"); do qdbus6 "$svc" "$o" org.qtproject.Qt.QAction.trigger >/dev/null 2>&1 || true; done; done
            [ $pass = 1 ] && sleep 2.2
          done
      fi ) &
    fi ) &
wait
# the terminal's light theme carries its own lower opacity; a running Ghostty re-reads its config on SIGUSR2. Only send it
# if the process really handles that signal (bit 11 of SigCgt) — unhandled, it would close every terminal
for gp in $(pgrep -x ghostty 2>/dev/null); do cgt="$(awk '/^SigCgt/{print $2}' "/proc/$gp/status" 2>/dev/null)"; [ -n "$cgt" ] && (( 0x$cgt & 0x800 )) && kill -USR2 "$gp" 2>/dev/null || true; done
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true      # window decorations pick the new colours up for sure
echo "$want"
