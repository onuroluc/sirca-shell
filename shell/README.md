# Sirca Shell

A liquid-glass shell for KDE Plasma 6 on Wayland. It replaces Plasma's panels with its own top bar and dock; KWin stays
the window manager. Popups are not separate windows: they grow out of the bar and the dock as one glass shape.

> **Status: alpha.** Built for and tested on exactly one machine: Plasma 6.6, Ubuntu 26.04, NVIDIA, one 5120×1440
> screen. It works there every day. Other screen sizes, several monitors, other Plasma versions and other GPUs are
> untested. It can always be switched off again with one command, and it switches itself off if it keeps crashing.

## What is in it

- **Top bar** — show desktop, workspaces, tray (StatusNotifier host with its own menus), focused window title, clock
  (volume and brightness changes show inside the clock pill), now-playing with a live level meter, notifications,
  quick settings; optional date and CPU / memory widgets.
- **Dock** — pinned and running apps, hover zoom, window previews with peek, per-window pills, badges, drag to
  reorder, launch hop; the app launcher grows out of it.
- **Popups** — launcher with search, quick settings (network, Bluetooth, audio, brightness, night light, power),
  calendar, notification history grouped per app, now-playing panel, tray menus.
- **Tools** — search (Meta+Space, KRunner's engine: apps, files, settings, and sums or conversions such as `12*7` or
  `5 km in mi`), clipboard history (Meta+V; Ctrl+P pins an entry: it stays on top and survives "Clear"), screenshot and screen recording
  (Meta+Shift+S / Meta+Shift+R), tile picker for wide screens (Meta+A), window switcher (Alt+Tab), power menu
  (Ctrl+Alt+Del).
- **Do Not Disturb, timed** — the quick-settings tile steps through: an hour, until the morning, until switched off.
- **A welcome card** on the first start names the things nobody finds alone (again: `qdbus6 onur.SircaShell /SircaShell onur.SircaShell.showWelcome`).
- **Edit mode** — right click an empty spot on the bar or the dock. Widgets become chips you drag between left, centre
  and right or remove; handles resize the bar; two strips hold every option (sizes, width modes, blur / tint / edge /
  sheen / shadow / haze per surface, clock format, dock behaviour …). Everything applies while you drag.
- **Safety** — `sirca-shell-reload` refuses a build that does not load; five crashes in a minute restore the Plasma
  panels automatically; your Plasma layout is saved and restored exactly.

## What it needs

- KDE Plasma **6.6** on **Wayland** (KWin). Not X11, not other compositors.
- For the glass look: the glass KWin effect in `../kwin-effects` (the installer builds it). Without it the shell runs, but the bar and dock are flat tinted shapes without blur or a lit edge.
- Optional: `gpu-screen-recorder` and `ffmpeg` (screen recording), the Mudeer KWin script (the tile picker uses its
  gaps; without it the shell places windows itself), Dolphin ("Show in folder").
- The matching themes (GTK, Qt, window decoration, lock screen) live in `../desktop`.

### Build dependencies

Ubuntu / Debian names:

```
sudo apt install build-essential cmake extra-cmake-modules qt6-base-dev qt6-declarative-dev \
  liblayershellqtinterface-dev libplasma-dev kwayland-dev libkf6windowsystem-dev libkf6package-dev \
  libkf6config-dev libkf6i18n-dev libkf6globalaccel-dev libkf6service-dev libkf6guiaddons-dev
```

Runtime QML modules (normally present on a Plasma desktop): `plasma-workspace`, `plasma-nm`, `plasma-pa`, `powerdevil`,
`milou`, `qml6-module-org-kde-pipewire`, `qml6-module-org-kde-bluezqt`, `qml6-module-qt5compat-graphicaleffects`.

Fedora (tested in a Fedora 44 sandbox, Plasma 6.7.5):

```
sudo dnf install cmake gcc-c++ extra-cmake-modules qt6-qtbase-devel qt6-qtdeclarative-devel layer-shell-qt-devel \
  libplasma-devel kf6-kwayland-devel kf6-kwindowsystem-devel kf6-kpackage-devel kf6-kconfig-devel kf6-ki18n-devel \
  kf6-kglobalaccel-devel kf6-kservice-devel kf6-kguiaddons-devel
```

