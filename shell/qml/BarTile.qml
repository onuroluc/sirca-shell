// A quick-settings tile as a bar widget (issue #8): the same data the tile in the panel shows, as an icon that is lit
// while the tile is "on". Click = the tile's own action, or the quick-settings page it belongs to (Config "barTileClick",
// per tile); middle click = the page (or the KCM); on the volume widget the wheel changes the volume with the OSD and
// middle click steps to the next output device (headphones <-> speakers in one gesture). The data comes from the quick
// settings panel (bar.nativeControl): until that has been built (about 1.5 s after start) the widget shows a plain icon.
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell

Item {
    id: tile
    property string name                                   // "volume", "network", "bluetooth", "dnd", "nightlight", "power", "caffeine", "mic"
    property var qs: null                                  // the quick settings panel item, or null
    property bool allowed: true
    signal openPage(string page)
    signal osd(string icon, real value)
    readonly property var d: qs ? qs.tileData(name) : ({ available: true, icon: fallbackIcon(name), title: name, on: false })
    function fallbackIcon(n) { switch (n) { case "volume": return "audio-volume-high-symbolic"; case "network": return "network-wired-symbolic"; case "bluetooth": return "network-bluetooth-symbolic"
        case "dnd": return "notifications-symbolic"; case "nightlight": return "redshift-status-on"; case "power": return "speedometer-symbolic"; case "caffeine": return "system-suspend-uninhibited"; case "mic": return "mic-on-symbolic" } return "emblem-system-symbolic" }
    readonly property bool shown: allowed && d.available
    visible: shown
    width: shown ? 30 : 0; height: 29
    readonly property bool hovered: hh.hovered
    Rectangle { visible: Config.barHoverPills; anchors.centerIn: parent; width: 30; height: 27; radius: 13.5; color: Config.fg(tile.hovered ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
    // lit = a soft accent disc behind the glyph, like the tile's bubble in the panel
    Rectangle { anchors.centerIn: parent; width: 22; height: 22; radius: 11; color: tile.d.on ? Config.onFill : "transparent"; opacity: tile.d.on ? 0.85 : 0; Behavior on opacity { NumberAnimation { duration: Config.normal } } }
    Kirigami.Icon { anchors.centerIn: parent; width: Math.round(16 * Config.barIconScale); height: width; source: tile.d.icon; isMask: true; roundToIconSize: false
        color: tile.d.on ? Config.onFg : Config.fgSolid; opacity: tile.d.on ? 1 : 0.85 }
    HoverHandler { id: hh }
    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: {
        if (!tile.qs) { tile.openPage(""); return }
        if (tile.qs.tileClickMode(tile.name) === "page") { const p = tile.qs.tilePage(tile.name); if (p !== "") tile.openPage(p); else tile.qs.tileOpen(tile.name) }
        else tile.qs.tileToggle(tile.name) } }
    TapHandler { acceptedButtons: Qt.MiddleButton; onTapped: {
        if (!tile.qs) return
        if (tile.name === "volume" && tile.qs.vol) { const n = tile.qs.vol.nextSink(); if (n !== "") Shell.notify("Output", n, "", ""); return }
        const p = tile.qs.tilePage(tile.name); if (p !== "") tile.openPage(p); else tile.qs.tileOpen(tile.name) } }
    WheelHandler { enabled: tile.name === "volume"; property real acc: 0
        onWheel: e => { if (!tile.qs || !tile.qs.hasSink) return; acc += e.angleDelta.y
            if (Math.abs(acc) >= 120) { const step = acc > 0 ? 5 : -5; acc = 0; const v = Math.max(0, Math.min(100, tile.qs.volumePct + step)); tile.qs.vol.setPct(v, true); tile.osd(tile.qs.volIcon(), v / 100) } } }
}
