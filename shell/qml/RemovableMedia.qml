// The "disks" lobe: removable drives (USB sticks, cards, external discs) from UDisks2 through RemovableModel, one row each
// with Open (mounts first when it has to, then the file manager) and Eject (unmounts, then ejects or powers the drive off;
// a drive that cannot be ejected gets Unmount instead). Lobe-sized, like the calendar: the bar hangs it under its widget.
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell

Item {
    id: panel
    property bool open: false
    readonly property int count: devices.count
    implicitWidth: 340
    implicitHeight: col.implicitHeight + 12
    RemovableModel { id: devices
        onMounted: (label, mountPoint) => { if (panel.wantOpen === mountPoint || panel.wantOpen === "*") { panel.wantOpen = ""; Shell.runDetached("xdg-open", [mountPoint]) } } }
    property string wantOpen: ""                         // "*" while an Open waits for its mount
    function fmtSize(b) { const u = ["B", "kB", "MB", "GB", "TB"]; let v = b, i = 0; while (v >= 1000 && i < 4) { v /= 1000; ++i } return (v < 10 && i > 0 ? v.toFixed(1) : Math.round(v)) + " " + u[i] }
    function openRow(row, mounted, mountPoint) { if (mounted) Shell.runDetached("xdg-open", [mountPoint]); else { wantOpen = "*"; devices.mount(row) } }

    component Pill: Item { id: pb; property string label; property string icon; property bool enabled_: true; signal tapped()
        width: pl.implicitWidth + 24 + (icon !== "" ? 18 : 0); height: 26; opacity: enabled_ ? 1 : 0.4
        Rectangle { anchors.fill: parent; radius: 13; color: Config.fg(pt.pressed ? 0.20 : (ph.hovered ? 0.12 : 0.055)); border.width: 1; border.color: Config.fg(ph.hovered ? 0.18 : 0.09)
            Behavior on color { ColorAnimation { duration: Config.quick } } }
        Row { anchors.centerIn: parent; spacing: 5
            Kirigami.Icon { visible: pb.icon !== ""; width: 13; height: 13; anchors.verticalCenter: parent.verticalCenter; source: pb.icon; isMask: true; color: Config.fgSolid; roundToIconSize: false }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pb.label; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium } }
        HoverHandler { id: ph; cursorShape: pb.enabled_ ? Qt.PointingHandCursor : Qt.ArrowCursor } TapHandler { id: pt; enabled: pb.enabled_; onTapped: pb.tapped() } }

    Column { id: col; x: 6; y: 6; width: parent.width - 12; spacing: 4
        Item { width: parent.width; height: 28
            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; color: Config.ink; font.pixelSize: 15; font.weight: Font.DemiBold; text: "Removable drives" }
            Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; color: Config.inkDim; font.pixelSize: 12
                text: !devices.available ? "UDisks2 not running" : devices.count === 0 ? "none plugged in" : "" } }
        Repeater { model: devices
            Item { id: row; required property int index; required property var model
                width: parent.width; height: 56
                Rectangle { anchors.fill: parent; radius: 12; color: Config.fg(rh.hovered ? 0.07 : 0.035); border.width: 1; border.color: Config.fg(0.06)
                    Behavior on color { ColorAnimation { duration: Config.quick } } }
                Kirigami.Icon { id: ic; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; source: row.model.icon; roundToIconSize: false; opacity: row.model.busy ? 0.5 : 1 }
                Column { anchors.left: ic.right; anchors.leftMargin: 10; anchors.right: btns.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    Text { width: parent.width; elide: Text.ElideRight; color: Config.ink; font.pixelSize: 13; font.weight: Font.Medium; text: row.model.label }
                    Text { width: parent.width; elide: Text.ElideMiddle; color: Config.inkDim; font.pixelSize: 11; font.features: { "tnum": 1 }
                        text: (row.model.busy ? "working…" : row.model.mounted ? row.model.mountPoint : "not mounted") + "  ·  " + panel.fmtSize(row.model.size) + "  ·  " + row.model.device.replace(/^\/dev\//, "") } }
                // a dot for "mounted" (data may be open somewhere: eject flushes it first)
                Rectangle { x: ic.x + ic.width - 6; y: ic.y + 2; width: 8; height: 8; radius: 4; visible: row.model.mounted; color: Config.onFill; border.width: 1; border.color: Config.fg(0.3) }
                Row { id: btns; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Pill { label: "Open"; icon: "folder-open-symbolic"; enabled_: !row.model.busy; onTapped: panel.openRow(row.index, row.model.mounted, row.model.mountPoint) }
                    Pill { label: row.model.ejectable ? "Eject" : "Unmount"; icon: "media-eject-symbolic"; enabled_: !row.model.busy && (row.model.ejectable || row.model.mounted)
                        onTapped: row.model.ejectable ? devices.eject(row.index) : devices.unmount(row.index) } }
                HoverHandler { id: rh } } }
        Text { visible: devices.lastError !== ""; x: 8; width: parent.width - 16; wrapMode: Text.Wrap; color: Config.attention; font.pixelSize: 11; text: devices.lastError }
    }
}
