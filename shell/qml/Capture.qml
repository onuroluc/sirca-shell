// Screenshot overlay (Print). The window manager hands over one frame of the screen first; this window then shows that
// frozen frame, so menus and popups that were open stay in the picture. Drag = a region, click = the window under the
// pointer, Enter = the whole screen, Esc or right click = cancel. The cut is saved to ~/Pictures/Screenshots and copied.
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import SircaShell
import "Glass"

Window {
    id: cw
    color: "black"
    flags: Qt.FramelessWindowHint
    visible: false
    width: Screen.width; height: Screen.height
    signal opened()
    signal recordRequested(real x, real y, real w, real h)
    property string mode: "shot"                       // "shot" = picture, "record" = start a recording of the selection (Tab switches)
    readonly property color recColor: Qt.rgba(229/255, 72/255, 77/255, 1)
    property bool setupDone: false
    property bool pending: false                       // a frame was asked for and has not arrived yet
    property bool dryRun: false                        // preview and tests: nothing is saved or copied
    property var windowRects: []                       // [{x,y,width,height}] top-most first, set by Main when opening
    property rect sel: Qt.rect(0, 0, 0, 0)             // the drag rectangle
    property bool dragging: false
    property int hoverWindow: -1
    property point pointer: Qt.point(-1, -1)
    readonly property rect target: dragging ? sel : (hoverWindow >= 0 ? clip(windowRects[hoverWindow]) : Qt.rect(0, 0, 0, 0))
    readonly property bool hasTarget: target.width > 0 && target.height > 0
    property real show: 0
    Behavior on show { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    function clip(g) { const x = Math.max(0, g.x), y = Math.max(0, g.y); return Qt.rect(x, y, Math.min(width, g.x + g.width) - x, Math.min(height, g.y + g.height) - y) }
    function begin(rects, file) {
        if (visible || pending) { cancel(); return }
        windowRects = rects || []; pending = true
        if (file) Screenshot.useFile(file); else Screenshot.grab(cw.screen ? cw.screen.name : "")
    }
    function reveal() {
        pending = false
        if (!setupDone) { Shell.setupCapture(cw); setupDone = true }
        sel = Qt.rect(0, 0, 0, 0); dragging = false; hoverWindow = -1; pointer = Qt.point(-1, -1); flash.opacity = 0
        visible = true; show = 1; keys.forceActiveFocus(); cw.opened()
        console.log("capture: frame shown, revision", Screenshot.revision, "windows", windowRects.length)
    }
    function cancel() { pending = false; visible = false; show = 0; Screenshot.drop() }
    function take(r) {
        if (r.width < 3 || r.height < 3) return
        if (mode === "record") { const q = Qt.rect(r.x, r.y, r.width, r.height); cancel(); if (dryRun) console.log("record (dry run):", q); else startLater.go(q); return }
        const path = dryRun ? "" : Screenshot.finish(r.x, r.y, r.width, r.height, cw.width, true, true)
        if (dryRun) console.log("capture (dry run):", r.x, r.y, r.width, r.height)
        // the file is written on a worker thread: the notification comes from onSaved once it is there
        done.restart(); flashAnim.restart()
    }
    Timer { id: done; interval: 170; onTriggered: cw.cancel() }
    // the overlay must be off the screen before the first recorded frame
    Timer { id: startLater; interval: 220; property rect r; function go(q) { r = q; restart() } onTriggered: cw.recordRequested(r.x, r.y, r.width, r.height) }
    Connections { target: Screenshot
        function onFrameChanged() { if (cw.pending && Screenshot.ready) cw.reveal() }
        function onFailed(why) { if (!cw.pending) return; cw.pending = false; console.warn("screenshot failed:", why); Shell.notify("Screenshot failed", why, "") }
        function onSaved(path, w, h) { if (path !== "") Shell.notify("Screenshot", "Saved and copied  ·  " + path.substring(path.lastIndexOf("/") + 1), path, path); else Shell.notify("Screenshot failed", "The file could not be written", "") } }

    Image { id: frame; anchors.fill: parent; cache: false; asynchronous: false; smooth: true
        source: cw.visible && Screenshot.ready ? "image://shot/frame" + Screenshot.revision : "" }

    // everything outside the target goes darker (four bands, so the target itself keeps the frame's real colours)
    Item { anchors.fill: parent; opacity: cw.show
        readonly property color dim: Qt.rgba(0, 0, 0, cw.hasTarget ? 0.52 : 0.34)
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Rectangle { color: parent.dim; x: 0; y: 0; width: cw.width; height: cw.hasTarget ? cw.target.y : cw.height }
        Rectangle { color: parent.dim; visible: cw.hasTarget; x: 0; y: cw.target.y + cw.target.height; width: cw.width; height: cw.height - y }
        Rectangle { color: parent.dim; visible: cw.hasTarget; x: 0; y: cw.target.y; width: cw.target.x; height: cw.target.height }
        Rectangle { color: parent.dim; visible: cw.hasTarget; x: cw.target.x + cw.target.width; y: cw.target.y; width: cw.width - x; height: cw.target.height } }

    // the target's frame and its size
    Rectangle { visible: cw.hasTarget; x: cw.target.x - 1; y: cw.target.y - 1; width: cw.target.width + 2; height: cw.target.height + 2
        color: "transparent"; border.width: 1.5; border.color: cw.mode === "record" ? cw.recColor : (cw.dragging ? Config.accent : Qt.rgba(1, 1, 1, 0.85)); radius: cw.dragging ? 2 : 10 }
    Rectangle { id: sizeTag; visible: cw.hasTarget; radius: height / 2; color: Qt.rgba(0.06, 0.07, 0.10, 0.82); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16)
        width: sizeText.implicitWidth + 22; height: 26
        x: Math.max(8, Math.min(cw.width - width - 8, cw.target.x + (cw.target.width - width) / 2))
        y: cw.target.y + cw.target.height + 10 + height < cw.height - 90 ? cw.target.y + cw.target.height + 10 : Math.max(8, cw.target.y - height - 10)
        Text { id: sizeText; anchors.centerIn: parent; color: "white"; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 }
            text: Math.round(cw.target.width * Screen.devicePixelRatio) + " × " + Math.round(cw.target.height * Screen.devicePixelRatio) } }

    // crosshair lines while nothing is pressed
    Rectangle { visible: !cw.dragging && cw.pointer.x >= 0 && !bar.hovered; x: cw.pointer.x; y: 0; width: 1; height: cw.height; color: Qt.rgba(1, 1, 1, 0.22) }
    Rectangle { visible: !cw.dragging && cw.pointer.x >= 0 && !bar.hovered; x: 0; y: cw.pointer.y; width: cw.width; height: 1; color: Qt.rgba(1, 1, 1, 0.22) }

    Item { id: keys; anchors.fill: parent; focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { cw.cancel(); e.accepted = true }
            else if (e.key === Qt.Key_Tab || e.key === Qt.Key_R) { cw.mode = cw.mode === "record" ? "shot" : "record"; e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_F) { cw.take(Qt.rect(0, 0, cw.width, cw.height)); e.accepted = true } }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; cursorShape: Qt.CrossCursor
            property point from
            function pick(x, y) { for (let i = 0; i < cw.windowRects.length; ++i) { const g = cw.windowRects[i]; if (x >= g.x && x < g.x + g.width && y >= g.y && y < g.y + g.height) return i } return -1 }
            onPositionChanged: m => { cw.pointer = Qt.point(m.x, m.y)
                if (pressed && pressedButtons & Qt.LeftButton) {
                    if (!cw.dragging && Math.abs(m.x - from.x) + Math.abs(m.y - from.y) > 5) cw.dragging = true
                    if (cw.dragging) { const x = Math.max(0, Math.min(from.x, m.x)), y = Math.max(0, Math.min(from.y, m.y));
                        cw.sel = Qt.rect(x, y, Math.min(cw.width, Math.max(from.x, m.x)) - x, Math.min(cw.height, Math.max(from.y, m.y)) - y) }
                } else cw.hoverWindow = pick(m.x, m.y) }
            onPressed: m => { if (m.button === Qt.RightButton) { cw.cancel(); return } from = Qt.point(m.x, m.y) }
            onReleased: m => { if (m.button !== Qt.LeftButton || !cw.visible) return
                if (cw.dragging) { const r = cw.sel; cw.take(r) } else if (cw.hoverWindow >= 0) cw.take(cw.target) }
            onExited: cw.pointer = Qt.point(-1, -1) } }

    // the hint bar: frosted from the frozen frame itself (nothing live is behind this window)
    Item { id: bar; width: hints.implicitWidth + 36; height: 46; x: Math.round((cw.width - width) / 2); y: cw.height - height - 56
        opacity: cw.show * (cw.dragging ? 0.25 : 1); Behavior on opacity { NumberAnimation { duration: 140 } }
        transform: Translate { y: (1 - cw.show) * 12 }
        readonly property bool hovered: barHover.hovered
        HoverHandler { id: barHover }
        ShaderEffectSource { id: under; anchors.fill: parent; sourceItem: frame; sourceRect: Qt.rect(bar.x, bar.y, bar.width, bar.height); visible: false; live: cw.visible }
        MultiEffect { id: frost; anchors.fill: parent; source: under; blurEnabled: true; blur: 1; blurMax: 48; autoPaddingEnabled: false; brightness: -0.18; saturation: 0.15
            layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: barMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 } }
        Item { id: barMask; anchors.fill: parent; layer.enabled: true; visible: false; Rectangle { anchors.fill: parent; radius: height / 2 } }
        Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(0.07, 0.08, 0.11, 0.42); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20) }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }                       // presses on the bar are not a selection
        Row { id: hints; anchors.centerIn: parent; spacing: 6
            // picture / recording switch (Tab)
            Rectangle { width: modeRow.implicitWidth + 6; height: 30; radius: 15; color: Qt.rgba(0, 0, 0, 0.25); anchors.verticalCenter: parent.verticalCenter
                Row { id: modeRow; anchors.centerIn: parent
                    Repeater { model: [ { id: "shot", t: "Screenshot" }, { id: "record", t: "Record" } ]
                        Rectangle { id: seg; required property var modelData; readonly property bool on: cw.mode === modelData.id
                            width: segRow.implicitWidth + 22; height: 24; radius: 12; color: on ? (modelData.id === "record" ? Qt.rgba(229/255, 72/255, 77/255, 0.85) : Qt.rgba(1, 1, 1, 0.20)) : "transparent"
                            Behavior on color { ColorAnimation { duration: Config.quick } }
                            Row { id: segRow; anchors.centerIn: parent; spacing: 6
                                Rectangle { visible: seg.modelData.id === "record"; width: 7; height: 7; radius: 3.5; color: seg.on ? "white" : cw.recColor; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: seg.modelData.t; color: "white"; opacity: seg.on ? 1 : 0.7; font.pixelSize: 12; font.weight: seg.on ? Font.DemiBold : Font.Normal } }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: cw.mode = seg.modelData.id } } } } }
            Item { width: 8; height: 1 }
            Repeater { model: [ { t: "Drag", d: "region" }, { t: "Click", d: "window" } ]
                Row { required property var modelData; spacing: 6; anchors.verticalCenter: parent.verticalCenter; rightPadding: 10
                    Rectangle { width: k.implicitWidth + 14; height: 22; radius: 7; color: Qt.rgba(1, 1, 1, 0.12); anchors.verticalCenter: parent.verticalCenter
                        Text { id: k; anchors.centerIn: parent; text: modelData.t; color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold } }
                    Text { text: modelData.d; color: Qt.rgba(1, 1, 1, 0.78); font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter } } }
            Repeater { model: [ { t: "Enter", d: "whole screen", act: "full" }, { t: "Esc", d: "cancel", act: "cancel" } ]
                Item { id: b; required property var modelData; width: br.implicitWidth + 16; height: 30; anchors.verticalCenter: parent.verticalCenter
                    Rectangle { anchors.fill: parent; radius: 15; color: Qt.rgba(1, 1, 1, bh.hovered ? 0.12 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
                    Row { id: br; anchors.centerIn: parent; spacing: 6
                        Rectangle { width: bk.implicitWidth + 14; height: 22; radius: 7; color: Qt.rgba(1, 1, 1, 0.12); anchors.verticalCenter: parent.verticalCenter
                            Text { id: bk; anchors.centerIn: parent; text: b.modelData.t; color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold } }
                        Text { text: b.modelData.d; color: Qt.rgba(1, 1, 1, 0.78); font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter } }
                    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: b.modelData.act === "full" ? cw.take(Qt.rect(0, 0, cw.width, cw.height)) : cw.cancel() } } } } }

    Rectangle { id: flash; anchors.fill: parent; color: "white"; opacity: 0
        SequentialAnimation { id: flashAnim; NumberAnimation { target: flash; property: "opacity"; to: 0.22; duration: 50 } NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 120 } } }
}
