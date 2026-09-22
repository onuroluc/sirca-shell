// The desktop's right-click menu: a small glass panel at the pointer. Same mechanics as the power menu (one full-screen
// overlay surface whose shape and input are only the panel; it takes the keyboard and closes when it loses it), so a click
// anywhere else lands where it was aimed. Arrows + Enter work, Esc closes.
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell
import "Glass"

Window {
    id: dm
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false
    width: Screen.width; height: Screen.height
    signal opened()
    signal action(string id)
    // t: "item" | "sep" | "themes"
    readonly property var entries: [
        { t: "item", id: "wallpaper", label: "Change Wallpaper…", icon: "preferences-desktop-wallpaper-symbolic" },
        { t: "item", id: "edit", label: "Customise Bar and Dock…", icon: "document-edit-symbolic" },
        { t: "themes" },
        { t: "sep" },
        { t: "item", id: "terminal", label: "Open Terminal", icon: "utilities-terminal-symbolic" },
        { t: "item", id: "files", label: "Open Files", icon: "system-file-manager-symbolic" },
        { t: "sep" },
        { t: "item", id: "displays", label: "Display Settings…", icon: "video-display-symbolic" },
        { t: "item", id: "system", label: "System Settings…", icon: "preferences-system-symbolic" },
        { t: "item", id: "glass", label: "Sirca Settings…", icon: "configure" },
        { t: "sep" },
        { t: "item", id: "lock", label: "Lock Screen", icon: "system-lock-screen-symbolic" },
        { t: "item", id: "power", label: "Power…", icon: "system-shutdown-symbolic" } ]
    readonly property bool hasThemes: Object.keys(Config.themes).length > 1
    function hOf(e) { return e.t === "sep" ? 9 : (e.t === "themes" ? (hasThemes ? 46 : 0) : 34) }
    readonly property int panelW: 268
    readonly property int panelH: { let h = 16; for (const e of entries) h += hOf(e); return h }
    property point at: Qt.point(200, 200)
    readonly property rect panel: Qt.rect(Math.max(8, Math.min(width - panelW - 8, at.x)), Math.max(8, Math.min(height - panelH - 8, at.y)), panelW, panelH)
    property int current: -1
    property bool setupDone: false
    property real show: 0
    Behavior on show { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    readonly property var themeNames: { const hue = n => { const h = Qt.color((Config.themes[n] || {}).accent || "#888").hslHue; return h > 0.93 ? h - 1 : h }   // literal-ok: fallback swatch
        return Object.keys(Config.themes).sort((a, b) => hue(a) - hue(b)) }

    function openAt(x, y) {
        if (!setupDone) { Shell.setupSearch(dm); setupDone = true }
        at = Qt.point(x, y); current = -1; visible = true; show = 1; keys.forceActiveFocus(); shapeLater.restart(); dm.opened()
        focusArmed = false; Shell.setKeyboardMode(dm, "exclusive"); relax.restart()
    }
    function close_() { if (!visible) return; visible = false; show = 0; focusArmed = false; relax.stop(); arm.stop()
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "clearLobes", "sii", ["sirca-shell", dm.width, dm.height]) }
    function run(id) { close_(); dm.action(id) }
    function step(d) { const n = entries.length; let i = current; for (let k = 0; k < n; ++k) { i = (i + d + n) % n; if (entries[i].t === "item") { current = i; return } } }

    property bool focusArmed: false
    Timer { id: relax; interval: 160; onTriggered: { Shell.setKeyboardMode(dm, "ondemand"); arm.restart() } }
    Timer { id: arm; interval: 220; onTriggered: dm.focusArmed = true }
    onActiveChanged: if (visible && focusArmed && !active) lost.restart(); else lost.stop()
    Timer { id: lost; interval: 80; onTriggered: if (dm.visible && !dm.active) dm.close_() }
    Timer { id: shapeLater; interval: 16; onTriggered: dm.pushShape() }
    function pushShape() { if (!visible) return
        Shell.setShape(dm, [{ x: panel.x, y: panel.y, w: panel.width, h: panel.height, r: 16 }])
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "setLobes", "siivdd", ["sirca-shell", dm.width, dm.height, [panel.x, panel.y, panel.width, panel.height], 16, 1])
        dm.requestUpdate() }

    LobeShape { anchors.fill: parent; bar: dm.panel; radius: 16 }
    Item { id: keys; x: dm.panel.x; y: dm.panel.y; width: dm.panel.width; height: dm.panel.height; focus: true
        opacity: dm.show; scale: 0.96 + 0.04 * dm.show; transformOrigin: Item.TopLeft
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { dm.close_(); e.accepted = true }
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { dm.step(1); e.accepted = true }
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) { dm.step(-1); e.accepted = true }
            else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && dm.current >= 0) { dm.run(dm.entries[dm.current].id); e.accepted = true } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Column { x: 8; y: 8; width: parent.width - 16
            Repeater { model: dm.entries
                Item { id: row; required property var modelData; required property int index; width: parent.width; height: dm.hOf(modelData); visible: height > 0
                    // separator
                    Rectangle { visible: row.modelData.t === "sep"; anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: Config.fg(0.10) }
                    // an entry
                    Rectangle { visible: row.modelData.t === "item"; anchors.fill: parent; radius: 10
                        color: Config.fg(it.pressed ? 0.18 : (dm.current === row.index ? 0.11 : 0)); Behavior on color { ColorAnimation { duration: 90 } } }
                    Kirigami.Icon { visible: row.modelData.t === "item"; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; source: row.modelData.icon || ""; isMask: true; color: Config.fgSolid; opacity: 0.85; roundToIconSize: false }
                    Text { visible: row.modelData.t === "item"; x: 38; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.label || ""; color: Config.ink; font.pixelSize: 13 }
                    HoverHandler { enabled: row.modelData.t === "item"; onHoveredChanged: if (hovered) dm.current = row.index; else if (dm.current === row.index) dm.current = -1 }
                    TapHandler { id: it; enabled: row.modelData.t === "item"; onTapped: dm.run(row.modelData.id) }
                    // colour themes + light / dark, right in the menu
                    Row { visible: row.modelData.t === "themes" && dm.hasThemes; anchors.verticalCenter: parent.verticalCenter; x: 8; spacing: 6
                        Repeater { model: row.modelData.t === "themes" ? dm.themeNames : []
                            Item { id: sw; required property string modelData; readonly property bool cur: Config.theme === modelData; width: 24; height: 24
                                Rectangle { anchors.fill: parent; radius: 12; color: "transparent"; border.width: 2; border.color: sw.cur ? Config.fgSolid : "transparent" }
                                Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 8; color: (Config.themes[sw.modelData] || {}).accent || "#888"   // literal-ok: fallback swatch. 16 in 24: a whole-pixel offset (15 sat at 4.5 px: the disc drifted off the ring)
                                    scale: swh.hovered && !sw.cur ? 1.18 : 1; Behavior on scale { NumberAnimation { duration: Config.quick } } }
                                HoverHandler { id: swh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: dm.run("theme:" + sw.modelData) } } } }
                    Item { visible: row.modelData.t === "themes" && dm.hasThemes; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30
                        Rectangle { anchors.fill: parent; radius: 15; color: Config.fg(mh.hovered ? 0.14 : 0.07) }
                        Kirigami.Icon { anchors.centerIn: parent; width: 15; height: 15; source: Config.dark ? "weather-clear-symbolic" : "weather-clear-night-symbolic"; isMask: true; color: Config.fgSolid; roundToIconSize: false }
                        HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: dm.run("mode") } } } } } }
}
