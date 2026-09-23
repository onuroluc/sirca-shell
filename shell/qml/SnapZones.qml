// Snap zones: while a window is being dragged (scripts/kwin-snap-zones.js reports through KwinSnap), a slim strip of
// the tile layouts appears under the bar. The zone under the pointer lights up; dropping the window there tiles it
// (Shell.tileActiveWindow: x and width as fractions of the screen, full height). Nothing else changes: a drop anywhere
// else is an ordinary move. Config `snapZones` (default true) switches the strip AND the KWin script off.
// The layouts mirror qml/Tiles.qml (the Meta+A picker); this file only needs their [x, w] fractions.
import QtQuick
import SircaShell
import "Glass"

Window {
    id: sz
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false
    width: Screen.width; height: Screen.height
    readonly property bool enabled: Config.get("snapZones", true)
    readonly property var layouts: [
        { name: "Halves", zones: [ [0, 1/2], [1/2, 1/2] ] },
        { name: "Thirds", zones: [ [0, 1/3], [1/3, 1/3], [2/3, 1/3] ] },
        { name: "Quarters", zones: [ [0, 1/4], [1/4, 1/4], [1/2, 1/4], [3/4, 1/4] ] },
        { name: "Wide middle", zones: [ [0, 1/4], [1/4, 1/2], [3/4, 1/4] ] },
        { name: "Two thirds + third", zones: [ [0, 2/3], [2/3, 1/3] ] },
        { name: "Third + two thirds", zones: [ [0, 1/3], [1/3, 2/3] ] },
        { name: "Three quarters + quarter", zones: [ [0, 3/4], [3/4, 1/4] ] },
        { name: "Quarter + three quarters", zones: [ [0, 1/4], [1/4, 3/4] ] },
        { name: "Centred two thirds", zones: [ [1/6, 2/3] ] },
        { name: "Whole screen", zones: [ [0, 1] ] } ]
    // one small screen per layout, in a row; sized so ten of them fit a 1920 screen with air around them
    readonly property int miniW: Math.min(128, Math.floor((width - 80) / layouts.length) - 10)
    readonly property int miniH: Math.round(miniW * 9 / 32)
    readonly property int gap: 10
    readonly property int pad: 10
    readonly property int panelW: layouts.length * miniW + (layouts.length + 1) * gap
    readonly property int panelH: miniH + 2 * pad
    // under the bar, with a little air: the window's title bar is under the pointer, the strip must not sit under it
    readonly property rect panel: Qt.rect(Math.round((width - panelW) / 2), Config.barHeight + Config.barGap * 2 + 14, panelW, panelH)
    property point cursor: Qt.point(-1, -1)          // in this window's coordinates; (-1,-1) = nowhere
    property bool setupDone: false
    property real show: 0
    Behavior on show { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    // the KWin script follows the config key; the shell owns the object, so this is the one place that switches it
    Component.onCompleted: KwinSnap.enabled = sz.enabled
    onEnabledChanged: { KwinSnap.enabled = sz.enabled; if (!sz.enabled) sz.close_() }
    Connections { target: KwinSnap
        function onStarted() { if (sz.enabled) sz.open() }
        function onMoved(x, y) { if (sz.visible) sz.cursor = sz.local(x, y) }
        function onFinished(x, y) { sz.drop(x, y) } }
    function local(x, y) { return Qt.point(x - Screen.virtualX, y - Screen.virtualY) }

    // geometry of the small screens and their zones, shared by the painter and the hit test
    function miniRect(i) { return Qt.rect(panel.x + gap + i * (miniW + gap), panel.y + pad, miniW, miniH) }
    function zoneRect(i, z) { const m = miniRect(i); return Qt.rect(m.x + 3 + z[0] * (m.width - 6) + 1.5, m.y + 3, z[1] * (m.width - 6) - 3, m.height - 6) }
    function inRect(r, p) { return p.x >= r.x && p.y >= r.y && p.x < r.x + r.width && p.y < r.y + r.height }
    // the zone under a point, as {x, w} fractions, or null. The hit area is generous: the whole strip height, the small
    // screen plus half the gap on each side, and the zones split it at their fractions (no dead pixels between them)
    function zoneAt(p) {
        for (let i = 0; i < layouts.length; ++i) {
            const m = miniRect(i); const wide = Qt.rect(m.x - gap / 2, panel.y, m.width + gap, panel.height)
            if (!inRect(wide, p)) continue
            const fx = Math.min(0.9999, Math.max(0, (p.x - m.x) / m.width)), zones = layouts[i].zones
            for (let k = 0; k < zones.length; ++k) if (fx >= zones[k][0] && fx < zones[k][0] + zones[k][1]) return { x: zones[k][0], w: zones[k][1], i: i, k: k }
        }
        return null }
    readonly property var hot: zoneAt(cursor)

    function open() {
        if (!setupDone) { Shell.setupSearch(sz); Shell.setKeyboardMode(sz, "none"); setupDone = true }   // overlay layer, and never the keyboard: the dragged window keeps it
        cursor = Qt.point(-1, -1); visible = true; show = 1; shapeLater.restart() }
    function close_() { if (!visible) return; visible = false; show = 0; cursor = Qt.point(-1, -1)
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "clearLobes", "sii", ["sirca-shell", sz.width, sz.height]) }
    function drop(x, y) { const z = visible ? zoneAt(local(x, y)) : null; close_(); if (z) { later.zone = z; later.restart() } }
    // KWin has just finished its own move; let that settle before the tile script moves the window again
    Timer { id: later; interval: 60; property var zone: null; onTriggered: { const z = later.zone; later.zone = null; if (z) Shell.tileActiveWindow(z.x, z.w) } }
    Timer { id: shapeLater; interval: 16; onTriggered: sz.pushShape() }
    function pushShape() { if (!visible) return
        Shell.setShape(sz, [{ x: panel.x, y: panel.y, w: panel.width, h: panel.height, r: 16 }])
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "setLobes", "siivdd", ["sirca-shell", sz.width, sz.height, [panel.x, panel.y, panel.width, panel.height], 16, 1])
        sz.requestUpdate() }

    LobeShape { anchors.fill: parent; bar: sz.panel; radius: 16 }
    Item { x: sz.panel.x; y: sz.panel.y; width: sz.panel.width; height: sz.panel.height
        opacity: sz.show; transform: Translate { y: (1 - sz.show) * -6 }
        Repeater { model: sz.layouts
            Rectangle { id: mini; required property int index; required property var modelData
                x: sz.miniRect(index).x - sz.panel.x; y: sz.pad; width: sz.miniW; height: sz.miniH; radius: 7
                color: Qt.rgba(0, 0, 0, 0.22); border.width: 1; border.color: Config.fg(sz.hot && sz.hot.i === index ? 0.30 : 0.10)
                Repeater { model: mini.modelData.zones
                    Rectangle { id: zone; required property int index; required property var modelData
                        readonly property bool lit: !!sz.hot && sz.hot.i === mini.index && sz.hot.k === index
                        readonly property rect r: sz.zoneRect(mini.index, modelData)
                        x: r.x - sz.miniRect(mini.index).x; y: r.y - sz.miniRect(mini.index).y; width: r.width; height: r.height; radius: 5
                        color: lit ? Config.onFill : Config.fg(0.09); border.width: 1; border.color: Config.fg(lit ? 0.6 : 0.16)
                        Behavior on color { ColorAnimation { duration: Config.quick } } } } } }
    }
}
