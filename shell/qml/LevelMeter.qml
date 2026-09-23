// The bar's level meter source: the REAL output level (PulseAudio/PipeWire peak of the default sink, ~25 readings a
// second) turned into four bar heights. Behind a Loader (by URL) in MediaIsland.qml: org.kde.plasma.private.volume is a
// PRIVATE Plasma module; without it the bars simply stay flat.
import QtQuick
import org.kde.plasma.private.volume

QtObject {
    id: meter
    property bool live: false                       // bound by the island: something plays and the bar is not quiet
    property var history: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property var shown: [0, 0, 0, 0]                // one level, four bars: each shows the level a few readings later than its left neighbour
    onLiveChanged: if (!live) shown = [0, 0, 0, 0]
    readonly property var _monitor: VolumeMonitor { target: meter.live ? PreferredDevice.sink : null
        // Auto-ranging: the bars show the level RELATIVE to how loud it has been lately, not the absolute peak. An app with
        // its own volume turned down (measured: Spotify peaking at 0.013 of full scale) left the bars flat. `ref` follows
        // the loudest recent reading: up at once, down by half in about 8 s; below the floor it is silence, not music.
        property real ref: 0.05
        onVolumeChanged: { ref = Math.max(0.004, volume, ref * 0.9965)
            const rel = volume < 0.0006 ? 0 : volume / ref
            const h = meter.history.slice(1); h.push(Math.min(1, Math.pow(rel, 1.6))); meter.history = h;   // pow > 1: peaks near the recent maximum are the norm, spread them out
            const out = []; for (let i = 0; i < 4; ++i) { const v = h[h.length - 1 - i * 2]; out.push(v > meter.shown[i] ? v : Math.max(v, meter.shown[i] * 0.80)) }
            // a bar is 3..14 px tall: a change of less than a pixel is invisible, but assigning it would still repaint the
            // whole 5120-wide bar surface. Only whole-pixel changes go through (steady or quiet passages then cost nothing).
            let same = true; for (let i = 0; i < 4; ++i) if (Math.round(11 * out[i]) !== Math.round(11 * (meter.shown[i] || 0))) { same = false; break }
            if (!same) meter.shown = out } }
}