Runtime on Fedora: `plasma-milou` (the search; the shell exits without it), `plasma-nm plasma-pa powerdevil kpipewire kf6-bluez-qt qt6-qt5compat`.

and for the KWin effect: `kwin-devel kdecoration-devel kf6-kcmutils-devel libepoxy-devel libdrm-devel vulkan-headers`
(KWin's development files need epoxy, drm and the Vulkan headers to be found by CMake, and Fedora does not pull them in).
For the Qt style and decoration: `kf6-frameworkintegration-devel kf6-kcolorscheme-devel kf6-kiconthemes-devel
kf6-kirigami-devel qt6-qtdeclarative-devel`.

On Arch the equivalents are `extra-cmake-modules qt6-base qt6-declarative layer-shell-qt libplasma kwayland
kwindowsystem kpackage kconfig ki18n kglobalaccel kservice kguiaddons` plus `plasma-workspace plasma-nm plasma-pa
powerdevil milou kpipewire bluez-qt qt6-5compat` (untested).

## Install

```
./install.sh                 # builds and installs to ~/.local, no root
sirca-shell-switch on        # saves your Plasma layout, removes Plasma's panels, starts the shell
```

Back to stock Plasma at any time:

```
sirca-shell-switch off       # stops the shell and restores the saved layout exactly
./uninstall.sh               # also removes the files
```

`sirca-shell-switch status` shows where things stand. `sirca-shell-switch plasma off` runs the session without
plasmashell at all (the shell then draws the wallpaper and serves the volume / brightness display); `plasma on` brings
it back. That mode is experimental: there is no desktop right-click menu and there are no desktop icons.

KWin only gives a program the window list, screenshots and input replay if a desktop file asks for them **and its
`Exec=` is the path of the running binary**. `install.sh` takes care of that; if you move the binary, reinstall.

## Settings

Everything is a key in `~/.config/sirca-shell/config.json`; the file is watched, changes apply at once. Edit mode and the
Sirca Settings window (in the launcher, or `qdbus6 onur.SircaShell /SircaShell openSettings`) write the same file. An
empty file is the default look. A few keys:

| key | meaning |
| --- | --- |
| `barWidthMode` | `auto` (scaled to the monitor), `fill`, `fit`, `custom` (+ `barWidth`) |
| `barLeft` `barCenter` `barRight` | widget names per group: `desktop workspaces tray title clock date system media bell gear` |
| `barBlur` `barTintAlpha` `barRimAlpha` `barSheen` `barShadow` `barHazeStrength` | the bar's glass (dock: `dock…`, haze: `hazeStrength`) |
| `barDodge` `dockDodge` | slide away under windows instead of reserving space |
| `mode` | `dark` or `light`: everything drawn on the glass flips (the Appearance tile in quick settings; with glass-desktop's `glass-mode` the whole desktop follows) |
| `themes` `theme` | colour themes: `{name: {accent, light, dark}}` (accent + a wallpaper per mode), shown as swatches in quick settings |
| `launchers` `favorites` | pinned dock apps, launcher favourites |
| `welcomed` | `true` once the first-run card has been closed |
| `trayHidden` | list of tray item ids or titles to keep out of the bar, e.g. `["polychromatic-tray-applet"]` |
| `recordSound` `levelMeter` `quietWhenBusy` `showFps` | behaviour switches |
| `dockDodgeMode` `dockTintAlphaTouched` | which windows make the dock leave: `all`, `active` (the focused one), `maximized`; the denser tint (0.85) while a window lies over a dock that stays |
| `weather` `weatherLocation` `weatherUnits` | off by default. On, the clock popup gets a weather card and the bar a `weather` widget (Open-Meteo, no key; one request every 30 min while on, cached in `~/.cache/sirca-shell/weather.json`). `weatherLocation`: `{"lat": 41.0, "lon": 29.0, "name": "Istanbul"}`; without it GeoClue is asked once. Units `c` or `f` |
| `disks` (a bar widget) | removable drives: a lobe with every USB stick / card / external disc, Open (mounts first) and Eject / Unmount, from UDisks2 over D-Bus |
| `levelMeterStyle` | `bars` (the four peak bars) or `spectrum`: 32 bands from a PipeWire capture of the sink's monitor plus an FFT, only while music plays and the bar is on screen (one extra capture node then, ~25 small FFTs a second) |
| `lyrics` | off by default. On, the now-playing lobe looks the track up on LRCLIB (lrclib.net, no key) while it is open and shows synced lines that follow the player (a click seeks) or the plain text; answers are cached per track in `~/.cache/sirca-shell/lyrics/` |
| `calendarDirs` | folders of `.ics` files for the clock popup (default: `~/.local/share/sirca-shell/calendars` plus khal / vdirsyncer stores that exist); dots on the days, the picked day's events, the next one under the clock. Nothing leaves the machine |

## Sharing a setup

`sirca-shell-setup export my-setup.json` writes the look and layout (bar and dock layout, sizes, glass values, clock, colour
themes, accent, mode) as one file; `sirca-shell-setup import their-setup.json` takes one in. Pinned apps, favourites,
hidden tray items and wallpaper paths are left out of an export (`--wallpapers` keeps the paths). An import only accepts
known look keys with sane values, never runs anything, keeps your own wallpapers for themes you already have, and writes a
`config.json.bak-<time>` first.

## Scripting

`qdbus6 onur.SircaShell /SircaShell` lists the D-Bus methods: `toggleLauncher`, `toggleLobe <name>`, `toggleSearch`,
`toggleClipboard`, `toggleTiles`, `tileActive <x> <width>` (fractions of the screen), `screenshot`,
`grabRegion x y w h`, `record`, `recordRegion x y w h`, `toggleEditMode`, `togglePowerMenu`, `openSettings`, `showWelcome`.

## What works, what does not (yet)

| | |
|---|---|
| KDE Plasma 6.6 on **Wayland**, KWin as the compositor | works, this is what it is built and used on |
| X11 session, other compositors | no: the shell is layer-shell windows plus KWin's D-Bus and protocols |
| One screen | works; the bar and dock are on the primary output |
| Several screens | wallpaper on every screen; the bar and dock on the primary, or on any screen you choose in edit mode (Screens). Tested with virtual screens only |
| Without plasmashell (`sirca-shell-switch plasma off`) | works for daily use; Plasma's desktop widgets and its clipboard applet are gone, the shell brings its own wallpaper, clipboard and notifications |
| The glass look (blur, refraction, rim) | needs the companion KWin effect; without it the bar and dock are plain translucent surfaces |
| Light and dark | both; with the companion `glass-mode` script the whole desktop switches with one cross-fade |
| Screen recording | needs `gpu-screen-recorder` (and `ffmpeg` for HDR screens); without it a recording ends at once with a notification that says so |
| NVIDIA | developed on it (open kernel driver); AMD and Intel are untested by the author |

## Known limits

- One screen. The bar and dock appear on the primary output only.
- The bar is a pill: its corner radius is fixed by the glass effect. The dock sits at the bottom only.
- Recording captures through the display hardware (KMS), so the desktop must not be HDR-tonemapped by something else;
  with HDR on, recordings are tonemapped to SDR when you stop.
- The fallbacks that host real Plasma applets (tray, quick settings, launcher, calendar, notifications as `native… = false`)
  need forked applets that are not part of this repository yet.
- Identifiers such as the D-Bus name `onur.SircaShell` carry the author's name and may change before a 1.0.

## Layout of the code

- `src/` — C++: layer-shell setup, shapes → blur region and input mask, global shortcuts, D-Bus, config, tray host,
  apps model, clipboard, screenshots, recording.
- `qml/` — everything you see. `Surface.qml` is a layer-shell window whose shape is the union of its lobes;
  `TopBar.qml`, `Dock.qml`; `EditScene.qml`; `Config.qml` holds every token and default.
- `sirca-shell --check` compiles every QML file without showing anything; `sirca-shell-reload` runs it before a restart.

## Licence and credits

GPL-3.0-or-later, see `LICENSE`.

- `qml/control/` (the "classic" quick-settings pages) derives from **Plasma Control Hub** by zayronxio, GPL-3.0-or-later.
- `applets/` holds forks of KDE Plasma's system tray and notifications applets (KDE contributors; LGPL-2.0-or-later and
  GPL-2.0-or-later, headers kept in the files).
- The glass itself is drawn by a fork of **kwin-effects-glass** by 4v3ngR.
- The emoji list (`qml/data/emoji.json`) is built from Unicode's `emoji-test.txt` (© Unicode, Inc., Unicode License v3) by `scripts/gen-emoji.py`.
- Built on Qt, KDE Frameworks, libplasma and LayerShellQt.
