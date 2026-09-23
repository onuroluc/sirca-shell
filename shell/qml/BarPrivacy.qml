// Privacy indicator for the bar: small orange glyphs while the microphone is in use (plasma-pa's SourceOutputModel, through
// the bar's shared VolumeBackend), the camera is read (PipeWire: a running Video/Source or a Stream/Input/Video consumer)
// or the screen is shared (KWin's screencast stream for a portal session). PrivacyMonitor (src/privacymonitor.cpp) listens
// to PipeWire's registry: events, no polling. Takes no room while nothing is active; a tap opens the Sound page.
import QtQuick
import SircaShell
import "Glass"

Item {
    id: priv
    property bool allowed: true
    property var audio: null
    signal clicked()
    PrivacyMonitor { id: mon; active: priv.allowed }
    readonly property bool micOn: !!audio && audio.recording > 0
    readonly property bool camOn: mon.camera
    readonly property bool screenOn: mon.screen
    readonly property int count: (micOn ? 1 : 0) + (camOn ? 1 : 0) + (screenOn ? 1 : 0)
    readonly property bool shown: allowed && count > 0
    visible: shown
    width: shown ? row.implicitWidth + 16 : 0; height: 27
    readonly property string tip: { const parts = []
        if (micOn) parts.push("Microphone: " + ((audio.recorderNames || []).join(", ") || "in use"))
        if (camOn) parts.push("Camera: " + (mon.cameraApps.join(", ") || "in use"))
        if (screenOn) parts.push("Screen: " + (mon.screenApps.join(", ") || "shared"))
        return parts.join("  ·  ") }
    Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(Config.attention.r, Config.attention.g, Config.attention.b, hh.hovered ? 0.24 : 0.14); border.width: 1; border.color: Qt.rgba(Config.attention.r, Config.attention.g, Config.attention.b, 0.45)
        Behavior on color { ColorAnimation { duration: Config.quick } } }
    Row { id: row; anchors.centerIn: parent; spacing: 6
        GlowIcon { visible: priv.micOn; anchors.verticalCenter: parent.verticalCenter; size: 13; source: "mic-on-symbolic"; color: Config.attention; hovered: hh.hovered }
        GlowIcon { visible: priv.camOn; anchors.verticalCenter: parent.verticalCenter; size: 13; source: "camera-web-symbolic"; color: Config.attention; hovered: hh.hovered }
        GlowIcon { visible: priv.screenOn; anchors.verticalCenter: parent.verticalCenter; size: 13; source: "monitor-symbolic"; color: Config.attention; hovered: hh.hovered } }
    HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: priv.clicked() }
    Timer { id: tipDelay; interval: 600; running: hh.hovered }
    Rectangle { visible: hh.hovered && !tipDelay.running && priv.tip !== ""; anchors.top: parent.bottom; anchors.topMargin: 10; anchors.horizontalCenter: parent.horizontalCenter; z: 50
        width: tipText.implicitWidth + 18; height: 26; radius: 8; color: Config.popSurface; border.width: 1; border.color: Config.fg(0.14)
        Text { id: tipText; anchors.centerIn: parent; text: priv.tip; color: Config.ink; font.pixelSize: 12 } }
}
