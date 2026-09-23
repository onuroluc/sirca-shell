// Microphone for the bar: appears ONLY while an app records from a source (plasma-pa's SourceOutputModel has a
// non-virtual row), shows whether the default source is muted, a tap mutes / unmutes it. `audio` is the bar's shared
// VolumeBackend instance (a Loader in TopBar; null when the private plasma-pa module is missing, then nothing shows).
import QtQuick
import SircaShell
import "Glass"

Item {
    id: mic
    property bool allowed: true
    property var audio: null
    readonly property bool shown: allowed && !!audio && audio.recording > 0
    readonly property bool muted: !!audio && audio.micMuted
    visible: shown
    width: shown ? 30 : 0; height: 27
    readonly property string tip: { if (!audio) return ""; const n = audio.recorderNames || []; const who = n.length ? n.join(", ") : (audio.recording + (audio.recording === 1 ? " app" : " apps"))
        return (muted ? "Microphone muted · " : "Microphone in use · ") + who }
    Rectangle { visible: Config.barHoverPills; anchors.fill: parent; radius: height / 2; color: Config.fg(hh.hovered ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
    GlowIcon { anchors.centerIn: parent; size: Math.round(16 * Config.barIconScale); source: mic.muted ? "mic-off-symbolic" : "mic-on-symbolic"; hovered: hh.hovered
        color: mic.muted ? Config.attention : Config.fgSolid; active: false }
    // a live microphone gets the privacy dot, muted it does not
    Rectangle { visible: !mic.muted; x: parent.width - 9; y: 3; width: 7; height: 7; radius: 3.5; color: Config.attention; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.4) }
    HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: if (mic.audio) mic.audio.toggleMicMute() }
    Timer { id: tipDelay; interval: 600; running: hh.hovered }
    Rectangle { visible: hh.hovered && !tipDelay.running && mic.tip !== ""; anchors.top: parent.bottom; anchors.topMargin: 10; anchors.horizontalCenter: parent.horizontalCenter; z: 50
        width: tipText.implicitWidth + 18; height: 26; radius: 8; color: Config.popSurface; border.width: 1; border.color: Config.fg(0.14)
        Text { id: tipText; anchors.centerIn: parent; text: mic.tip; color: Config.ink; font.pixelSize: 12 } }
}
