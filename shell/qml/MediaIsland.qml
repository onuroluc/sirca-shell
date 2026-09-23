// Now playing, in the bar. No container at rest: a round cover wrapped by a thin progress ring, the title with the
// artist dimmed after it, and a small level meter. Static: hovering only lays a faint glass tile under it, clicking opens the
// now-playing lobe, which has the controls. Data: Plasma's MPRIS model.
import QtQuick
import QtQml
import QtQuick.Effects
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import SircaShell

Item {
    id: island
    signal clicked()                // the bar opens the now-playing lobe
    property bool lobeOpen: false
    property bool quiet: false      // a fullscreen window has focus: stop the perpetual animations, nobody can see them
    // The MPRIS side lives in MediaSource.qml and the level meter in LevelMeter.qml, each behind a Loader by URL: both use
    // PRIVATE Plasma modules (org.kde.plasma.private.mpris / .volume). Should one be missing or changed, only that file
    // fails to load: no now-playing element, or flat meter bars, instead of no bar at all.
    Loader { id: srcLoader; source: "MediaSource.qml"; onStatusChanged: if (status === Loader.Error) console.warn("bar: now playing unavailable (org.kde.plasma.private.mpris)") }
    readonly property var src: srcLoader.item
    readonly property var model: src ? src.model : null       // the Mpris2Model, for the media lobe
    readonly property var player: src ? src.player : null
    readonly property bool hasTrack: !!player && (player.track ?? "") !== ""
    property alias coverItem: disc                 // the bar builds its colour haze from the cover only
    readonly property string coverUrl: cover.status === Image.Ready ? String(cover.source) : ""
    readonly property bool playing: src ? src.playing : false
    readonly property bool hovered: hover.hovered
    readonly property real progress: (player && player.length > 0) ? Math.max(0, Math.min(1, player.position / player.length)) : 0
    readonly property string artist: player ? (player.artist ?? "") : ""

    Timer { interval: 1000; repeat: true; running: island.playing && island.visible && !island.quiet; onTriggered: if (island.player) island.player.updatePosition() }

    visible: opacity > 0.01
    property bool allowed: true                 // placed in the bar at all (layout) and not in edit mode
    opacity: hasTrack && allowed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Config.normal } }
    height: 29
    width: hasTrack ? row.implicitWidth + 18 : 0
    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }   // track changes only; nothing resizes on hover
    clip: true

    // hover pill: the very same one as the clock and the gear (27 px, fill only, no rim); a bit brighter while the lobe is open
    Rectangle { anchors.centerIn: parent; width: parent.width; height: 27; radius: 13.5
        color: Config.fg(island.lobeOpen ? 0.12 : (island.hovered ? 0.07 : 0))
        Behavior on color { ColorAnimation { duration: Config.quick } } }

    Row {
        id: row
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 9

        // cover in a progress ring
        Item { width: 25; height: 25; anchors.verticalCenter: parent.verticalCenter
            Shape {   // track + progress arc
                anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
                ShapePath { strokeColor: Config.fg(0.14); strokeWidth: 1.5; fillColor: "transparent"
                    PathAngleArc { centerX: 12.5; centerY: 12.5; radiusX: 11.5; radiusY: 11.5; startAngle: 0; sweepAngle: 360 } }
                ShapePath { strokeColor: Config.fg(island.playing ? 0.92 : 0.5); strokeWidth: 1.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 12.5; centerY: 12.5; radiusX: 11.5; radiusY: 11.5; startAngle: -90; sweepAngle: Math.max(0.01, 360 * island.progress) } }
            }
            Item { id: disc; anchors.centerIn: parent; width: 19; height: 19
                opacity: island.playing ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: Config.normal } }
                Rectangle { id: coverMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true; layer.smooth: true }
                Image { id: cover; anchors.fill: parent; source: island.player ? (island.player.artUrl ?? "") : ""; fillMode: Image.PreserveAspectCrop; visible: false; layer.enabled: true; asynchronous: true; sourceSize: Qt.size(76, 76); smooth: true; mipmap: true }
                MultiEffect { anchors.fill: parent; source: cover; maskEnabled: true; maskSource: coverMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; visible: cover.status === Image.Ready }
                Kirigami.Icon { anchors.centerIn: parent; width: 13; height: 13; source: "emblem-music-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.8; visible: cover.status !== Image.Ready; roundToIconSize: false }
            }
        }

        // title, then the artist dimmed; one line, fading out at the end instead of "…"
        Item { id: label; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(line.implicitWidth, 300); height: line.implicitHeight
            Text { id: line; textFormat: Text.StyledText; font.pixelSize: 13; font.weight: Font.Medium; color: Config.ink
                opacity: island.playing ? 1 : 0.88      // 0.7 on a see-through bar read as washed out
                Behavior on opacity { NumberAnimation { duration: Config.normal } }
                text: {
                    const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                    const t = island.player ? esc(island.player.track ?? "") : ""
                    return island.artist !== "" ? t + "<font color=\"" + Config.hex(Qt.rgba(Config.ink.r, Config.ink.g, Config.ink.b, 0.84)) + "\">&nbsp;&nbsp;" + esc(island.artist) + "</font>" : t
                }
                layer.enabled: line.implicitWidth > 300
                layer.effect: MultiEffect { maskEnabled: true; maskSource: fadeMask }
            }
            Rectangle { id: fadeMask; width: 300; height: line.implicitHeight; visible: false; layer.enabled: true
                gradient: Gradient { orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "white" } GradientStop { position: 0.86; color: "white" } GradientStop { position: 1.0; color: "transparent" } } }
            clip: true
        }

        // Level meter: four slim rounded bars driven by the REAL output level (PulseAudio/PipeWire peak of the default
        // sink, ~25 readings a second, only while something plays and the bar is not in quiet mode). One level, four bars:
        // each bar shows the level a few readings later than its left neighbour, so loud moments travel across as a small
        // wave. Rise at once, fall slowly, like a meter.
        // levelMeterStyle "spectrum": 32 bands from a PipeWire capture + FFT (MediaSpectrum.qml, C++ Spectrum) instead of the four bars
        readonly property bool spectrum: Config.get("levelMeterStyle", "bars") === "spectrum"
        Loader { id: spectrumLoader; active: row.spectrum && Config.levelMeter; visible: active && island.playing; anchors.verticalCenter: parent.verticalCenter; source: "MediaSpectrum.qml"
            onLoaded: item.live = Qt.binding(() => levels.live)
            onStatusChanged: if (status === Loader.Error) console.warn("bar: spectrum unavailable") }
        Row { id: levels; spacing: 2.5; anchors.verticalCenter: parent.verticalCenter; height: 14; visible: island.playing && !row.spectrum
            readonly property bool live: island.playing && island.visible && !island.quiet && Config.levelMeter
            readonly property var shown: meterLoader.item ? meterLoader.item.shown : [0, 0, 0, 0]
            Repeater { model: 4
                Rectangle { required property int index
                    readonly property real level: levels.shown[index] || 0
                    width: 2; radius: 1; anchors.verticalCenter: parent.verticalCenter
                    height: 3 + 11 * level
                    color: Config.fg(0.5 + 0.45 * level) } }      // no Behavior: easing a value that changes 25x a second repaints this wide surface at the full 240 Hz
        }
    }
    Loader { id: meterLoader; active: !row.spectrum; source: "LevelMeter.qml"; onLoaded: item.live = Qt.binding(() => levels.live)   // (outside the Row: a Loader in it would take a spacing slot)
        onStatusChanged: if (status === Loader.Error) console.warn("bar: level meter unavailable (org.kde.plasma.private.volume)") }
    HoverHandler { id: hover }
    TapHandler { onTapped: island.clicked() }
}
