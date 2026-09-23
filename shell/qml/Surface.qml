// A layer-shell surface whose visible shape is given either as `polygon` (sampled outline from LobeShape) or as
// rounded-rect `lobes`. Blur region and input mask are (re)sent on every change and again once the window is
// mapped — a region sent to an unmapped window is lost, and a static shape would otherwise never resend it.
import QtQuick
import SircaShell

Window {
    id: surface
    property string edge: "top"
    property int strut: 0
    property var lobes: []
    property var polygon: []

    // ---- dodge windows (same idea as a Plasma panel set to "Dodge Windows"): no reserved space; when a window covers
    // the bar's strip of the screen (a maximised app, a 3440x1440 game centred on the ultrawide) the bar slides off its
    // edge, and a thin strip at the screen edge brings it back while the pointer is there.
    property bool dodge: Config.dodge
    property bool blur: true                   // glass behind this surface (off: the tint alone carries it)
    onBlurChanged: { applyShape(); if (typeof surface.pushShape === "function") surface.pushShape() }
    property bool covered: false               // set by Main from the window watcher
    // ---- popups close when the surface loses keyboard focus (no full-screen click catcher: that swallowed the press, so a
    // window could not be dragged while a popup was open). While a popup is open the surface takes the keyboard:
    // "exclusive" for a moment makes KWin focus it (a layer surface cannot ask for activation any other way), then
    // "ondemand" lets the focus move on as soon as anything else is clicked, and that loss closes the popup. The click,
    // the drag, the scroll go to their window untouched.
    property bool popupFocus: false
    signal focusLost()
    signal pressedAnywhere()                     // any press on this surface (passive; nothing is taken from the items)
    property bool focusArmed: false
    readonly property bool focusDebug: Config.user && Config.user.debugFocus === true        // live: "debugFocus": true in config.json
    onPopupFocusChanged: {
        focusArmed = false; lostLater.stop();
        if (popupFocus) { Shell.setKeyboardMode(surface, "exclusive"); relaxFocus.restart() }
        else { relaxFocus.stop(); armFocus.stop(); Shell.setKeyboardMode(surface, restingKeyboardMode) }
    }
    property string restingKeyboardMode: "none"
    onRestingKeyboardModeChanged: if (!popupFocus) Shell.setKeyboardMode(surface, restingKeyboardMode)
    Timer { id: relaxFocus; interval: 160; onTriggered: { Shell.setKeyboardMode(surface, "ondemand"); armFocus.restart() } }
    Timer { id: armFocus; interval: 220; onTriggered: { surface.focusArmed = true; if (surface.focusDebug) console.log("focus armed", surface.title, "active", surface.active) } }
    onActiveChanged: { if (focusDebug) console.log("focus", title, "active", active, "popup", popupFocus, "armed", focusArmed);
        if (popupFocus && focusArmed && !active) lostLater.restart(); else lostLater.stop() }
    PointHandler { parent: surface.contentItem; acceptedButtons: Qt.AllButtons; onActiveChanged: if (active) surface.pressedAnywhere() }
    Timer { id: lostLater; interval: 80; onTriggered: if (surface.popupFocus && !surface.active) { if (surface.focusDebug) console.log("focus LOST ->", surface.title); surface.focusLost() } }

    property bool holdOpen: false              // set by the bar itself: a lobe is open, cards are showing, …
    property bool quiet: false                 // a fullscreen window has focus: not even the edge strip
    property real slideMax: 80
    property rect edgeStrip: Qt.rect(0, 0, 0, 0)   // x/width of the reveal strip, in surface coordinates
    readonly property bool pointerIn: hover.hovered
    readonly property bool shouldShow: !dodge || !covered || holdOpen || pointerIn
    property bool shown: true
    readonly property bool dbg: Qt.application.arguments.indexOf("--debug") >= 0
    // a window moved over the bar: leave at once, like a Plasma panel does. (The dwell below is only for the pointer
    // leaving a bar that is already covered, so it does not vanish under a hand that overshoots by a few pixels.)
    onCoveredChanged: { if (dbg) console.log(edge, "covered", covered); if (covered && dodge && !holdOpen && !pointerIn) { hideDelay.stop(); shown = false } }
    onShownChanged: if (dbg) console.log(edge, "shown", shown)
    onShouldShowChanged: {
        if (shouldShow) { hideDelay.stop(); shown = true; }        // pointer at the edge: come back at once, no dwell
        else hideDelay.restart();
    }
    onHoldOpenChanged: if (holdOpen) shown = true
    Timer { id: hideDelay; interval: 420; onTriggered: if (!surface.shouldShow) surface.shown = false }
    property real slide: shown ? 0 : slideMax
    // sliding in lands with a light bounce (a few px past rest, then back); sliding out is short and direct (no wind-up:
    // it read as lag when a window was dragged over the bar)
    Behavior on slide { NumberAnimation { duration: surface.shown ? 260 : 170; easing.type: surface.shown ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.5 } }   // 1.5 = lands ~7 px past rest (0.9 was ~3 px: invisible)
    readonly property bool hiddenFully: slide >= slideMax - 0.5
    onHiddenFullyChanged: applyShape()
    onQuietChanged: applyShape()
    onEdgeStripChanged: applyShape()
    // On the window's root item, not on an overlay: an item stacked above the content swallowed hover for everything
    // under it (dock magnification, spotlights, hover pills all went dead). A handler on the common parent sees the
    // pointer anywhere inside the input mask and leaves the children's own hover alone.
    HoverHandler { id: hover; parent: surface.contentItem }
    function maskExtra() {
        if (!dodge) return [];
        if (quiet && covered && !holdOpen) return [0, 0, 1, 1];               // in a fullscreen game the edge does nothing
        const h = hiddenFully ? 2 : strutSize;
        return [edgeStrip.x, edge === "top" ? 0 : surface.height - h, edgeStrip.width, h];
    }
    property int strutSize: 0
    // multi-screen: the screen this surface lives on is Window.screen (set by ScreenSet before the surface shows); its
    // origin in the virtual desktop, for the window-overlap test (task geometry is in desktop coordinates)
    readonly property int screenX: screen ? screen.virtualX : 0
    readonly property int screenY: screen ? screen.virtualY : 0
    // "no bar on this screen" (edit mode > Screens): unmapped, nothing else changes
    property bool userHidden: false
    onUserHiddenChanged: if (hasBeenSetUp) visible = !userHidden
    property bool hasBeenSetUp: false
    color: "transparent"
    // Wayland never tells a client where its surface is, and layer-shell ignores these — but hosted applets place their
    // tooltips, menus and notification popups relative to the window's position, so keep it truthful.
    x: Math.round((Screen.width - width) / 2)
    y: edge === "top" ? 0 : Screen.height - height
    flags: Qt.FramelessWindowHint
    visible: false

    function applyShape() {
        if (polygon && polygon.length >= 6) Shell.setShapePolygon(surface, hiddenFully ? [] : polygon, maskExtra(), blur);
        else if (lobes && lobes.length) Shell.setShape(surface, lobes);
        surface.requestUpdate();   // blur/mask are double-buffered Wayland state: they apply on the next surface commit
    }
    onPolygonChanged: applyShape()
    onLobesChanged: applyShape()
    onStrutChanged: if (visible) Shell.setExclusiveZone(surface, dodge ? 0 : strut)
    onVisibleChanged: if (visible) { Qt.callLater(applyShape); resend.start() }
    // --fps: log swapped frames per half second while something is animating
    property int frames: 0
    property double lastSwap: 0
    property double worst: 0
    property bool firstFrameLogged: false
    onFrameSwapped: { if (!firstFrameLogged) { firstFrameLogged = true; console.log("start-up: first frame of", edge, "after", Shell.sinceStart(), "ms"); Shell.markReady(edge) } frames++; const t = Date.now(); if (lastSwap > 0) worst = Math.max(worst, t - lastSwap); lastSwap = t }
    // frame meter (Sirca Settings > Behaviour, or --fps): frames this surface swapped in the last half second and the longest
    // gap between two of them. At rest it must read 0: a number that never drops to 0 means something repaints for nothing.
    readonly property bool meter: Config.showFps || Qt.application.arguments.indexOf("--fps") >= 0
    property string meterText: ""
    Timer { running: surface.meter; interval: 500; repeat: true; onTriggered: {
        const busy = surface.frames > 3        // the readout changing is itself a frame or two
        surface.meterText = busy ? (surface.frames * 2) + " fps  ·  worst " + Math.round(surface.worst) + " ms" : "idle"
        if (busy) console.log("fps", surface.edge, surface.frames * 2, "worst ms", surface.worst)
        surface.frames = 0; surface.worst = 0; surface.lastSwap = 0 } }
    Rectangle { visible: surface.meter; z: 1000; x: 24; y: surface.edge === "top" ? 8 : surface.height - height - 8; width: mt.implicitWidth + 18; height: 22; radius: 11
        color: Qt.rgba(0, 0, 0, 0.72); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)      // literal-ok: a debug readout, always white on black
        Text { id: mt; anchors.centerIn: parent; text: surface.edge + "  " + surface.meterText; color: "white"; font.pixelSize: 11; font.features: { "tnum": 1 } } }   // literal-ok
    Timer { id: resend; interval: 250; onTriggered: surface.applyShape() }   // belt and braces after mapping
    Component.onCompleted: {
        strutSize = strut;
        Shell.setupLayer(surface, edge, dodge ? 0 : strut, "dock");
        hasBeenSetUp = true;
        visible = !userHidden;
        applyShape();   // synchronously after show(): rides on the surface's first commit, which the effect samples
    }
}
