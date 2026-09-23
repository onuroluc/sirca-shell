# Changes

Versions, newest first. `./update.sh` brings you to the newest one; the shell can also check once a day (Sirca Settings › Behaviour › Updates).

## 0.7.0 (2026-09-23)

- Fixed: on a fresh install the KWin effect blurred nothing until "Blur all except matching" was chosen in its settings
  (the default was a whitelist of placeholder window classes inherited from Better Blur). Now it blurs every window that
  asks for it, out of the box. (#9)
- Fixed: a faint grain band above popups and outside rounded corners (the noise was drawn over the blur region's
  rectangles; it is now part of the shape-masked pass). The "ghost panel" of #9.
- Fixed: unfocused windows had brighter, thicker corner arcs than their edges (the decoration's corner compensation was tuned for the focused outline only; it is now a setting per state).
- The effect's defaults are now the look from the screenshots (blur, refraction, corner radii, noise, saturation); a
  fresh install used to run with Better Blur's defaults and looked like a different effect.
- Bar and dock: choose what happens with windows (never touch / hide under them / windows go below), and a look for each
  state: when a window touches the surface, when a window is maximised, when a full-screen window has focus (hide, or
  keep it on top). Each with its own opacity, blur, and for the bar width and corners. Edit mode > Bar / Dock. (#7)
- Quick-settings tiles as bar widgets: Volume, Network, Bluetooth, Do Not Disturb, Night Light, Power profile, Caffeine
  and Microphone can sit in the bar (edit mode > Add). Click toggles or opens the page (your choice per tile in Sirca
  Settings > Top bar), scroll on Volume changes it, middle click on Volume jumps to the next output. (#8)

## 0.6.1 (2026-09-23)

- Wording only: the README, this file and the installer's text, no code changes.

## 0.6.0 (2026-09-23)

- Start-up self-test: six seconds after start the shell checks that the bar and dock drew, its shortcuts are registered,
  fake input was granted, the Glass effect is loaded and a notification server exists. One journal line
  (`journalctl --user -u sirca-shell | grep self-test`); a notification only when something is missing.
- Crash report: after a crash-restart the previous run's last log lines go to a report file, with "Show report" and
  "File an issue" on the notification.
- Fixed: a single crash switched the shell off and restored the Plasma panels (the fallback fired on every failure, not
  only after repeated ones). Now it only acts when the shell really keeps crashing. `./update.sh` installs the fixed unit.
- Screenshots no longer freeze the desktop while a big PNG is written (the encode moved off the UI thread).
- Running without plasmashell (`sirca-shell-switch plasma off`) is now a complete session: the shell tells the login
  splash the desktop is up, and serves the OSD, notifications and the desktop itself.
- `levelMeterOverlay`: the level bars in a window of their own (opt-in, for weak integrated GPUs).

Measured on the author's machine (Ryzen 7 7800X3D, RTX 5080, one 5120x1440 screen, Plasma 6.6.6), from systemd's
CPU accounting of whole-day sessions, so real use rather than a benchmark:

| | CPU over a day | memory peak |
|---|---|---|
| plasmashell with its panels | 1.4–1.6 % of one core | 0.7–1 GB |
| Sirca Shell, doing the same job | 0.2–0.4 % | 0.4–0.8 GB (about 420 MB resident) |

Start to first frame is about 0.4 s. A notification card used to cost 10 % CPU and 11 % GPU while it was on screen
(the bar repainted every frame); since 0.5.0 it is close to nothing. Popups and idle are the same as before.

## 0.5.0 (2026-09-23)

The first numbered version. Everything before this was "whatever main was" - from here on main only moves when a version is
released, and hotfixes get their own number (0.5.1, …).

Since the last un-numbered push:
- Quick settings: right-click a tile to show, hide and reorder tiles (also a list in Sirca Settings › Top bar).
- New tiles: Power profile, Caffeine, Microphone, Follow the sun; VPN connections in the Network page.
- New bar widgets: battery, microphone (while something records), privacy (mic / camera / screen share), keyboard layout,
  weather, removable disks, and your own widgets (`shell/examples/widgets`).
- Meta+/ shows every shortcut. Search: emoji (`:`) and a colour picker (`pick`). Notifications: search, urgency, Meta+Shift+N clears.
- Click the CPU / memory widget for a system monitor.
- Dock: drop a file on an app, mouse wheel switches its windows, progress bars, one wiggle on attention, dodge modes.
- Calendar events from .ics files, weather (opt-in), lyrics (opt-in), a spectrum level meter, accent colour from the wallpaper.
- Snap zones while you drag a window (switchable).
- Installer: the "Install now?" prompt was inverted; widget style is selected; blur and icon theme are restored on uninstall.
- Performance: a notification card no longer repaints the bar every frame; ~15 MB less memory.
- KWin effect: quality tiers, "reduce on battery", shader overrides are per build.
