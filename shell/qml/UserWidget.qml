// Host for one user widget from ~/.config/<app>/widgets/<name>/ (see src/userwidgets.h). The bar places it like any
// other widget: `UserWidget { name: "uptime"; height: barHeight }` and reads its implicitWidth.
//   Widget.qml   — loaded as is. It sits in this file's context, so it can use `widget.config` (= Config), `widget.shell`
//                  (= Shell), `widget.height`, `widget.dir`, `widget.quiet`, `widget.hovered`; `import SircaShell` works
//                  too, the singletons are the shell's own. Its implicitWidth is its width in the bar.
//   widget.json  — without a Widget.qml the built-in Exec type: `exec` runs every `interval` s (in the widget's folder,
//                  which is first on PATH), the first stdout line is shown as text, `icon` (theme name or file) before
//                  it, `click` runs on a tap. With a Widget.qml the json only adds a label / icon for the edit shelf.
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell

Item {
    id: widget
    required property string name
    property bool quiet: false                                           // the bar is slid away / a game has focus: no polling
    readonly property var info: { UserWidgets.names; return UserWidgets.info(name) }   // re-read when the folder changes
    readonly property string dir: info.dir || ""
    readonly property bool isExec: !!info.exec && !info.qml
    readonly property bool hovered: hover.hovered
    readonly property var config: Config
    readonly property var shell: Shell
    implicitWidth: loader.item ? loader.item.implicitWidth : (loader.status === Loader.Error ? broken.implicitWidth : (isExec ? execRow.implicitWidth : 0))   // a widget whose folder is gone takes no room

    // ---- a Widget.qml of its own
    Loader { id: loader; active: !!widget.info.qml && widget.visible; source: active ? "file://" + widget.info.qml : ""; height: widget.height; anchors.verticalCenter: parent.verticalCenter
        onStatusChanged: if (status === Loader.Error) console.warn("user widget", widget.name, "failed to load:", source) }   // (the QML engine has logged the reason)
    // a broken widget shows its name, so the bar still explains the empty slot
    Text { id: broken; visible: loader.status === Loader.Error; anchors.verticalCenter: parent.verticalCenter; text: "⚠ " + widget.name; color: Config.inkDim; font.pixelSize: 12 }

    // ---- the Exec type
    ExecRunner { id: runner; command: widget.isExec ? widget.info.exec : ""; workingDirectory: widget.dir; interval: widget.info.interval || 5
        running: widget.isExec && widget.visible && !widget.quiet }
    Row { id: execRow; visible: widget.isExec; spacing: 6; anchors.verticalCenter: parent.verticalCenter
        Kirigami.Icon { visible: !!widget.info.icon; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; source: widget.info.icon || ""; color: Config.ink; roundToIconSize: false }
        Text { anchors.verticalCenter: parent.verticalCenter; text: runner.text !== "" ? runner.text : (runner.failed ? "⚠ " + widget.name : "…")
            color: runner.failed ? Config.inkDim : Config.ink; font.pixelSize: 13; font.weight: Font.Medium; font.features: { "tnum": 1 } } }
    HoverHandler { id: hover; enabled: widget.isExec && !!widget.info.click; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: widget.isExec && !!widget.info.click; onTapped: runner.run(widget.info.click) }
}
