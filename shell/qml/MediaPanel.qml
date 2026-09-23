// Now-playing panel: the content of the lobe that grows under the media widget. Native to the shell (no hosted applet):
// large cover whose colour hazes into the glass, title / artist / album, a seek line, transport, the player's own volume,
// and a switcher when more than one player is around. Data: the MediaIsland's MPRIS model.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami
import SircaShell

Item {
    id: panel
    property var mpris: null                     // Mpris.Mpris2Model (set by the bar's Loader; null while the source is unavailable)
    property bool open: false
    readonly property var player: mpris ? mpris.currentPlayer : null
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property real length: player ? Math.max(0, player.length) : 0
    readonly property int pad: 8
    implicitWidth: 400
    implicitHeight: col.implicitHeight + 2 * pad

    function fmt(us) {
        const s = Math.max(0, Math.floor(us / 1e6)), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60;
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(ss).padStart(2, "0");
    }
    Timer { interval: 500; repeat: true; running: panel.open && panel.playing; triggeredOnStart: true; onTriggered: if (panel.player) panel.player.updatePosition() }

    // ---- lyrics (opt-in: config `lyrics: true`; LRCLIB, cached per track). Looked up while the lobe is open, so a closed
    // lobe never causes a request. Synced lines follow the player's position; plain text scrolls by hand.
    Lyrics { id: lyrics; enabled: Config.get("lyrics", false) === true }
    readonly property string trackKey: player ? (player.track ?? "") + "|" + (player.artist ?? "") + "|" + (player.album ?? "") + "|" + Math.round(length / 1e6) : ""
    function lookupLyrics() { if (open && lyrics.enabled && player && (player.track ?? "") !== "") lyrics.lookup(player.track ?? "", player.artist ?? "", player.album ?? "", Math.round(length / 1e6)) }
    onTrackKeyChanged: lookupLyrics()
    onOpenChanged: lookupLyrics()
    Connections { target: lyrics; function onEnabledChanged() { panel.lookupLyrics() } }
    readonly property bool lyricsShown: lyrics.enabled && lyrics.status === "ready" && lyrics.lines.length > 0
    readonly property int lyricLine: lyrics.synced && player ? lyrics.lineAt(player.position / 1000) : -1

    // a thin glass slider: line, bright fill, a knob that shows up with the pointer
    component Line: Item {
        id: sl
        property real value: 0                   // 0..1
        property bool enabled_: true
        readonly property bool dragging: ma.pressed
        property real dragValue: 0
        signal moved(real v)                     // while dragging
        signal committed(real v)                 // on release
        implicitHeight: 18
        readonly property real shown: dragging ? dragValue : value
        Rectangle { id: track; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Config.fg(0.14) }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Math.max(height, track.width * sl.shown); height: 4; radius: 2; color: Config.fg(sl.enabled_ ? 0.92 : 0.4) }
        Rectangle { x: (track.width - width) * sl.shown; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: Config.fgSolid
            opacity: sl.enabled_ && (ma.containsMouse || ma.pressed) ? 1 : 0; scale: ma.pressed ? 1.15 : 1
            Behavior on opacity { NumberAnimation { duration: Config.quick } }
            Behavior on scale { NumberAnimation { duration: Config.quick } } }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: sl.enabled_
            function at(mx) { return Math.max(0, Math.min(1, mx / width)) }
            onPressed: e => { sl.dragValue = at(e.x); sl.moved(sl.dragValue) }
            onPositionChanged: e => { if (pressed) { sl.dragValue = at(e.x); sl.moved(sl.dragValue) } }
            onReleased: sl.committed(sl.dragValue)
            onWheel: w => { const v = Math.max(0, Math.min(1, sl.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))); sl.committed(v) } }
    }
    // round glyph button; `on` = a lit state (shuffle / repeat), `big` = the play button
    component Btn: Item {
        id: b
        property string icon
        property bool on: false
        property bool big: false
        property bool enabled_: true
        signal tapped()
        width: big ? 46 : 36; height: width
        opacity: enabled_ ? 1 : 0.3
        Rectangle { anchors.fill: parent; radius: width / 2
            color: Config.fg(bt.pressed ? 0.22 : (b.big ? (bh.hovered ? 0.18 : 0.12) : (bh.hovered ? 0.10 : 0)))
            border.width: b.big ? 1 : 0; border.color: Config.fg(0.16)
            Behavior on color { ColorAnimation { duration: Config.quick } } }
        Kirigami.Icon { anchors.centerIn: parent; width: b.big ? 22 : 17; height: width; source: b.icon; isMask: true; color: Config.fgSolid; roundToIconSize: false; opacity: b.on || b.big ? 1 : 0.78 }
        Rectangle { visible: b.on; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 5; width: 4; height: 4; radius: 2; color: Config.fgSolid }
        HoverHandler { id: bh }
        TapHandler { id: bt; enabled: b.enabled_; onTapped: b.tapped() }
    }

    // The cover's colour, caught in the glass behind everything. A blurred OPAQUE picture keeps hard edges (unlike a dock
    // icon, which has transparent margins), and a spot glow at a cover that sits in the corner looks lopsided once it is kept off the
    // edges. So the haze is an even wash of the cover's colours over the whole popup: stronger at the top, feathered on all sides.
    // The canvas reaches hazeUp further at the top: the wash used to be clipped along the bar's bottom edge (the lobe's
    // container starts there), which read as a hard line; the host lets the container run up into the bar by that much.
    // The wash itself is no bigger, the feather core below defines it.
    property real hazeUp: 0
    Item { id: haze
        readonly property real over: Config.lobePad
        readonly property real overTop: over + panel.hazeUp
        x: -over; y: -overTop; width: panel.width + 2 * over; height: panel.height + over + overTop
        opacity: Config.hazeStrength * 2.0; visible: art.status === Image.Ready
        // two masks, as two nested layers (an item's own layer.effect is ignored when it is used as a mask source):
        // outer = feathered core along the header row, inner = slight left-to-right fall-off
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: edgeFeather; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        Item { anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: hazeMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            // the cover stretched over the whole popup and blurred until only its colours are left: an even wash, not a spot
            MultiEffect { anchors.fill: parent; anchors.margins: -40
                source: art; blurEnabled: true; blur: 1.0; blurMax: 64; blurMultiplier: 3.0; autoPaddingEnabled: false; saturation: Config.dark ? 0.45 : 1.3; brightness: Config.dark ? 0 : 0.14 } }
    }
    // Outer mask: a feathered inset box. The haze dies away before it reaches the glass
    // rim on any side (it must not tint the border highlight) and before the line where the lobe meets the bar.
    Item { id: edgeFeather; x: haze.x; y: haze.y; width: haze.width; height: haze.height; visible: false; layer.enabled: true
        // A low, wide core along the header row (cover + title) and a very wide blur: the wash sits on and around the picture
        // and the title, has no outline, and is gone before it reaches the rim or the bar above.
        Rectangle { id: featherCore
            readonly property real rowY: haze.overTop + panel.pad + 54         // centre line of the cover
            x: 44; y: rowY - 30; width: parent.width - 120; height: 84; radius: 36; color: Config.fgSolid; visible: false; layer.enabled: true }
        MultiEffect { anchors.fill: featherCore; source: featherCore; blurEnabled: true; blur: 1.0; blurMax: 64; blurMultiplier: 1.2; autoPaddingEnabled: true } }
    Item { id: hazeMask; x: haze.x; y: haze.y; width: haze.width; height: haze.height; visible: false; layer.enabled: true
        Shape { anchors.fill: parent
            ShapePath { strokeWidth: 0; strokeColor: "transparent"
                fillGradient: LinearGradient { x1: 0; y1: 0; x2: hazeMask.width; y2: 0            // a little stronger at the cover's side
                    GradientStop { position: 0.0; color: Config.fgSolid }
                    GradientStop { position: 1.0; color: Config.fg(0.55) } }
                startX: 0; startY: 0
                PathLine { x: hazeMask.width; y: 0 } PathLine { x: hazeMask.width; y: hazeMask.height } PathLine { x: 0; y: hazeMask.height } PathLine { x: 0; y: 0 } } } }

    Column {
        id: col
        x: panel.pad; y: panel.pad; width: panel.width - 2 * panel.pad
        spacing: 14

        Row { width: parent.width; spacing: 14
            Item { id: coverBox; width: 108; height: 108
                Rectangle { id: artMask; anchors.fill: parent; radius: 16; visible: false; layer.enabled: true; layer.smooth: true }
                Image { id: art; anchors.fill: parent; source: panel.player ? (panel.player.artUrl ?? "") : ""; fillMode: Image.PreserveAspectCrop; visible: false; layer.enabled: true; asynchronous: true; sourceSize: Qt.size(324, 324); mipmap: true }
                MultiEffect { anchors.fill: parent; source: art; maskEnabled: true; maskSource: artMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; visible: art.status === Image.Ready }
                Rectangle { anchors.fill: parent; radius: 16; color: art.status === Image.Ready ? "transparent" : Config.fg(0.07); border.width: 1; border.color: Config.fg(0.14)
                    Kirigami.Icon { anchors.centerIn: parent; width: 40; height: 40; source: "emblem-music-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.6; visible: art.status !== Image.Ready; roundToIconSize: false } }
                TapHandler { onTapped: if (panel.player && panel.player.canRaise) panel.player.Raise() }
            }
            Column { width: parent.width - coverBox.width - 14; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                Row { spacing: 6; height: 18
                    Kirigami.Icon { width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter; source: panel.player ? (panel.player.iconName || "emblem-music-symbolic") : ""; roundToIconSize: false }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: panel.player ? (panel.player.identity ?? "") : ""; color: Config.inkDim; font.pixelSize: 11; font.weight: Font.Medium; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 } }
                Text { width: parent.width; text: panel.player ? (panel.player.track ?? "") : ""; color: Config.ink; font.pixelSize: 16; font.weight: Font.DemiBold; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; lineHeight: 1.08 }
                Text { width: parent.width; text: panel.player ? (panel.player.artist ?? "") : ""; visible: text !== ""; color: Config.inkDim; font.pixelSize: 13; elide: Text.ElideRight }
                Text { width: parent.width; text: panel.player ? (panel.player.album ?? "") : ""; visible: text !== ""; color: Config.inkDim; opacity: 0.7; font.pixelSize: 12; elide: Text.ElideRight }
            }
        }

        // seek
        Column { width: parent.width; spacing: 1
            Line { id: seek; width: parent.width
                enabled_: !!panel.player && panel.player.canSeek && panel.length > 0
                value: panel.length > 0 ? Math.max(0, Math.min(1, panel.player.position / panel.length)) : 0
                onCommitted: v => { if (panel.player) { panel.player.position = Math.round(v * panel.length); panel.player.updatePosition() } } }
            Item { width: parent.width; height: 14
                Text { anchors.left: parent.left; text: panel.fmt(seek.dragging ? seek.dragValue * panel.length : (panel.player ? panel.player.position : 0)); color: Config.inkDim; font.pixelSize: 11; font.features: { "tnum": 1 } }
                Text { anchors.right: parent.right; text: panel.length > 0 ? panel.fmt(panel.length) : "–:––"; color: Config.inkDim; font.pixelSize: 11; font.features: { "tnum": 1 } } }
        }

        // transport
        Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 10
            Btn { anchors.verticalCenter: parent.verticalCenter; icon: "media-playlist-shuffle-symbolic"
                enabled_: !!panel.player && panel.player.canControl && panel.player.shuffle !== Mpris.ShuffleStatus.Unknown
                on: !!panel.player && panel.player.shuffle === Mpris.ShuffleStatus.On
                onTapped: panel.player.shuffle = on ? Mpris.ShuffleStatus.Off : Mpris.ShuffleStatus.On }
            Btn { anchors.verticalCenter: parent.verticalCenter; icon: "media-skip-backward-symbolic"; enabled_: !!panel.player && panel.player.canGoPrevious; onTapped: panel.player.Previous() }
            Btn { big: true; icon: panel.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"; enabled_: !!panel.player && (panel.player.canPlay || panel.player.canPause); onTapped: panel.player.PlayPause() }
            Btn { anchors.verticalCenter: parent.verticalCenter; icon: "media-skip-forward-symbolic"; enabled_: !!panel.player && panel.player.canGoNext; onTapped: panel.player.Next() }
            Btn { anchors.verticalCenter: parent.verticalCenter
                readonly property int st: panel.player ? panel.player.loopStatus : Mpris.LoopStatus.Unknown
                icon: st === Mpris.LoopStatus.Track ? "media-playlist-repeat-song-symbolic" : "media-playlist-repeat-symbolic"
                enabled_: !!panel.player && panel.player.canControl && st !== Mpris.LoopStatus.Unknown
                on: st === Mpris.LoopStatus.Playlist || st === Mpris.LoopStatus.Track
                onTapped: panel.player.loopStatus = (st === Mpris.LoopStatus.None ? Mpris.LoopStatus.Playlist : st === Mpris.LoopStatus.Playlist ? Mpris.LoopStatus.Track : Mpris.LoopStatus.None) }
        }

        // the player's own volume
        Row { width: parent.width; spacing: 10; visible: !!panel.player && panel.player.canControl
            Kirigami.Icon { id: volIcon; width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter; isMask: true; color: Config.fgSolid; opacity: 0.8; roundToIconSize: false
                readonly property real v: panel.player ? panel.player.volume : 0
                source: v <= 0.001 ? "audio-volume-muted-symbolic" : v < 0.34 ? "audio-volume-low-symbolic" : v < 0.67 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic" }
            Line { id: vol; width: parent.width - volIcon.width - volText.width - 20; anchors.verticalCenter: parent.verticalCenter
                value: panel.player ? Math.max(0, Math.min(1, panel.player.volume)) : 0
                onMoved: v => { if (panel.player) panel.player.volume = v }
                onCommitted: v => { if (panel.player) panel.player.volume = v } }
            Text { id: volText; width: 30; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Config.inkDim; font.pixelSize: 11; font.features: { "tnum": 1 }
                text: Math.round((vol.dragging ? vol.dragValue : vol.value) * 100) + "%" }
        }

        // lyrics: five lines' worth, the current one bright and centred; a click on a synced line seeks there
        Item { width: parent.width; height: panel.lyricsShown ? 118 : (lyrics.enabled && lyrics.status === "loading" ? 18 : 0); visible: height > 0; clip: true
            Text { visible: lyrics.status === "loading"; anchors.horizontalCenter: parent.horizontalCenter; color: Config.inkDim; font.pixelSize: 11; text: "Looking up lyrics…" }
            Rectangle { anchors.fill: parent; radius: 12; color: Config.fg(0.045); visible: panel.lyricsShown }
            ListView { id: lyricList; anchors.fill: parent; anchors.margins: 6; visible: panel.lyricsShown; model: panel.lyricsShown ? lyrics.lines : []; clip: true; spacing: 0
                // synced: the list is driven, the current line held in the middle; plain: a free scroll
                interactive: !lyrics.synced
                currentIndex: lyrics.synced ? Math.max(0, panel.lyricLine) : -1
                highlightRangeMode: lyrics.synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
                preferredHighlightBegin: height / 2 - 11; preferredHighlightEnd: height / 2 + 11
                highlightMoveDuration: 260; highlightMoveVelocity: -1
                // the last lines can still reach the middle: room under them (synced only; plain text ends where it ends)
                footer: Item { width: 1; height: lyrics.synced ? lyricList.height / 2 : 0 } header: Item { width: 1; height: lyrics.synced ? lyricList.height / 2 - 11 : 0 }
                delegate: Item { id: ll; required property int index; required property var modelData; width: lyricList.width; height: Math.max(22, lt.implicitHeight + 4)
                    readonly property int dist: lyrics.synced ? Math.abs(index - panel.lyricLine) : 0
                    Text { id: lt; width: parent.width - 8; x: 4; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.Wrap; horizontalAlignment: lyrics.synced ? Text.AlignHCenter : Text.AlignLeft
                        text: ll.modelData.text === "" ? "♪" : ll.modelData.text; color: Config.ink; font.pixelSize: lyrics.synced && ll.dist === 0 ? 14 : 12.5; font.weight: lyrics.synced && ll.dist === 0 ? Font.DemiBold : Font.Normal
                        opacity: !lyrics.synced ? 0.85 : ll.dist === 0 ? 1 : ll.dist === 1 ? 0.55 : ll.dist === 2 ? 0.32 : 0.16
                        Behavior on opacity { NumberAnimation { duration: Config.normal } } }
                    TapHandler { enabled: lyrics.synced && ll.modelData.t >= 0 && !!panel.player && panel.player.canSeek; onTapped: { panel.player.position = ll.modelData.t * 1000; panel.player.updatePosition() } } } } }

        // other players (row 0 of the model is the "follow the active one" multiplexer)
        Flow { width: parent.width; spacing: 6; visible: players.count > 2
            Repeater { id: players; model: panel.mpris
                Item { id: chip
                    required property int index
                    required property var model
                    readonly property bool current: !!panel.mpris && panel.mpris.currentIndex === index
                    visible: index > 0
                    width: visible ? chipRow.implicitWidth + 18 : 0; height: 26
                    Rectangle { anchors.fill: parent; radius: 13; color: Config.fg(chip.current ? 0.16 : (chh.hovered ? 0.09 : 0.05)); border.width: 1; border.color: Config.fg(chip.current ? 0.2 : 0.08) }
                    Row { id: chipRow; anchors.centerIn: parent; spacing: 6
                        Kirigami.Icon { width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter; source: chip.model.iconName || "emblem-music-symbolic"; roundToIconSize: false }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: chip.model.identity ?? ""; color: Config.ink; font.pixelSize: 11; font.weight: Font.Medium } }
                    HoverHandler { id: chh }
                    TapHandler { onTapped: if (panel.mpris) panel.mpris.currentIndex = chip.index } }
            }
        }
    }
}
