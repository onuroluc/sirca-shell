// The level meter's own little window (see Shell::setupPatch): the four bars of MediaIsland, drawn here instead of on the
// bar surface, so a change of a few pixels does not repaint (and re-blur) the whole bar. It sits exactly over the island's
// meter slot and follows it; it is unmapped while nothing plays or the bar is away.
import QtQuick
import SircaShell

Window {
    id: patch
    property var host: null                       // the island's meter Row: position, screen, and whether it is live
    property var shown: [0, 0, 0, 0]
    property bool live: false
    property int gx: 0
    property int gy: 0
    width: 16; height: 14
    color: "transparent"; flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput
    title: "glass-meter"
    visible: false
    // set up before the first show (a layer window shown before its layer is set is an ordinary window); then follow live
    Component.onCompleted: { if (host) screen = host.Window.window.screen; Shell.setupPatch(patch, gx, gy); visible = live }
    onLiveChanged: visible = live
    onGxChanged: Shell.movePatch(patch, gx, gy)
    onGyChanged: Shell.movePatch(patch, gx, gy)
    Row { spacing: 2.5; anchors.verticalCenter: parent.verticalCenter; height: 14
        Repeater { model: 4
            Rectangle { required property int index
                readonly property real level: patch.shown[index] || 0
                width: 2; radius: 1; anchors.verticalCenter: parent.verticalCenter
                height: 3 + 11 * level
                color: Config.fg(0.5 + 0.45 * level) } }      // no Behavior: the value changes 25x a second
    }
}
