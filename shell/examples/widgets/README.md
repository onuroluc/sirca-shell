# User widgets

A widget is a folder under `~/.config/sirca-shell/widgets/<name>/` (the public build: `~/.config/sirca-shell/widgets/`).
The shell watches that folder: a new widget appears in edit mode's **Add** shelf at once, and the bar shows it as the
widget kind `user:<name>` (in `barLeft` / `barCenter` / `barRight`).

Two kinds:

- **`Widget.qml`** — any QML Item. See `hello/Widget.qml` for what it can reach (`widget.config`, `widget.shell`,
  `widget.height`, `widget.quiet`, `widget.hovered`); `import SircaShell` works too.
- **`widget.json` alone** — the built-in *Exec* type, see `uptime/`:

  ```json
  { "label": "Uptime", "icon": "chronometer-symbolic", "exec": "uptime.sh", "interval": 30, "click": "xdg-open /proc/uptime" }
  ```

  `exec` runs every `interval` seconds (`0` = once) through `/bin/sh -c`, in the widget's folder, which is also first on
  `PATH` (so `uptime.sh` needs no path, but does need its executable bit). The first line of stdout is shown, with `icon`
  (an icon theme name or a file) before it; `click` runs the same way on a tap. A non-zero exit shows the widget's name
  dimmed. `label` and `icon` also apply to a `Widget.qml` (the name in the edit shelf); `qml` names a file other than
  `Widget.qml`.

Try one: `cp -r uptime ~/.config/sirca-shell/widgets/` and drag "Uptime" from the shelf in edit mode.
