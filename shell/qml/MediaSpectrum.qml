// The level meter as a spectrum: 32 slim bars, low to high, driven by Spectrum (a PipeWire capture of the default sink's
// monitor + a small FFT in C++). Behind a Loader in MediaIsland (config levelMeterStyle: "spectrum"); `live` is bound by
// the island like the peak meter's. Heights are whole pixels already (the C++ side quantises), so a steady passage costs
// no repaints of the wide bar surface.
import QtQuick
import SircaShell

Row {
    id: spec
    property bool live: false
    spacing: 1
    height: 14
    readonly property var bands: source.bands
    Spectrum { id: source; active: spec.live && available }
    Repeater { model: 32
        Rectangle { required property int index
            readonly property real level: spec.bands[index] || 0
            width: 2; radius: 1; anchors.verticalCenter: parent.verticalCenter
            height: 3 + Math.round(11 * level)
            color: Config.fg(0.5 + 0.45 * level) } }   // no Behavior: 25 updates a second on the bar surface, like the meter
}
