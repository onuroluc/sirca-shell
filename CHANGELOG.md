# Changes

Versions, newest first. `./update.sh` brings you to the newest one; the shell can also check once a day (Sirca Settings › Behaviour › Updates).

## 0.5.0 — 2026-09-23

The first numbered version. Everything before this was "whatever main was" — from here on main only moves when a version is
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
