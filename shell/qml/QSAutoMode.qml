// Follow the sun: with config `autoMode: "sun"` the desktop goes dark at sunset and light at sunrise. The schedule comes
// from KWin's night light when it is on (org.kde.KWin /org/kde/KWin/NightLight: `daylight` says which side we are on,
// `scheduledTransitionDateTime` when the next change begins; modes Automatic / Location / Times all work, Constant has no
// schedule), else from a sunrise / sunset computation for `sunLatitude` / `sunLongitude` in the config (KWin does not
// put its location on the bus). Without either the switch stays off with a note.
// Two instances exist: Main's (`driver: true`) does the switching, quick settings' only shows the row. A transition runs
// `glass-mode dark|light` (the whole desktop follows) or, without glass-desktop, flips the shell's own `mode` key.
import QtQuick
import SircaShell

QtObject {
    id: am
    property bool driver: false
    readonly property bool on: Config.get("autoMode", "") === "sun"
    function setOn(v) { if (v) Shell.saveConfigKey("autoMode", "sun"); else Shell.removeConfigKey("autoMode") }
    // ---- night light (KWin)
    property bool nlAvailable: false
    property bool nlEnabled: false
    property int nlMode: 0                         // 0 automatic, 1 location, 2 times, 3 constant
    property bool nlDaylight: true
    property double nlNext: 0                      // ms since the epoch, 0 = none
    readonly property bool useNightLight: nlAvailable && nlEnabled && nlMode !== 3 && nlNext > 0
    function readNightLight() {
        const get = k => Shell.dbusCall("org.kde.KWin", "/org/kde/KWin/NightLight", "org.freedesktop.DBus.Properties", "Get", ["org.kde.KWin.NightLight", k])
        const av = get("available"); nlAvailable = av === true
        if (!nlAvailable) return
        nlEnabled = get("enabled") === true; nlMode = Number(get("mode") || 0); nlDaylight = get("daylight") !== false; nlNext = Number(get("scheduledTransitionDateTime") || 0) * 1000 }
    readonly property var _nl: Connections { target: Shell
        function onDbusSignal(iface, member, args) {
            if (iface !== "org.freedesktop.DBus.Properties" || member !== "PropertiesChanged" || !args || args[0] !== "org.kde.KWin.NightLight") return
            // only the keys that came (the temperature ticks every few seconds through a transition: no re-read for that)
            const c = args[1] || {}
            if (c.available !== undefined) am.nlAvailable = c.available === true
            if (c.enabled !== undefined) am.nlEnabled = c.enabled === true
            if (c.mode !== undefined) am.nlMode = Number(c.mode)
            if (c.daylight !== undefined) am.nlDaylight = c.daylight !== false
            if (c.scheduledTransitionDateTime !== undefined) am.nlNext = Number(c.scheduledTransitionDateTime) * 1000
            am.reschedule() } }
    // ---- sunrise / sunset from a location (NOAA's simplified equation; fine to a couple of minutes, plenty for a theme)
    readonly property var lat: Config.get("sunLatitude", null)
    readonly property var lon: Config.get("sunLongitude", null)
    readonly property bool hasLocation: lat !== null && lon !== null && isFinite(Number(lat)) && isFinite(Number(lon))
    function sunTimes(day) {                        // { rise, set } as Dates for the local calendar day of `day`, null in polar night / day
        const rad = Math.PI / 180, la = Number(lat), lo = Number(lon)
        const noon = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 12)
        const J = Math.round(noon.getTime() / 86400000 + 2440587.5)
        const n = J - 2451545.0 + 0.0008, Js = n - lo / 360
        const M = ((357.5291 + 0.98560028 * Js) % 360 + 360) % 360
        const C = 1.9148 * Math.sin(M * rad) + 0.02 * Math.sin(2 * M * rad) + 0.0003 * Math.sin(3 * M * rad)
        const L = ((M + C + 180 + 102.9372) % 360 + 360) % 360
        const Jt = 2451545.0 + Js + 0.0053 * Math.sin(M * rad) - 0.0069 * Math.sin(2 * L * rad)
        const dec = Math.asin(Math.sin(L * rad) * Math.sin(23.4397 * rad))
        const cw = (Math.sin(-0.833 * rad) - Math.sin(la * rad) * Math.sin(dec)) / (Math.cos(la * rad) * Math.cos(dec))
        if (cw < -1 || cw > 1) return null
        const w = Math.acos(cw) / rad, toDate = j => new Date((j - 2440587.5) * 86400000)
        return { rise: toDate(Jt - w / 360), set: toDate(Jt + w / 360) } }
    // ---- the verdict
    readonly property bool canSchedule: useNightLight || hasLocation
    property bool wantDark: true
    property double nextChange: 0                  // ms since the epoch
    function compute() {
        const now = new Date()
        if (useNightLight) { wantDark = !nlDaylight; nextChange = nlNext; return }
        if (!hasLocation) { nextChange = 0; return }
        const t = sunTimes(now)
        if (!t) { wantDark = Number(lat) * (now.getMonth() >= 3 && now.getMonth() <= 8 ? 1 : -1) < 0; nextChange = 0; return }   // polar: summer = day, winter = night
        if (now < t.rise) { wantDark = true; nextChange = t.rise.getTime() }
        else if (now < t.set) { wantDark = false; nextChange = t.set.getTime() }
        else { wantDark = true; const tm = sunTimes(new Date(now.getTime() + 86400000)); nextChange = tm ? tm.rise.getTime() : 0 } }
    readonly property string nextText: { if (!canSchedule) return "Needs Night Light on, or sunLatitude / sunLongitude in the config"
        if (nextChange <= 0) return wantDark ? "Dark" : "Light"
        const d = new Date(nextChange), today = d.toDateString() === new Date().toDateString()
        return (wantDark ? "Light at " : "Dark at ") + (today ? "" : "tomorrow ") + Qt.formatTime(d, "hh:mm") }
    function apply() {
        if (!driver || !on || !canSchedule) return
        const want = wantDark ? "dark" : "light"
        if (Config.mode === want) return
        console.log("sirca-shell: follow the sun:", want, "(next change", nextChange > 0 ? new Date(nextChange).toString() : "none", ")")
        Shell.saveConfigKey("mode", want)
        if (Shell.hasProgram("glass-mode")) Shell.runDetached("glass-mode", [want]) }
    readonly property var tick: Timer { repeat: false; onTriggered: am.reschedule() }
    function reschedule() {
        compute(); apply()
        // wake a second after the change; never sleep more than six hours (a night light schedule can move under us). A
        // change that is already past (KWin has not moved its schedule on yet) is looked at again in a minute, not every second
        const wait = nextChange <= 0 ? 6 * 3600000 : nextChange < Date.now() - 500 ? 60000 : nextChange - Date.now() + 1000
        tick.interval = Math.max(1000, Math.min(6 * 3600000, wait)); tick.restart() }
    onOnChanged: reschedule()
    onLatChanged: reschedule()
    onLonChanged: reschedule()
    Component.onCompleted: {
        Shell.dbusListen("org.kde.KWin", "/org/kde/KWin/NightLight", "org.freedesktop.DBus.Properties", "PropertiesChanged")
        readNightLight(); reschedule() }
}
