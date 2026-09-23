// System monitor: the lobe under the bar's CPU / memory widget. Per-core CPU bars, memory and swap, GPU load and
// temperature (NVIDIA through nvidia-smi, AMD through sysfs, Intel says n/a), network up / down, and the five busiest
// processes with an End button each (SIGTERM). Every reading comes from the SysStats C++ type (src/sysmon.cpp), which polls only while
// `open` is true, so a closed lobe costs nothing.
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell

Item {
    id: panel
    property bool open: false
    readonly property int pad: 10
    implicitWidth: 440
    implicitHeight: col.implicitHeight + 2 * pad
    SysStats { id: mon; active: panel.open; interval: 2000 }
    function pct(v) { return Math.round(100 * Math.max(0, Math.min(1, v))) + "%" }
    function rate(bps) { return bps < 1000 ? Math.round(bps) + " B/s" : bps < 1e6 ? (bps / 1e3).toFixed(bps < 1e4 ? 1 : 0) + " KB/s" : (bps / 1e6).toFixed(1) + " MB/s" }

    component Label: Text { color: Config.inkDim; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
    component Value: Text { color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 } }
    // a thin horizontal meter; the fill turns to the attention colour past 90 % so a full disk or RAM is seen at a glance
    component Meter: Item { id: m; property real value: 0; property bool hot: value > 0.9; implicitHeight: 6; width: parent.width
        Rectangle { anchors.fill: parent; radius: 3; color: Config.fg(0.12) }
        Rectangle { width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, m.value))); height: parent.height; radius: 3; color: m.hot ? Config.attention : Config.fg(0.88)
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } } }
    component Head: Item { id: hd; property string label; property string note; property string value; width: parent.width; height: 18
        Label { id: hl; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: hd.label }
        Text { anchors.left: hl.right; anchors.leftMargin: 8; anchors.right: hv.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: hd.note; visible: text !== ""; color: Config.inkDim; font.pixelSize: 11; elide: Text.ElideRight }
        Value { id: hv; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: hd.value } }

    Column { id: col; x: panel.pad; y: panel.pad; width: parent.width - 2 * panel.pad; spacing: 10
        Item { width: parent.width; height: 24
            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "System"; color: Config.ink; font.pixelSize: 16; font.weight: Font.DemiBold }
            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 90; horizontalAlignment: Text.AlignRight
                text: mon.cpuName; color: Config.inkDim; font.pixelSize: 11; elide: Text.ElideRight } }
        // ---- CPU: one bar per core
        Column { width: parent.width; spacing: 6
            Head { label: "CPU"; value: panel.pct(mon.cpu) + "  ·  " + mon.coreCount + " threads" }
            Row { id: coreRow; width: parent.width; spacing: 3; readonly property int n: Math.max(1, mon.cores.length); readonly property real barW: (width - spacing * (n - 1)) / n
                Repeater { model: mon.cores
                    Item { required property var modelData; width: coreRow.barW; height: 40
                        Rectangle { anchors.fill: parent; radius: 3; color: Config.fg(0.08) }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; radius: 3; height: Math.max(3, parent.height * Math.max(0, Math.min(1, modelData)))
                            color: modelData > 0.9 ? Config.attention : Config.fg(0.55 + 0.4 * modelData); Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } } } } } }
        // ---- memory, swap only when there is any
        Column { width: parent.width; spacing: 6
            Head { label: "Memory"; value: mon.memTotal > 0 ? mon.human(mon.memUsed) + " of " + mon.human(mon.memTotal, 0) : "—" }
            Meter { value: mon.memTotal > 0 ? mon.memUsed / mon.memTotal : 0 } }
        Column { width: parent.width; spacing: 6; visible: mon.swapTotal > 0
            Head { label: "Swap"; value: mon.human(mon.swapUsed) + " of " + mon.human(mon.swapTotal, 0) }
            Meter { value: mon.swapTotal > 0 ? mon.swapUsed / mon.swapTotal : 0 } }
        // ---- GPU
        Column { width: parent.width; spacing: 6
            readonly property var g: mon.gpu
            readonly property bool ok: !!g && g.available === true
            Head { label: "GPU"; note: parent.g && parent.g.name ? parent.g.name : ""
                value: parent.ok ? panel.pct(parent.g.load) + (parent.g.temp > 0 ? "  ·  " + parent.g.temp + " °C" : "") + (parent.g.memTotal > 0 ? "  ·  " + mon.human(parent.g.memUsed) + " of " + mon.human(parent.g.memTotal, 0) : "")
                                 : (mon.gpu.vendor === "intel" ? "n/a (Intel)" : mon.gpu.vendor === "" ? "n/a" : "reading…") }
            Meter { value: parent.ok ? parent.g.load : 0; hot: parent.ok && parent.g.temp >= 85 } }
        // ---- network
        Head { label: "Network"; value: "↓ " + panel.rate(mon.netDown) + "    ↑ " + panel.rate(mon.netUp) }
        Rectangle { width: parent.width; height: 1; color: Config.fg(0.08) }
        // ---- processes
        Column { width: parent.width; spacing: 2
            Item { width: parent.width; height: 18
                Label { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Busiest processes" }
                Label { anchors.right: parent.right; anchors.rightMargin: 70; anchors.verticalCenter: parent.verticalCenter; text: "CPU" } }
            Repeater { model: mon.procs
                Item { id: prow; required property var modelData; width: parent.width; height: 30
                    Rectangle { anchors.fill: parent; radius: 9; color: Config.fg(ph.hovered ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
                    Text { anchors.left: parent.left; anchors.leftMargin: 8; anchors.right: cpuT.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: prow.modelData.name; color: Config.ink; font.pixelSize: 13; elide: Text.ElideRight; textFormat: Text.PlainText }
                    Value { id: cpuT; anchors.right: memT.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; width: 52; horizontalAlignment: Text.AlignRight; text: prow.modelData.cpu.toFixed(prow.modelData.cpu < 10 ? 1 : 0) + "%" }
                    Value { id: memT; anchors.right: endBtn.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; width: 66; horizontalAlignment: Text.AlignRight; text: mon.human(prow.modelData.mem, 0); color: Config.inkDim }
                    // End: SIGTERM, shown only while the row is hovered so a glance at the list cannot hit it
                    Rectangle { id: endBtn; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; width: 40; height: 22; radius: 11
                        opacity: ph.hovered ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Config.quick } }
                        color: eh.hovered ? Qt.rgba(229/255, 72/255, 77/255, 0.85) : Config.fg(0.12); border.width: 1; border.color: Config.fg(0.14)
                        Text { anchors.centerIn: parent; text: "End"; color: eh.hovered ? "white" : Config.ink; font.pixelSize: 11; font.weight: Font.Medium }   // literal-ok: white on the red hover fill
                        HoverHandler { id: eh } TapHandler { onTapped: mon.endProcess(prow.modelData.pid) } }
                    HoverHandler { id: ph } } }
            Text { visible: mon.procs.length === 0; x: 8; height: 30; verticalAlignment: Text.AlignVCenter; text: "Measuring…"; color: Config.inkDim; font.pixelSize: 12 } }
    }
}
