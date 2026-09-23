// Screen recording: RecorderProcess drives gpu-screen-recorder (see src/recorderprocess.h for why not KWin's stream or
// KDE's recorder library). Started from the capture overlay's Record mode, stopped from the bar's recording pill,
// Meta+Shift+R, or the D-Bus slot. The bar reads `recording`, `finishing` (file being finished / converted) and `clock`.
import QtQuick
import SircaShell

QtObject {
    id: rec
    property bool recording: false
    property bool finishing: false                     // stopped, the file is still being written out
    property int seconds: 0
    property string file: ""
    readonly property string clock: Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")

    function start(x, y, w, h) {
        if (recording || finishing) return
        w = Math.floor(w / 2) * 2; h = Math.floor(h / 2) * 2                      // H.264 wants even sizes
        if (w < 16 || h < 16) return
        file = Screenshot.newVideoPath("mp4"); if (file === "") { Shell.notify("Recording failed", "Cannot create the Screencasts folder", ""); return }
        seconds = 0; recording = true; tick.restart()
        console.log("recording:", Math.round(x), Math.round(y), w, h, "->", file)
        helper.start(Math.round(x), Math.round(y), w, h, file, Config.recordSound)
    }
    function stop() { if (!recording) return; recording = false; finishing = true; tick.stop(); helper.stop() }
    function toggleOrAsk(ask) { if (recording) stop(); else if (!finishing) ask() }

    property var helper: RecorderProcess {
        onFinished: code => { const wasStopping = rec.finishing; rec.recording = false; rec.finishing = false; tick.stop()
            if (code !== 0) { Screenshot.discardIfEmpty(rec.file); Shell.notify("Recording failed", code === -2 ? "gpu-screen-recorder is not installed" : code === -3 ? "ffmpeg is not installed (the HDR recording is kept next to the file)" : "The recorder stopped with an error (code " + code + "); see the journal", ""); return }
            Shell.notify(wasStopping ? "Recording saved" : "Recording ended", rec.clock + "  ·  " + rec.file.substring(rec.file.lastIndexOf("/") + 1), "", rec.file) } }
    property var _tick: Timer { id: tick; interval: 1000; repeat: true; onTriggered: rec.seconds++ }
}
