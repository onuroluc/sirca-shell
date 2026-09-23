// The launcher: native, no Plasma applet. Search field, pinned apps, category chips, every app in a grid, and a footer
// with the user and the session actions. Apps come from AppsModel (KService). Pinned apps are the config key
// "favorites" (storage ids); right-click an app to pin or unpin it.
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import SircaShell
import "Glass"
import "control" as Control

Item {
    id: root
    property bool open: false
    signal done()                                   // something was launched or an action ran: the dock closes the panel
    implicitWidth: 684; implicitHeight: 600
    readonly property int cellW: 110
    readonly property int cellH: 98
    readonly property var favorites: Config.favorites
    readonly property bool browsing: field.text === "" && apps.category === ""

    AppsModel { id: apps; filter: field.text }
    onOpenChanged: if (open) { field.text = ""; apps.category = ""; grid.currentIndex = 0; grid.positionViewAtBeginning(); field.forceActiveFocus(); grid.activeNav = false }
    function launch(id) { if (id !== "" && apps.launch(id)) root.done() }
    function togglePin(id) {
        const f = root.favorites.slice(); const i = f.indexOf(id);
        if (i >= 0) f.splice(i, 1); else f.push(id);
        Shell.saveConfigKey("favorites", f);
    }

    component AppCell: Item { id: cell
        property string name; property string icon; property string storageId; property bool current: false; property bool pinned: false
        signal picked(); signal pinToggled()
        width: root.cellW; height: root.cellH
        Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 14
            color: Config.fg(cell.current ? 0.13 : (ch.hovered ? 0.07 : 0)); border.width: 1; border.color: Config.fg(cell.current ? 0.16 : 0)
            Behavior on color { ColorAnimation { duration: Config.quick } } }
        Kirigami.Icon { id: ic; anchors.horizontalCenter: parent.horizontalCenter; y: 12; width: 46; height: 46; source: cell.icon; roundToIconSize: false
            scale: tap.pressed ? 0.92 : 1; Behavior on scale { NumberAnimation { duration: Config.quick } } }
        Rectangle { visible: cell.pinned; x: ic.x + ic.width - 6; y: ic.y - 2; width: 8; height: 8; radius: 4; color: Config.fgSolid; opacity: 0.85 }
        Text { anchors.top: ic.bottom; anchors.topMargin: 5; x: 6; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter
            text: cell.name; color: Config.ink; font.pixelSize: 12; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap; lineHeight: 0.95; textFormat: Text.PlainText }
        HoverHandler { id: ch }
        TapHandler { id: tap; acceptedButtons: Qt.LeftButton; onTapped: cell.picked() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: cell.pinToggled() } }

    component FootBtn: Item { id: fb; property string icon; property string tip; signal tapped()
        width: 36; height: 36
        Rectangle { anchors.fill: parent; radius: 18; color: Config.fg(ft.pressed ? 0.20 : (fh.hovered ? 0.12 : 0.05)); border.width: 1; border.color: Config.fg(fh.hovered ? 0.18 : 0.08)
            Behavior on color { ColorAnimation { duration: Config.quick } } }
        Kirigami.Icon { anchors.centerIn: parent; width: 17; height: 17; source: fb.icon; isMask: true; color: Config.fgSolid; roundToIconSize: false; opacity: 0.9 }
        HoverHandler { id: fh }
        TapHandler { id: ft; onTapped: fb.tapped() }
        // our own small tip (no Plasma tooltip needed)
        Rectangle { visible: fh.hovered; anchors.bottom: parent.top; anchors.bottomMargin: 6; anchors.horizontalCenter: parent.horizontalCenter
            width: tipText.implicitWidth + 16; height: 24; radius: 8; color: Config.popSurface; border.width: 1; border.color: Config.fg(0.14)
            Text { id: tipText; anchors.centerIn: parent; text: fb.tip; color: Config.ink; font.pixelSize: 11 } } }

    // ---- search field ----
    Rectangle { id: fieldBox; x: 14; y: 12; width: parent.width - 28; height: 44; radius: 22
        color: Config.fg(0.07); border.width: 1; border.color: Config.fg(field.activeFocus ? 0.20 : 0.10)
        Kirigami.Icon { id: mag; x: 16; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; source: "search-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.7; roundToIconSize: false }
        Text { anchors.left: field.left; anchors.verticalCenter: parent.verticalCenter; visible: field.text === ""; text: "Search applications"; color: Config.inkDim; font.pixelSize: 15 }
        TextInput { id: field; anchors.left: mag.right; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
            color: Config.ink; font.pixelSize: 15; clip: true; selectByMouse: true; selectionColor: Config.fg(0.25); selectedTextColor: Config.fgSolid
            onTextChanged: { grid.currentIndex = 0; grid.positionViewAtBeginning() }
            Keys.onPressed: e => {
                const cols = Math.max(1, Math.floor(grid.width / root.cellW));
                if (e.key === Qt.Key_Escape) { if (text !== "") text = ""; else root.done(); e.accepted = true }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.launch(apps.storageIdAt(grid.currentIndex)); e.accepted = true }
                else if (e.key === Qt.Key_Down) { grid.currentIndex = Math.min(grid.count - 1, grid.currentIndex + cols); e.accepted = true }
                else if (e.key === Qt.Key_Up) { grid.currentIndex = Math.max(0, grid.currentIndex - cols); e.accepted = true }
                else if (e.key === Qt.Key_Right && cursorPosition === text.length) { grid.currentIndex = Math.min(grid.count - 1, grid.currentIndex + 1); e.accepted = true }
                else if (e.key === Qt.Key_Left && cursorPosition === 0) { grid.currentIndex = Math.max(0, grid.currentIndex - 1); e.accepted = true }
                else if (e.key === Qt.Key_Tab) { const c = [""].concat(apps.categories); apps.category = c[(c.indexOf(apps.category) + 1) % c.length]; e.accepted = true }
            } } }

    // ---- category chips ----
    ListView { id: chips; x: 14; y: fieldBox.y + fieldBox.height + 10; width: parent.width - 28; height: 30; orientation: ListView.Horizontal; spacing: 6; clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: ["All"].concat(apps.categories)
        delegate: Rectangle { required property string modelData; required property int index
            readonly property bool on: (index === 0 && apps.category === "") || apps.category === modelData
            height: 30; width: ct.implicitWidth + 24; radius: 15
            color: Config.fg(on ? 0.17 : (cth.hovered ? 0.09 : 0.045)); border.width: 1; border.color: Config.fg(on ? 0.24 : 0.08)
            Behavior on color { ColorAnimation { duration: Config.quick } }
            Text { id: ct; anchors.centerIn: parent; text: parent.modelData; color: Config.ink; font.pixelSize: 12; font.weight: parent.on ? Font.DemiBold : Font.Normal }
            HoverHandler { id: cth }
            TapHandler { onTapped: { apps.category = parent.index === 0 ? "" : parent.modelData; grid.currentIndex = 0; grid.positionViewAtBeginning(); field.forceActiveFocus() } } } }

    // ---- pinned (only while browsing everything) ----
    Item { id: pinnedBox; x: 8; y: chips.y + chips.height + 8; width: parent.width - 16; visible: root.browsing && pinnedRep.count > 0
        height: visible ? 22 + Math.ceil(pinnedRep.count / Math.max(1, Math.floor(width / root.cellW))) * root.cellH : 0
        Text { x: 10; text: "PINNED"; color: Config.inkDim; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 0.6 }
        Flow { y: 20; width: parent.width
            Repeater { id: pinnedRep; model: root.favorites.map(id => apps.info(id)).filter(a => a.storageId !== undefined)
                AppCell { required property var modelData; name: modelData.name; icon: modelData.icon; storageId: modelData.storageId; pinned: false
                    onPicked: root.launch(storageId); onPinToggled: root.togglePin(storageId) } } } }

    // ---- all apps ----
    Text { id: allLabel; x: 18; y: pinnedBox.y + pinnedBox.height + (pinnedBox.visible ? 6 : 0); color: Config.inkDim; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 0.6
        text: field.text !== "" ? (apps.count + (apps.count === 1 ? " RESULT" : " RESULTS")) : (apps.category === "" ? "ALL APPLICATIONS" : apps.category.toUpperCase()) }
    GridView { id: grid; x: 8; y: allLabel.y + 20; width: parent.width - 16; height: footer.y - y - 6; clip: true
        cellWidth: root.cellW; cellHeight: root.cellH; model: apps; boundsBehavior: Flickable.StopAtBounds; keyNavigationEnabled: false; highlightMoveDuration: 0
        delegate: AppCell { required property int index; required property var model
            name: model.name; icon: model.icon; storageId: model.storageId
            current: index === grid.currentIndex && (field.text !== "" || grid.activeNav); pinned: root.favorites.indexOf(model.storageId) >= 0
            onPicked: root.launch(storageId); onPinToggled: root.togglePin(storageId) }
        property bool activeNav: false
        onCurrentIndexChanged: activeNav = true
    }
    Text { anchors.centerIn: grid; visible: apps.count === 0; text: "No application matches"; color: Config.inkDim; font.pixelSize: 14 }

    // ---- footer ----
    Rectangle { x: 14; y: footer.y - 1; width: parent.width - 28; height: 1; color: Config.fg(0.08) }
    Item { id: footer; x: 14; y: parent.height - 52; width: parent.width - 28; height: 52
        // the account's real name and face (KUser through control/UserInfo, as quick settings does), not the home folder's name
        // and a guessed AccountsService path
        Control.UserInfo { id: user }
        readonly property string userName: String(user.name).replace(/^\S+\s+/, "")
        Row { anchors.verticalCenter: parent.verticalCenter; spacing: 10
            Item { width: 32; height: 32
                Rectangle { anchors.fill: parent; radius: 16; color: Config.fg(0.08); border.width: 1; border.color: Config.fg(0.18) }
                Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "user-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.8; roundToIconSize: false; visible: face.status !== Image.Ready }
                Rectangle { id: faceMask; anchors.fill: parent; anchors.margins: 2; radius: width / 2; visible: false; layer.enabled: true; layer.smooth: true }
                Image { id: face; anchors.fill: faceMask; source: user.urlAvatar; sourceSize: Qt.size(96, 96); fillMode: Image.PreserveAspectCrop; visible: false; layer.enabled: true; mipmap: true }
                MultiEffect { anchors.fill: faceMask; source: face; maskEnabled: true; maskSource: faceMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; visible: face.status === Image.Ready } }
            Text { anchors.verticalCenter: parent.verticalCenter; text: footer.userName; color: Config.ink; font.pixelSize: 14; font.weight: Font.Medium } }
        Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            FootBtn { icon: "configure"; tip: "Sirca Settings"; onTapped: { Shell.dbusSend("onur.SircaShell", "/SircaShell", "onur.SircaShell", "openSettings"); root.done() } }
            FootBtn { icon: "system-lock-screen-symbolic"; tip: "Lock"; onTapped: { Shell.dbusSend("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver", "Lock"); root.done() } }
            FootBtn { icon: "system-suspend-symbolic"; tip: "Sleep"; onTapped: { Shell.runDetached("systemctl", ["suspend"]); root.done() } }
            FootBtn { icon: "system-shutdown-symbolic"; tip: "Power"; onTapped: { root.done(); Shell.dbusSend("onur.SircaShell", "/SircaShell", "onur.SircaShell", "togglePowerMenu") } } } }
}
