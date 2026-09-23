// The shell's own wallpaper: a full-screen surface on the background layer. While plasmashell still runs, its desktop
// window covers this one, so nothing changes; once plasmashell is not started, this is the wallpaper. The picture is the
// config key "wallpaper" (Sirca Settings > Desktop); until that is set, whatever Plasma shows now. Changes cross-fade.
import QtQuick
import SircaShell

Window {
    id: wp
    color: "#05060f"
    flags: Qt.FramelessWindowHint
    width: Screen.width; height: Screen.height
    // NEVER visible before the layer is set: a window that maps first is an ordinary full-screen toplevel (it covered the
    // desktop on 2026-09-19). `ready` flips only after Shell.setupWallpaper().
    property bool ready: false
    visible: ready && (Config.ownWallpaper === true || (Config.ownWallpaper === "auto" && !Shell.plasmaRunning))
    title: "Sirca Shell — wallpaper"
    readonly property string path: Config.wallpaper !== "" ? Config.wallpaper : Shell.plasmaWallpaper()
    property bool useA: true
    // The new picture loads in the hidden layer; its Ready flips the layers. Going back to the picture the hidden layer
    // ALREADY holds (dark -> light -> dark) changes nothing in it, so no Ready ever comes: flip at once in that case.
    // Nothing is decoded while the window is not on screen (with plasmashell running this window is unmapped, and a 5K
    // picture is a big decode): a path change is picked up when the window becomes visible, see onVisibleChanged.
    onPathChanged: if (visible) show(path)
    function show(p) { const u = toUrl(p), back = useA ? b : a
        if (String(back.source) === u && back.status === Image.Ready) { useA = !useA; return }
        back.source = u }
    onVisibleChanged: { if (!visible) return; const u = toUrl(path), front = useA ? a : b
        if (String(front.source) === u) return
        if (String(front.source) === "") front.source = u; else show(path) }      // first show: straight in, no fade from black
    // once a cross-fade has ended the hidden layer's picture is dropped (its texture is the size of the screen). The flip
    // shortcut in show() then simply misses and reloads, which is what it did before the picture was ever cached.
    function dropHidden() { const back = useA ? b : a; if (back.opacity === 0 && String(back.source) !== toUrl(path)) back.source = "" }
    function toUrl(p) { return p === "" ? "" : "file://" + p }
    // With plasmashell still running, its desktop window is in the same layer as ours and whichever mapped LAST is on top.
    // When plasmashell (re)starts, ours is mapped again a moment later so it stays the desktop you click on.
    Connections { target: Shell; function onPlasmaRunningChanged() { if (Shell.plasmaRunning && Config.ownWallpaper === true) remap.restart() } }
    Timer { id: remap; interval: 3500; onTriggered: { wp.ready = false; remapShow.restart() } }
    function remapNow() { wp.ready = false; remapShow.restart() }
    Timer { id: remapShow; interval: 120; onTriggered: { wp.ready = true; raiseLater.restart() } }
    Timer { id: raiseLater; interval: 600; onTriggered: Shell.raiseWallpaper() }       // see Shell::raiseWallpaper
    signal menuRequested(real x, real y)
    signal pressedAnywhere()
    Component.onCompleted: { Shell.setupWallpaper(wp, true); ready = true; raiseLater.restart() }    // the picture loads through onVisibleChanged
    component Pic: Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false; smooth: true; mipmap: true
        sourceSize: Qt.size(wp.width, wp.height) }
    Pic { id: a; opacity: wp.useA ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad; onRunningChanged: if (!running) wp.dropHidden() } } }
    Pic { id: b; opacity: wp.useA ? 0 : 1; Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad; onRunningChanged: if (!running) wp.dropHidden() } }
        onStatusChanged: if (status === Image.Ready && source != "" && wp.useA) wp.useA = false }
    // the desktop itself: right click = the desktop menu, any press closes what the shell has open
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: m => { wp.pressedAnywhere(); if (m.button === Qt.RightButton) wp.menuRequested(m.x, m.y) } }
    Connections { target: a; function onStatusChanged() { if (a.status === Image.Ready && a.source != "" && !wp.useA && String(a.source) === wp.toUrl(wp.path)) wp.useA = true } }
}
