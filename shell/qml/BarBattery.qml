// Battery for the bar: glyph + percent, a small bolt state while charging; takes no room on a machine without a battery.
// UPower's composite DisplayDevice over the system bus (BatteryInfo, src/powerinfo.cpp). A tap opens quick settings,
// where the power-profile tile has the time left.
import QtQuick
import SircaShell
import "Glass"

Item {
    id: bat
    property bool allowed: true
    signal clicked()
    BatteryInfo { id: info }
    readonly property bool shown: allowed && info.present
    readonly property int percent: info.percent
    readonly property bool charging: info.charging
    visible: shown
    width: shown ? row.implicitWidth + 16 : 0; height: 27
    // Breeze has battery-000 … battery-100 in tens, each with a -charging twin; UPower's own name (battery-level-…) is GNOME's set
    readonly property string icon: { const p = Math.max(0, Math.min(100, Math.round(info.percent / 10) * 10)); return "battery-" + ("00" + p).slice(-3) + (info.charging ? "-charging" : "") + "-symbolic" }
    readonly property bool low: !info.charging && info.percent <= 15
    function spell(sec) { if (sec <= 0) return ""; const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60); return h > 0 ? h + " h " + (m > 0 ? m + " min" : "") : m + " min" }
    readonly property string tip: { if (!info.present) return ""
        if (info.full) return "Charged"
        const t = info.charging ? spell(info.timeToFull) : spell(info.timeToEmpty)
        return info.charging ? ("Charging" + (t !== "" ? " · " + t + " until full" : "")) : (t !== "" ? t + " left" : "On battery") }
    Rectangle { visible: Config.barHoverPills; anchors.fill: parent; radius: height / 2; color: Config.fg(hh.hovered ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
    Row { id: row; anchors.centerIn: parent; spacing: 5
        GlowIcon { anchors.verticalCenter: parent.verticalCenter; size: Math.round(16 * Config.barIconScale); source: bat.icon; hovered: hh.hovered
            color: bat.low ? Config.attention : Config.fgSolid }     // (attention orange reads on both glasses)
        Text { anchors.verticalCenter: parent.verticalCenter; text: info.percent + "%"; color: bat.low ? Config.attention : Config.ink; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 } } }
    HoverHandler { id: hh }
    TapHandler { onTapped: bat.clicked() }
    // the time left, as a tip under the bar after a short rest (same look as the tray's)
    Timer { id: tipDelay; interval: 600; running: hh.hovered }
    Rectangle { visible: hh.hovered && !tipDelay.running && bat.tip !== ""; anchors.top: parent.bottom; anchors.topMargin: 10; anchors.horizontalCenter: parent.horizontalCenter; z: 50
        width: tipText.implicitWidth + 18; height: 26; radius: 8; color: Config.popSurface; border.width: 1; border.color: Config.fg(0.14)
        Text { id: tipText; anchors.centerIn: parent; text: bat.tip; color: Config.ink; font.pixelSize: 12 } }
}
