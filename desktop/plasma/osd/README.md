# glass-osd - custom Plasma OSD (volume / brightness / keyboard layout) in the Glass Control style

Plasma 6.6 loads the OSD from the QML module `org.kde.plasma.workspace.osd` (via
`SharedQmlEngine::setSourceFromModule`), not from the look-and-feel package, so the only
way to replace it without patching plasma-workspace is to shadow that module:

* `~/.local/lib/qt6/qml/org/kde/plasma/workspace/osd/` - `Osd.qml` (this repo), `qmldir`
  (this repo; declares the plugin as *required*, so Qt loads the module from this
  directory instead of the system one, whose qmldir `prefer`s its compiled-in resources),
  plus `OsdItem.qml` + `plasmashell_osd.qmltypes` copied from the system module and a
  symlink `libplasmashell_osd.so` → the system plugin.
* `~/.config/systemd/user/plasma-plasmashell.service.d/osd-override.conf` - sets
  `QML_IMPORT_PATH=%h/.local/lib/qt6/qml` for plasmashell only.

Install: copy the files as above, `systemctl --user daemon-reload && systemctl --user restart plasma-plasmashell`.
Test: `qdbus6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.volumeChanged 62`.
Revert: remove the drop-in, daemon-reload, restart plasmashell.
After a plasma-workspace upgrade re-copy `OsdItem.qml`/`plasmashell_osd.qmltypes` and re-check the symlink.

