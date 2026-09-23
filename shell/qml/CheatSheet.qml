// Shortcut cheat sheet (Meta+/): every global shortcut the session has, grouped by the component that owns it, the
// shell's own group first. The list is what kglobalaccel knows (ShortcutsModel asks it over D-Bus when the sheet opens),
// so KWin's window keys, Spectacle's, Plasma's and ours all appear with their real bindings, not a copy that goes stale.
// Type to filter (name, key or component). Same surface rules as the search panel: only the panel takes input, Escape
// closes (clears the filter first), and it closes when it loses keyboard focus.
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
    signal opened()
    readonly property int panelW: 760
    readonly property int fieldH: 62
    readonly property int rowH: 36
    readonly property int maxListH: Math.min(Math.round(height * 0.62), 720)
    readonly property real listH: list.count > 0 ? Math.min(list.contentHeight + 16, maxListH) : 64
    property real panelH: fieldH + listH
    Behavior on panelH { Spring {} }
    readonly property rect panel: Qt.rect(Math.round((width - panelW) / 2), Math.round(height * 0.14), panelW, Math.round(panelH))
    property bool setupDone: false
    property real show: 0
    Behavior on show { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    ShortcutsModel { id: shortcuts }
    property alias field: field                       // (offscreen previews and tests drive the panel through these)
    property alias model: shortcuts

    function toggle() { visible ? close_() : open() }
    function open() {
        if (!setupDone) { Shell.setupSearch(sw); setupDone = true }
        field.text = ""; shortcuts.filter = ""; shortcuts.refresh(); list.positionViewAtBeginning()
        visible = true; show = 1; field.forceActiveFocus(); shapeLater.restart(); sw.opened()
        armed = false; Shell.setKeyboardMode(sw, "exclusive"); relax.restart()
    }
    function close_() { if (!visible) return; visible = false; show = 0; field.text = ""; armed = false; relax.stop(); arm.stop()
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "clearLobes", "sii", ["sirca-shell", sw.width, sw.height]) }
    // focus hand-over as in Search: take the keyboard, relax to on-demand, then close on loss
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
    onWidthChanged: if (visible) shapeLater.restart()
    onHeightChanged: if (visible) shapeLater.restart()
    // "Meta+Shift+S" → ["Meta", "Shift", "S"]; a bare "+" key is the last part
    function keyParts(seq) { const s = String(seq); if (s === "+") return ["+"]; const out = []; let cur = ""; for (let i = 0; i < s.length; ++i) { const c = s[i]; if (c === "+" && cur !== "" && i < s.length - 1) { out.push(cur); cur = "" } else cur += c } if (cur !== "") out.push(cur); return out }

    LobeShape { anchors.fill: parent; bar: sw.panel; reach: Qt.rect(sw.panel.x, sw.panel.y, sw.panelW, sw.fieldH + sw.maxListH) }   // reach: the tallest the panel gets, so the spring does not resize the shadow layers per frame
    Item { x: sw.panel.x; y: sw.panel.y; width: sw.panel.width; height: sw.panel.height; clip: true
        opacity: sw.show; transform: Translate { y: (1 - sw.show) * 10 }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        // ---- the filter field
        Item { width: parent.width; height: sw.fieldH
            Kirigami.Icon { id: keyIcon; x: 22; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; source: "input-keyboard-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.75; roundToIconSize: false }
            Text { anchors.left: field.left; anchors.verticalCenter: parent.verticalCenter; visible: field.text === ""; color: Config.inkDim; font.pixelSize: 20
                text: shortcuts.loading && shortcuts.total === 0 ? "Reading shortcuts…" : "Keyboard shortcuts  ·  type to filter" }
            TextInput { id: field; anchors.left: keyIcon.right; anchors.leftMargin: 14; anchors.right: countText.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                color: Config.ink; font.pixelSize: 20; clip: true; focus: true; selectByMouse: true; selectionColor: Config.fg(0.25); selectedTextColor: Config.fgSolid
                cursorDelegate: Rectangle { width: 1.5; color: Config.fgSolid; visible: field.activeFocus }
                onTextChanged: { shortcuts.filter = text; list.positionViewAtBeginning() }
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) { if (text !== "") text = ""; else sw.close_(); e.accepted = true }
                    else if (e.key === Qt.Key_Down) { list.contentY = Math.min(list.contentY + sw.rowH * 3, Math.max(0, list.contentHeight - list.height)); e.accepted = true }
                    else if (e.key === Qt.Key_Up) { list.contentY = Math.max(0, list.contentY - sw.rowH * 3); e.accepted = true }
                    else if (e.key === Qt.Key_PageDown) { list.contentY = Math.min(list.contentY + list.height, Math.max(0, list.contentHeight - list.height)); e.accepted = true }
                    else if (e.key === Qt.Key_PageUp) { list.contentY = Math.max(0, list.contentY - list.height); e.accepted = true }
                    else if (e.key === Qt.Key_Home) { list.contentY = 0; e.accepted = true }
                    else if (e.key === Qt.Key_End) { list.contentY = Math.max(0, list.contentHeight - list.height); e.accepted = true } } }
            Text { id: countText; anchors.right: parent.right; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter; color: Config.inkDim; font.pixelSize: 12; font.features: { "tnum": 1 }
                text: shortcuts.count === shortcuts.total ? shortcuts.total : shortcuts.count + " of " + shortcuts.total } }
        Rectangle { y: sw.fieldH - 1; x: 16; width: parent.width - 32; height: 1; color: Config.fg(0.08) }
        // ---- the list, one section per component
        ListView { id: list; x: 8; y: sw.fieldH + 8; width: parent.width - 16; height: Math.max(0, sw.maxListH - 16)
            model: shortcuts; clip: true; interactive: contentHeight > height; boundsBehavior: Flickable.StopAtBounds
            section.property: "component"; section.criteria: ViewSection.FullString
            section.delegate: Item { required property string section; width: list.width; height: 34
                Text { x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; text: parent.section; color: Config.inkDim; opacity: 0.85
                    font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 } }
            delegate: Item { id: row; required property int index; required property var model; width: list.width; height: sw.rowH
                Rectangle { anchors.fill: parent; anchors.topMargin: 1; anchors.bottomMargin: 1; radius: 10; color: Config.fg(rh.hovered ? 0.06 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
                Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.right: keysRow.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: row.model.name; color: Config.ink; font.pixelSize: 13; elide: Text.ElideRight; textFormat: Text.PlainText }
                // the key caps, right-aligned; a second binding follows an "or"
                Row { id: keysRow; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Repeater { model: row.model.keyList
                        Row { id: seq; required property int index; required property var modelData; spacing: 3; anchors.verticalCenter: parent.verticalCenter
                            Text { visible: seq.index > 0; text: "or"; color: Config.inkDim; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter; rightPadding: 3 }
                            Repeater { model: sw.keyParts(seq.modelData)
                                Rectangle { required property var modelData; height: 22; width: Math.max(22, kt.implicitWidth + 12); radius: 6
                                    color: Config.fg(0.10); border.width: 1; border.color: Config.fg(0.16); anchors.verticalCenter: parent.verticalCenter
                                    Text { id: kt; anchors.centerIn: parent; text: parent.modelData; color: Config.ink; font.pixelSize: 11; font.weight: Font.Medium } } } } } }
                HoverHandler { id: rh } } }
        Text { x: 24; y: sw.fieldH + 22; visible: list.count === 0; color: Config.inkDim; font.pixelSize: 14
            text: shortcuts.loading ? "Reading shortcuts…" : (shortcuts.total === 0 ? "No shortcuts reported (is kglobalaccel running?)" : "Nothing matches") }
    }
}
