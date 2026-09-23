// The dock's per-app audio: the previewed app's playback streams (PipeWire / PulseAudio "sink inputs"), matched to the
// hovered task by process id, else by the binary name against the app id. Lives behind a Loader in Dock.qml because
// org.kde.plasma.private.volume is a PRIVATE Plasma module: when it is missing or changes shape only this file fails to
// load, and the dock carries on without its volume row.
import QtQuick
import org.kde.taskmanager as TaskManager
import org.kde.plasma.private.volume
import org.kde.kitemmodels as KItemModels

QtObject {
    id: audio
    property var dock: null                       // set by the Loader (onLoaded); read for previewShown / previewIndex / lobeMode / tasksModel
    readonly property var streamModel: SinkInputModel {}
    property var streams: []                      // [{ obj, name }] for the previewed task; obj is the PulseAudioQt stream (volume / muted writable)
    readonly property bool hasAudio: streams.length > 0
    property int rev: 0                           // bumped on stream changes: the row's bindings re-read volume / muted
    function volumePct() { const o = streams.length ? streams[0].obj : null; return o ? Math.round(o.volume / PulseAudio.NormalVolume * 100) : 0 }
    function muted() { const o = streams.length ? streams[0].obj : null; return o ? o.muted : false }
    function setMuted(mu) { for (const st of streams) st.obj.muted = mu; rev++ }
    // every stream of the app moves together: one slider. unmute: a slider dragged up from silence also unmutes
    function setVolumePct(v, unmute) { const vol = Math.round(v) * PulseAudio.NormalVolume / 100; for (const st of streams) { st.obj.volume = vol; if (unmute && st.obj.muted && v > 0) st.obj.muted = false } rev++ }
    function refresh() {
        const d = dock; if (!d) return
        if (!d.previewShown || d.previewIndex < 0 || d.lobeMode !== "windows") { if (streams.length) streams = []; return }
        const m = d.tasksModel, R_ = TaskManager.AbstractTasksModel; if (!m) return; const idx = m.makeModelIndex(d.previewIndex)
        const pids = [], one = i => { const p = m.data(i, R_.AppPid); if (p > 0) pids.push(p) }
        if (m.data(idx, R_.IsGroupParent)) { const n = m.rowCount(idx); for (let c = 0; c < n; ++c) one(m.makeModelIndex(d.previewIndex, c)) } else one(idx)
        const appId = String(m.data(idx, R_.AppId) || "").replace(/\.desktop$/, "").toLowerCase(); const base = appId.split(".").pop()
        const sm = streamModel, roleObj = sm.KItemModels.KRoleNames.role("PulseObject"), roleName = sm.KItemModels.KRoleNames.role("Name"), roleVirt = sm.KItemModels.KRoleNames.role("VirtualStream")
        const out = []
        for (let r = 0; r < sm.rowCount(); ++r) { const mi = sm.index(r, 0); if (sm.data(mi, roleVirt)) continue
            const obj = sm.data(mi, roleObj); if (!obj || !obj.client) continue
            const props = obj.client.properties || {}; const spid = parseInt(props["application.process.id"] || "0"); const bin = String(props["application.process.binary"] || obj.client.name || "").toLowerCase()
            if ((spid > 0 && pids.indexOf(spid) >= 0) || (base.length > 2 && bin.indexOf(base) >= 0)) out.push({ obj: obj, name: sm.data(mi, roleName) || "" }) }
        streams = out; rev++
    }
    readonly property Connections _model: Connections { target: audio.streamModel; function onRowsInserted() { audio.refresh() } function onRowsRemoved() { audio.refresh() } function onDataChanged() { audio.rev++ } }
}
