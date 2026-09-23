// Keyboard for the bar: the current layout's short name ("US", "DE"; KWin's org.kde.keyboard), a tap switches to the
// next one, the wheel walks them; hidden while only one layout is configured. Caps / Num lock appear as small lit
// letters in the same pill while they are on (KModifierKeyInfo over org_kde_kwin_keystate) — on their own too, so a
// stuck Caps Lock is visible even with a single layout. Config `keyboardLocks: false` leaves the locks out.
import QtQuick
import SircaShell

Item {
    id: kb
    property bool allowed: true
    KeyboardInfo { id: info }
    // the layout shows whenever the widget is placed (a placed widget that shows nothing reads as broken, 2026-09-23);
    // "keyboardHideSingle": true hides it while only one layout is configured, the old behaviour
    readonly property bool showLayout: info.layoutCount > 1 || Config.get("keyboardHideSingle", false) !== true
    readonly property bool locks: Config.get("keyboardLocks", true) !== false
    readonly property bool caps: locks && info.capsLock
    readonly property bool num: locks && info.numLock && Config.get("keyboardNumLock", false) === true   // Num Lock is on all day on most machines: shown only when asked for
    readonly property bool shown: allowed && (showLayout || caps || num)
    visible: shown
    width: shown ? row.implicitWidth + 16 : 0; height: 27
    Rectangle { visible: Config.barHoverPills; anchors.fill: parent; radius: height / 2; color: Config.fg(hh.hovered && kb.showLayout ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
    Row { id: row; anchors.centerIn: parent; spacing: 6
        Text { visible: kb.showLayout; anchors.verticalCenter: parent.verticalCenter; text: String(info.layoutShort).toUpperCase(); color: Config.ink; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.5 }
        // a lock is a filled little tag (the ink as the fill, the glass colour as the letter), like a keyboard's own LED
        Repeater { model: [ { on: kb.caps, t: "A", tip: "Caps Lock" }, { on: kb.num, t: "1", tip: "Num Lock" } ]
            Rectangle { required property var modelData; visible: modelData.on; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 4; color: Config.fg(0.85)
                Text { anchors.centerIn: parent; text: parent.modelData.t; color: Config.onFg; font.pixelSize: 10; font.weight: Font.Bold } } } }
    HoverHandler { id: hh; cursorShape: kb.showLayout ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { onTapped: if (kb.showLayout) info.nextLayout() }
    WheelHandler { enabled: kb.showLayout; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property real acc: 0
        onWheel: e => { acc += e.angleDelta.y; if (Math.abs(acc) >= 120) { const n = info.layoutCount; info.setLayout((info.layoutIndex + (acc > 0 ? n - 1 : 1)) % n); acc = 0 } } }
    readonly property string tip: { const p = []; if (showLayout) p.push(info.layoutName); if (caps) p.push("Caps Lock on"); if (num) p.push("Num Lock on"); return p.join(" · ") }
    Timer { id: tipDelay; interval: 600; running: hh.hovered }
    Rectangle { visible: hh.hovered && !tipDelay.running && kb.tip !== ""; anchors.top: parent.bottom; anchors.topMargin: 10; anchors.horizontalCenter: parent.horizontalCenter; z: 50
        width: tipText.implicitWidth + 18; height: 26; radius: 8; color: Config.popSurface; border.width: 1; border.color: Config.fg(0.14)
        Text { id: tipText; anchors.centerIn: parent; text: kb.tip; color: Config.ink; font.pixelSize: 12 } }
}
