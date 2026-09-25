// Quick settings' sound backend (PulseAudio / PipeWire through org.kde.plasma.private.volume, a PRIVATE Plasma module).
// Behind a Loader (by URL) in QuickSettings.qml: without it the volume slider is disabled and the Sound page lists nothing.
// The bar's microphone / privacy widgets load the same file (one PulseAudio context is shared inside the process).
import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.volume

QtObject {
    // PreferredDevice.sink / .source can stay null after login even though the device models are fine (the default
    // arrived before its object did; 2026-09-24: "the audio looks muted until I switch the output away and back", and the
    // microphone tile said unavailable). Fall back to the model row that says it is the default, re-checked on every model
    // change, and log once when the fallback carried the day so the journal shows it happened.
    property int _tick: 0
    function _defaultIn(model) { const r = model.KItemModels.KRoleNames.role("PulseObject"); for (let i = 0; i < model.rowCount(); ++i) { const o = model.data(model.index(i, 0), r); if (o && o.default) return o } return null }
    // (_tick comes in as an argument: a bare read in a binding is optimised away, see Config.load)
    function _pick(preferred, model, what, tick) { if (preferred) return preferred; const o = _defaultIn(model); if (o && !_told[what]) { _told[what] = true; console.log("sound: PreferredDevice." + what + " is null, using the model's default", o.name) } return o }
    property var _told: ({})
    readonly property var _watch: Connections { target: sinks; function onRowsInserted() { _tick++ } function onRowsRemoved() { _tick++ } function onModelReset() { _tick++ } function onDataChanged() { _tick++ } }
    readonly property var _watch2: Connections { target: sources; function onRowsInserted() { _tick++ } function onRowsRemoved() { _tick++ } function onModelReset() { _tick++ } function onDataChanged() { _tick++ } }
    readonly property var sink: _pick(PreferredDevice.sink, sinks, "sink", _tick)
    readonly property bool hasSink: sink && sink.name !== "auto_null"
    readonly property int pct: hasSink ? Math.round(sink.volume / PulseAudio.NormalVolume * 100) : 0
    readonly property bool muted: hasSink ? sink.muted : false
    // unmute: a slider dragged up from silence also unmutes (the main page); the Sound page's slider leaves mute alone
    function setPct(v, unmute) { if (!hasSink) return; sink.volume = Math.round(v) * PulseAudio.NormalVolume / 100; if (unmute && sink.muted && v > 0) sink.muted = false }
    function toggleMute() { if (hasSink) sink.muted = !sink.muted }
    readonly property var sinks: PulseObjectFilterModel { filterOutInactiveDevices: true; sourceModel: SinkModel {} }
    // the next output device becomes the default (headphones <-> speakers from the bar's volume widget); the name of the new one
    function nextSink() { const n = sinks.rowCount(); if (n < 2) return ""
        let cur = -1; for (let i = 0; i < n; ++i) { const o = sinks.data(sinks.index(i, 0), sinks.role("PulseObject")); if (o && o.default) { cur = i; break } }
        const o = sinks.data(sinks.index((cur + 1) % n, 0), sinks.role("PulseObject")); if (!o) return ""; o.default = true; return o.description || o.name || "" }
    readonly property var sources: PulseObjectFilterModel { filterOutInactiveDevices: true; sourceModel: SourceModel {} }
    // ---- microphone: the default source, and who is recording from it right now (source outputs = capture streams;
    // virtual ones are monitors and loopbacks, not apps listening)
    readonly property var source: _pick(PreferredDevice.source, sources, "source", _tick)
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
