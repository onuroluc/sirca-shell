// The now-playing source for the bar's island and the media lobe: Plasma's MPRIS model, and which of its players counts.
// Behind a Loader (by URL) in MediaIsland.qml: org.kde.plasma.private.mpris is a PRIVATE Plasma module, so if it is
// missing or has changed only this file fails and the bar simply has no now-playing element.
import QtQuick
import QtQml
import org.kde.plasma.private.mpris as Mpris

QtObject {
    id: src
    readonly property var model: mpris
    // Which source: the one that is PLAYING. Plasma's model keeps pointing at the source it chose last (a paused browser tab)
    // while another app plays, so every source is watched here: a playing one wins (the model's own choice first, if that is
    // playing), and with nothing playing it is the model's choice as before.
    property var sources: []
    readonly property var _watch: Instantiator { model: mpris
        delegate: QtObject { required property var container }
        onObjectAdded: (i, o) => { const l = src.sources.slice(); l.push(o); src.sources = l }
        onObjectRemoved: (i, o) => { src.sources = src.sources.filter(x => x !== o) } }
    readonly property var player: { const cur = mpris.currentPlayer
        if (cur && cur.playbackStatus === Mpris.PlaybackStatus.Playing) return cur
        for (let i = 0; i < sources.length; ++i) { const c = sources[i].container; if (c && c.playbackStatus === Mpris.PlaybackStatus.Playing) return c }
        return cur }
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property var _model: Mpris.Mpris2Model { id: mpris }
}
