// Clipboard history (Meta+V): what you copied, newest first. Type to filter, Enter or a click puts an entry back on the
// clipboard (then paste as usual), Delete removes the selected one. Same surface rules as Search: only the panel takes
// input, and it closes when it loses keyboard focus. The list is whatever `entries` is (the shell's ClipboardModel).
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell
import "Glass"

Window {
    id: sw
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false
    width: Screen.width; height: Screen.height
    property var entries                                 // ClipboardModel (or a test ListModel with the same roles)
    signal opened()
    readonly property int panelW: 600
    readonly property int fieldH: 58
    readonly property real listH: list.count > 0 ? Math.min(list.contentHeight + 12, 470) : 64
    property real panelH: fieldH + listH + 40
    Behavior on panelH { Spring {} }
    readonly property rect panel: Qt.rect(Math.round((width - panelW) / 2), Math.round(height * 0.20), panelW, Math.round(panelH))
    property bool setupDone: false
    property real show: 0
    Behavior on show { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    function ago(date) { if (!date) return ""; const s = Math.max(0, (Date.now() - new Date(date).getTime()) / 1000);
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + " min" : s < 86400 ? Math.floor(s / 3600) + " h" : Math.floor(s / 86400) + " d" }

    function toggle() { visible ? close_() : open() }
    function open() {
        if (!setupDone) { Shell.setupSearch(sw); setupDone = true }
        field.text = ""; list.currentIndex = 0
        visible = true; show = 1; field.forceActiveFocus(); shapeLater.restart(); sw.opened()
        armed = false; Shell.setKeyboardMode(sw, "exclusive"); relax.restart()
    }
    function close_() { if (!visible) return; visible = false; show = 0; field.text = ""; armed = false; relax.stop(); arm.stop()
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "clearLobes", "sii", ["sirca-shell", sw.width, sw.height]) }
    function pick(row) { if (!sw.entries || row < 0 || row >= list.count) return; sw.entries.select(row); close_() }
    property bool armed: false
    Timer { id: relax; interval: 160; onTriggered: { Shell.setKeyboardMode(sw, "ondemand"); arm.restart() } }
    Timer { id: arm; interval: 220; onTriggered: sw.armed = true }
    onActiveChanged: if (visible && armed && !active) lost.restart(); else lost.stop()
    Timer { id: lost; interval: 80; onTriggered: if (sw.visible && !sw.active) sw.close_() }
    Timer { id: shapeLater; interval: 16; onTriggered: sw.pushShape() }
    function pushShape() { if (!visible) return;
        Shell.setShape(sw, [{ x: panel.x, y: panel.y, w: panel.width, h: panel.height, r: Config.cornerRadius }]);
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "setLobes", "siivdd", ["sirca-shell", sw.width, sw.height, [panel.x, panel.y, panel.width, panel.height], Config.cornerRadius, 1]);
        sw.requestUpdate() }
    onPanelChanged: if (visible) shapeLater.restart()

    LobeShape { anchors.fill: parent; bar: sw.panel; reach: Qt.rect(sw.panel.x, sw.panel.y, sw.panelW, sw.fieldH + 470 + 40) }   // reach: the tallest the panel gets (listH's cap), so its spring does not resize the shadow layers per frame
    ClipboardContent { id: content; x: sw.panel.x; y: sw.panel.y; width: sw.panel.width; height: sw.panel.height; opacity: sw.show; transform: Translate { y: (1 - sw.show) * 10 }
        entries: sw.entries; fieldH: sw.fieldH
        onPicked: row => sw.pick(row); onCloseRequested: sw.close_() }
    property alias field: content.field
    property alias list: content.list
}
