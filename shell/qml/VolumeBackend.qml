// Quick settings' sound backend (PulseAudio / PipeWire through org.kde.plasma.private.volume, a PRIVATE Plasma module).
// Behind a Loader (by URL) in QuickSettings.qml: without it the volume slider is disabled and the Sound page lists nothing.
// The bar's microphone / privacy widgets load the same file (one PulseAudio context is shared inside the process).
import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.volume

QtObject {
    readonly property var sink: PreferredDevice.sink
    readonly property bool hasSink: sink && sink.name !== "auto_null"
    readonly property int pct: hasSink ? Math.round(sink.volume / PulseAudio.NormalVolume * 100) : 0
    readonly property bool muted: hasSink ? sink.muted : false
    // unmute: a slider dragged up from silence also unmutes (the main page); the Sound page's slider leaves mute alone
    function setPct(v, unmute) { if (!hasSink) return; sink.volume = Math.round(v) * PulseAudio.NormalVolume / 100; if (unmute && sink.muted && v > 0) sink.muted = false }
    function toggleMute() { if (hasSink) sink.muted = !sink.muted }
    readonly property var sinks: PulseObjectFilterModel { filterOutInactiveDevices: true; sourceModel: SinkModel {} }
    readonly property var sources: PulseObjectFilterModel { filterOutInactiveDevices: true; sourceModel: SourceModel {} }
    // ---- microphone: the default source, and who is recording from it right now (source outputs = capture streams;
    // virtual ones are monitors and loopbacks, not apps listening)
    readonly property var source: PreferredDevice.source
    readonly property bool hasSource: source && source.name !== "auto_null"
    readonly property bool micMuted: hasSource ? source.muted : false
    readonly property string sourceName: hasSource ? String(source.description || source.name || "") : ""
    function toggleMicMute() { if (hasSource) source.muted = !source.muted }
    readonly property var recorders: PulseObjectFilterModel { filters: [{ role: "VirtualStream", value: false }]; sourceModel: SourceOutputModel {} }
    readonly property int recording: recorders.count
    // the recording apps' names (for the widget's tip): the stream's client, else the stream's own name
    property var recorderNames: []
    readonly property var _rec: Connections { target: recorders
        function update() { const r = recorders.KItemModels.KRoleNames.role("PulseObject"), out = []
            for (let i = 0; i < recorders.rowCount(); ++i) { const o = recorders.data(recorders.index(i, 0), r); const n = o ? String((o.client && o.client.name) || o.name || "") : ""; if (n !== "" && out.indexOf(n) < 0) out.push(n) }
            recorderNames = out }
        function onRowsInserted() { update() } function onRowsRemoved() { update() } function onModelReset() { update() } function onDataChanged() { update() }
        Component.onCompleted: update() }
}
