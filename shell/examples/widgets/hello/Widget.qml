// The smallest QML widget: a greeting that follows the shell's colours and the time of day. Copy this folder to
// ~/.config/sirca-shell/widgets/hello/ and add "user:hello" to the bar (edit mode: the shelf lists it as "Hello").
// A widget is any Item; its implicitWidth is its width in the bar, its height is the bar's. It sits in the host's context:
//   widget.config  the shell's design tokens (= Config: fg(), ink, inkDim, accent …)
//   widget.shell   the Shell singleton (D-Bus helpers, runDetached, notify …)
//   widget.height  the bar height     widget.quiet   true while the bar is hidden / a game has focus: pause your timers
//   widget.hovered the pointer is over the widget
// `import SircaShell` works as well and gives the same Config / Shell singletons.
import QtQuick

Item {
    id: hello
    implicitWidth: label.implicitWidth
    property date now: new Date()
    Timer { interval: 60000; running: !widget.quiet; repeat: true; onTriggered: hello.now = new Date() }
    Text { id: label; anchors.verticalCenter: parent.verticalCenter
        readonly property int h: hello.now.getHours()
        text: h < 5 ? "Still up?" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        color: widget.hovered ? widget.config.accent : widget.config.ink; font.pixelSize: 13; font.weight: Font.Medium
        Behavior on color { ColorAnimation { duration: widget.config.quick } } }
    TapHandler { onTapped: widget.shell.notify("Hello", "It is " + Qt.formatTime(hello.now, "hh:mm"), "") }
}
