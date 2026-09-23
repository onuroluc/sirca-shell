// Caffeine: keep the screen and the machine awake. On = one inhibit cookie each on org.freedesktop.ScreenSaver (KWin:
// no lock, no screen off) and org.freedesktop.PowerManagement.Inhibit (PowerDevil: no sleep), held by an IdleInhibitor
// (src/powerinfo.cpp); off = both released. The holds live in this object, so the state lasts as long as the shell runs.
// `caffeineAuto` (config, default false) holds a SECOND pair while `busy` is true (a full-screen window or a game has
// focus, bound from the bar), released the moment focus moves on; the manual pair is untouched by it.
import QtQuick
import SircaShell

QtObject {
    id: caf
    property bool busy: false                                  // bound by the bar: bar.busy
    readonly property bool auto_: Config.get("caffeineAuto", false) === true
    property bool on: false                                    // the manual switch
    readonly property bool autoOn: auto_ && busy
    readonly property bool active: on || autoOn
    readonly property string status: on ? "On" : autoOn ? "While full-screen" : (auto_ ? "Auto" : "Off")
    readonly property var manual: IdleInhibitor { reason: "Caffeine: kept awake from the bar"; inhibited: caf.on }
    readonly property var automatic: IdleInhibitor { reason: "Caffeine: a full-screen window has focus"; inhibited: caf.autoOn }
    function toggle() { on = !on }
}
