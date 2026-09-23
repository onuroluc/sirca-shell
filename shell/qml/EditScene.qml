// Edit mode: a scene of its own, like Plasma's. The desktop dims, the bar and the dock stay live (they show their own
// edit overlays: widget chips, width handles, unpin badges) and two floating strips carry every option there is, in
// tabs. All of it writes straight to the config, which the shell re-reads at once: what you change is what you see.
import QtQuick
import SircaShell
import "Glass"

Window {
    id: es
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false
    width: Screen.width; height: Screen.height
    signal done()
    signal moreSettings()
    property rect barHole: Qt.rect(0, 0, 0, 0)          // where the bar and the dock are (screen coordinates): left clickable
    property rect dockHole: Qt.rect(0, 0, 0, 0)
    property bool setupDone: false
    property real show: 0
    Behavior on show { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    readonly property color accent: Config.accent

    function open() { if (!setupDone) { Shell.setupSearch(es); setupDone = true } visible = true; show = 1; keys.forceActiveFocus(); regions.restart() }
    function close_() { visible = false; show = 0 }
    Timer { id: regions; interval: 30; onTriggered: es.pushRegions() }
    function pushRegions() { if (!visible) return
        const p = []; for (const it of [barStrip, dockStrip, pill, screensStrip]) if (it.visible) p.push({ x: it.x, y: it.y, w: it.width, h: it.height, r: it.radius })
        Shell.setSceneRegions(es, p, [ { x: barHole.x, y: barHole.y, w: barHole.width, h: barHole.height }, { x: dockHole.x, y: dockHole.y, w: dockHole.width, h: dockHole.height } ]); es.requestUpdate() }
    onBarHoleChanged: regions.restart(); onDockHoleChanged: regions.restart()

    // ---- writing: sliders write while they move, a little throttled (every write re-evaluates the whole shell)
    property var pending: ({})
    Timer { id: flush; interval: 45; onTriggered: { const p = es.pending; es.pending = ({}); if (Object.keys(p).length) Shell.saveConfigKeys(p) } }
    function put(key, value, now) { const p = Object.assign({}, pending); p[key] = value; pending = p; if (now) { flush.stop(); flush.triggered() } else if (!flush.running) flush.start() }

    // ---- every option, as data. t: num | bool | choice
    readonly property var barTabs: [
        { name: "Size", items: [
            { k: "barWidthMode", t: "choice", label: "Width", options: [["auto", "Scaled"], ["fill", "Fill screen"], ["fit", "Fit content"], ["custom", "Custom"]] },
            { k: "barWidth", t: "num", label: "Custom width", from: 480, to: Screen.width, step: 2, unit: " px", when: "barWidthMode=custom" },
            { k: "barFillMargin", t: "num", label: "Side margin", from: 0, to: 120, step: 1, unit: " px", when: "barWidthMode=fill" },
            { k: "barHeight", t: "num", label: "Height", from: 28, to: 56, step: 1, unit: " px" },
            { k: "barGap", t: "num", label: "Gap to the edge", from: 0, to: 40, step: 1, unit: " px" },
            { k: "barPad", t: "num", label: "End padding", from: 8, to: 60, step: 1, unit: " px" },
            { k: "barSpacing", t: "num", label: "Widget spacing", from: 6, to: 40, step: 1, unit: " px" } ] },
        { name: "Glass", items: [
            { k: "barBlur", t: "bool", label: "Blur behind" },
            { k: "barTintAlpha", t: "num", label: "Tint", from: 0, to: 0.95, step: 0.01, pct: true },
            { k: "barRimAlpha", t: "num", label: "Edge line", from: 0, to: 0.5, step: 0.01, pct: true },
            { k: "barSheen", t: "num", label: "Top sheen", from: 0, to: 0.3, step: 0.005, pct: true },
            { k: "barShadow", t: "num", label: "Shadow", from: 0, to: 1, step: 0.01, pct: true },
            { k: "barHazeStrength", t: "num", label: "Colour haze", from: 0, to: 1, step: 0.01, pct: true },
            { k: "cornerRadius", t: "num", label: "Popup corners", from: 6, to: 32, step: 1, unit: " px" } ] },
        { name: "Widgets", items: [
            { k: "barHoverPills", t: "bool", label: "Hover pills" },
            { k: "barIconScale", t: "num", label: "Icon size", from: 0.8, to: 1.5, step: 0.05, mult: true },
            { k: "titleIcon", t: "bool", label: "Title: app icon" },
            { k: "titleMaxWidth", t: "num", label: "Title: max width", from: 120, to: 900, step: 10, unit: " px" },
            { k: "levelMeter", t: "bool", label: "Now playing: live meter" } ] },
        { name: "Clock", items: [
            { k: "clock24h", t: "bool", label: "24 hour" },
            { k: "clockSeconds", t: "bool", label: "Seconds" },
            { k: "clockDate", t: "bool", label: "Date in the clock" },
            { k: "clockBold", t: "bool", label: "Bold" },
            { k: "clockSize", t: "num", label: "Size", from: 11, to: 24, step: 1, unit: " px" },
            { k: "dateFormat", t: "choice", label: "Date format", options: [["ddd d MMM", "Sat 19 Sep"], ["d MMMM", "19 September"], ["dd.MM.yyyy", "19.09.2026"], ["yyyy-MM-dd", "2026-09-19"], ["M/d", "9/19"]] } ] },
        { name: "Behaviour", items: [
            { k: "barVisibility", t: "choice", label: "Windows", options: [["always", "Never touch it"], ["dodge", "Hide under them"], ["below", "Go below it"]] },
            { k: "quietWhenBusy", t: "bool", label: "Quiet during games" } ] },
        // #7: the bar's look per state, like Plasma's adaptive panel but every value is yours
        { name: "Touched", items: [
            { k: "barTouchedOpacity", t: "num", label: "Opacity when a window touches it", from: 0.1, to: 1, step: 0.01, pct: true },
            { k: "barTouchedBlur", t: "bool", label: "Blur" },
            { k: "barTouchedWidth", t: "choice", label: "Width", options: [["keep", "Keep"], ["fill", "Full width"]] },
            { k: "barTouchedCorners", t: "choice", label: "Corners", options: [["round", "Round"], ["square", "Square"]] } ] },
        { name: "Maximised", items: [
            { k: "barMaximizedMode", t: "choice", label: "A maximised window on this screen", options: [["touched", "Same as touched"], ["custom", "Its own look"]] },
            { k: "barMaximizedOpacity", t: "num", label: "Opacity", from: 0.1, to: 1, step: 0.01, pct: true, when: "barMaximizedMode=custom" },
            { k: "barMaximizedBlur", t: "bool", label: "Blur", when: "barMaximizedMode=custom" },
            { k: "barMaximizedWidth", t: "choice", label: "Width", options: [["keep", "Keep"], ["fill", "Full width"]], when: "barMaximizedMode=custom" },
            { k: "barMaximizedCorners", t: "choice", label: "Corners", options: [["round", "Round"], ["square", "Square"]], when: "barMaximizedMode=custom" } ] },
        { name: "Full-screen", items: [
            { k: "barFullscreenMode", t: "choice", label: "A full-screen window", options: [["hide", "Hide the bar"], ["keep", "Keep it on top"]] },
            { k: "barFullscreenOpacity", t: "num", label: "Opacity", from: 0.1, to: 1, step: 0.01, pct: true, when: "barFullscreenMode=keep" },
            { k: "barFullscreenBlur", t: "bool", label: "Blur", when: "barFullscreenMode=keep" },
            { k: "barFullscreenWidth", t: "choice", label: "Width", options: [["keep", "Keep"], ["fill", "Full width"]], when: "barFullscreenMode=keep" },
            { k: "barFullscreenCorners", t: "choice", label: "Corners", options: [["round", "Round"], ["square", "Square"]], when: "barFullscreenMode=keep" } ] } ]
    readonly property var dockTabs: [
        { name: "Size", items: [
            { k: "dockWidthMode", t: "choice", label: "Width", options: [["fit", "Fit icons"], ["fill", "Fill screen"]] },
            { k: "dockFillMargin", t: "num", label: "Side margin", from: 0, to: 120, step: 1, unit: " px", when: "dockWidthMode=fill" },
            { k: "dockIcon", t: "num", label: "Icon size", from: 28, to: 72, step: 1, unit: " px" },
            { k: "dockCell", t: "num", label: "Icon spacing", from: 40, to: 96, step: 1, unit: " px" },
            { k: "dockHeight", t: "num", label: "Height", from: 40, to: 96, step: 1, unit: " px" },
            { k: "dockRadius", t: "num", label: "Corners", from: 0, to: 40, step: 1, unit: " px" },
            { k: "dockGap", t: "num", label: "Gap to the edge", from: 0, to: 40, step: 1, unit: " px" } ] },
        { name: "Glass", items: [
            { k: "dockBlur", t: "bool", label: "Blur behind" },
            { k: "dockTintAlpha", t: "num", label: "Tint", from: 0, to: 0.95, step: 0.01, pct: true },
            { k: "dockRimAlpha", t: "num", label: "Edge line", from: 0, to: 0.5, step: 0.01, pct: true },
            { k: "dockSheen", t: "num", label: "Top sheen", from: 0, to: 0.3, step: 0.005, pct: true },
            { k: "dockShadow", t: "num", label: "Shadow", from: 0, to: 1, step: 0.01, pct: true },
            { k: "hazeStrength", t: "num", label: "Colour haze", from: 0, to: 1, step: 0.01, pct: true } ] },
        { name: "Icons", items: [
            { k: "dockMagnify", t: "num", label: "Hover zoom", from: 1, to: 1.8, step: 0.01, mult: true },
            { k: "dockSpotlight", t: "bool", label: "Hover light" },
            { k: "dockIndicators", t: "bool", label: "Running pills" },
            { k: "dockBadges", t: "bool", label: "Badges" },
            { k: "dockHop", t: "bool", label: "Launch hop" },
            { k: "launcherIcon", t: "choice", label: "Launcher icon", options: [["start-here-kde-symbolic", "KDE"], ["view-app-grid-symbolic", "Grid"], ["application-menu-symbolic", "Menu"], ["search-symbolic", "Search"], ["starred-symbolic", "Star"]] } ] },
        { name: "Behaviour", items: [
            { k: "dockVisibility", t: "choice", label: "Windows", options: [["always", "Never touch it"], ["dodge", "Hide under them"], ["below", "Go below it"]] },
            { k: "dockPreviews", t: "bool", label: "Window previews" },
            { k: "dockPreviewDelay", t: "num", label: "Preview delay", from: 0, to: 1500, step: 20, unit: " ms", when: "dockPreviews=true" } ] },
        { name: "Touched", items: [
            { k: "dockTouchedOpacity", t: "num", label: "Opacity when a window touches it", from: 0.1, to: 1, step: 0.01, pct: true },
            { k: "dockTouchedBlur", t: "bool", label: "Blur" } ] },
        { name: "Maximised", items: [
            { k: "dockMaximizedMode", t: "choice", label: "A maximised window on this screen", options: [["touched", "Same as touched"], ["custom", "Its own look"]] },
            { k: "dockMaximizedOpacity", t: "num", label: "Opacity", from: 0.1, to: 1, step: 0.01, pct: true, when: "dockMaximizedMode=custom" },
            { k: "dockMaximizedBlur", t: "bool", label: "Blur", when: "dockMaximizedMode=custom" } ] },
        { name: "Full-screen", items: [
            { k: "dockFullscreenMode", t: "choice", label: "A full-screen window", options: [["hide", "Hide the dock"], ["keep", "Keep it on top"]] },
            { k: "dockFullscreenOpacity", t: "num", label: "Opacity", from: 0.1, to: 1, step: 0.01, pct: true, when: "dockFullscreenMode=keep" },
            { k: "dockFullscreenBlur", t: "bool", label: "Blur", when: "dockFullscreenMode=keep" } ] } ]
    function keysOf(tabs, extra) { const out = extra.slice(); for (const t of tabs) for (const i of t.items) if (["cornerRadius", "levelMeter", "quietWhenBusy"].indexOf(i.k) < 0) out.push(i.k); return out }
    function met(when) { if (!when) return true; const p = when.split("="); return String(Config[p[0]]) === p[1] }
    function text(item, v) { return item.pct ? Math.round(v * 100) + " %" : item.mult ? Number(v).toFixed(2) + "×" : Math.round(v) + (item.unit || "") }

    // ---- one option
    component PillBtn: Rectangle { id: pb; property string label; property bool primary: false; signal tapped()
        width: pbt.implicitWidth + 30; height: 32; radius: 16; anchors.verticalCenter: parent.verticalCenter
        color: primary ? es.accent : Qt.rgba(1, 1, 1, pbh.hovered ? 0.16 : 0.09); Behavior on color { ColorAnimation { duration: Config.quick } }
        Text { id: pbt; anchors.centerIn: parent; text: pb.label; color: "white"; font.pixelSize: 12; font.weight: pb.primary ? Font.DemiBold : Font.Normal }
        HoverHandler { id: pbh; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: pb.tapped() } }
    component Option: Item { id: op; required property var modelData
        readonly property var cur: Config[modelData.k]
        visible: es.met(modelData.when); width: visible ? (modelData.t === "choice" ? ch.implicitWidth : 188) : 0; height: 50
        Text { id: lab; text: op.modelData.label; color: Qt.rgba(1, 1, 1, 0.72); font.pixelSize: 12 }
        Text { visible: op.modelData.t === "num"; anchors.right: parent.right; text: op.modelData.t === "num" ? es.text(op.modelData, sl.shown) : ""; color: "white"; font.pixelSize: 12; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
        GlassSlider { id: sl; visible: op.modelData.t === "num"; y: 22; width: parent.width; from: op.modelData.from || 0; to: op.modelData.to || 1; step: op.modelData.step || 0
            value: op.modelData.t === "num" ? Number(op.cur) : 0
            onMoved: v => es.put(op.modelData.k, op.modelData.step >= 1 ? Math.round(v) : Number(v.toFixed(3)), false)
            onCommitted: v => es.put(op.modelData.k, op.modelData.step >= 1 ? Math.round(v) : Number(v.toFixed(3)), true) }
        GlassSwitch { visible: op.modelData.t === "bool"; y: 22; checked: op.modelData.t === "bool" && !!op.cur; onToggled: on => es.put(op.modelData.k, on, true) }
        Row { id: ch; visible: op.modelData.t === "choice"; y: 21; spacing: 5
            Repeater { model: op.modelData.t === "choice" ? op.modelData.options : []
                Rectangle { id: seg; required property var modelData; readonly property bool on: String(op.cur) === modelData[0]
                    width: st.implicitWidth + 20; height: 25; radius: 12.5; color: on ? es.accent : Qt.rgba(1, 1, 1, sh.hovered ? 0.14 : 0.08); Behavior on color { ColorAnimation { duration: Config.quick } }
                    Text { id: st; anchors.centerIn: parent; text: seg.modelData[1]; color: "white"; font.pixelSize: 11; font.weight: seg.on ? Font.DemiBold : Font.Normal }
                    HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: es.put(op.modelData.k, seg.modelData[0], true) } } } } }

    // ---- a strip: title, tabs, the tab's options, and (bar) the shelf of widgets that are not placed
    component Strip: Rectangle { id: strip
        property string title; property string hint; property var tabs: []; property int tab: 0; property var shelf: []
        signal shelfTapped(string name)
        radius: 26; color: Qt.rgba(0.07, 0.08, 0.11, 0.55); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20)
        width: Math.min(es.width - 80, 1180); height: body.y + body.height + 18
        opacity: es.show; onHeightChanged: regions.restart(); onYChanged: regions.restart()
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Text { x: 26; y: 17; text: strip.title; color: "white"; font.pixelSize: 15; font.weight: Font.DemiBold }
        Text { x: 26; y: 39; text: strip.hint; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11 }
        Row { anchors.right: parent.right; anchors.rightMargin: 22; y: 16; spacing: 6
            Repeater { model: strip.tabs
                Rectangle { id: tb; required property var modelData; required property int index; readonly property bool on: strip.tab === index
                    width: tt.implicitWidth + 26; height: 28; radius: 14; color: on ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, th.hovered ? 0.10 : 0.04); Behavior on color { ColorAnimation { duration: Config.quick } }
                    Text { id: tt; anchors.centerIn: parent; text: tb.modelData.name; color: "white"; opacity: tb.on ? 1 : 0.75; font.pixelSize: 12; font.weight: tb.on ? Font.DemiBold : Font.Normal }
                    HoverHandler { id: th; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: strip.tab = tb.index } } } }
        Column { id: body; x: 26; y: 66; width: parent.width - 52; spacing: 10
            Flow { width: parent.width; spacing: 30
                Repeater { model: strip.tabs.length ? strip.tabs[strip.tab].items : []; Option {} } }
            // (a Flow, not a Row: with the tile widgets the shelf grew past the strip's edge, 2026-09-23)
            Flow { visible: strip.shelf.length > 0; width: parent.width; spacing: 8
                Text { text: "Add"; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 12; height: 27; verticalAlignment: Text.AlignVCenter }
                Repeater { model: strip.shelf
                    Rectangle { id: sc; required property string modelData; height: 27; width: sct.implicitWidth + 40; radius: 13.5; color: Qt.rgba(1, 1, 1, sch.hovered ? 0.12 : 0.04); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35)
                        Text { id: sct; x: 12; anchors.verticalCenter: parent.verticalCenter; text: Config.barWidgetNames[sc.modelData] || sc.modelData; color: "white"; font.pixelSize: 12 }
                        Rectangle { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: es.accent
                            Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 12; font.weight: Font.Bold } }
                        HoverHandler { id: sch; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: strip.shelfTapped(sc.modelData) } } } } } }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.36 * es.show) }        // the dim (the bar and dock windows draw above it)
    Item { id: keys; anchors.fill: parent; focus: true; Keys.onPressed: e => { if (e.key === Qt.Key_Escape) { es.done(); e.accepted = true } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons } }

    readonly property var unplaced: { const all = Object.keys(Config.barWidgetNames); return all.filter(n => Config.barLeft.indexOf(n) < 0 && Config.barCenter.indexOf(n) < 0 && Config.barRight.indexOf(n) < 0) }
    Strip { id: barStrip; anchors.horizontalCenter: parent.horizontalCenter; y: es.barHole.y + es.barHole.height + 26 - (1 - es.show) * 14
        title: "Top bar"; hint: "Drag a widget to move it  ·  × takes it off  ·  drag the ends to resize"; tabs: es.barTabs; shelf: es.unplaced
        onShelfTapped: name => { const left = ["desktop", "workspaces", "tray", "title"].indexOf(name) >= 0, centre = ["clock", "date"].indexOf(name) >= 0
            const key = left ? "barLeft" : centre ? "barCenter" : "barRight"; const l = Config[key].slice(); if (left || centre) l.push(name); else l.unshift(name); es.put(key, l, true) } }
    Strip { id: dockStrip; anchors.horizontalCenter: parent.horizontalCenter; y: es.dockHole.y - height - 26 + (1 - es.show) * 14
        title: "Dock"; hint: "Drag icons to reorder  ·  × unpins  ·  right-click an app to pin it"; tabs: es.dockTabs }

    // ---- Screens: which screen shows what. Only with more than one screen. The primary screen (Plasma's, or the one made
    // primary here) has the bar and the dock unless switched off; the others start with the wallpaper only.
    Rectangle { id: screensStrip; visible: Qt.application.screens.length > 1; anchors.horizontalCenter: parent.horizontalCenter
        y: pill.y - height - 14; radius: 26                                  // just above the pill, between the two strips
        width: Math.min(es.width - 80, 1180); height: sbody.y + sbody.height + 18
        color: Qt.rgba(0.07, 0.08, 0.11, 0.55); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20); opacity: es.show
        onHeightChanged: regions.restart(); onYChanged: regions.restart()
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Text { x: 26; y: 17; text: "Screens"; color: "white"; font.pixelSize: 15; font.weight: Font.DemiBold }
        Text { x: 26; y: 39; text: "Each screen shows its wallpaper. Choose which ones also get the bar and the dock, and which one is the primary (popups and shortcuts open there)."; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11 }
        Column { id: sbody; x: 26; y: 66; width: parent.width - 52; spacing: 8
            Repeater { model: Qt.application.screens
                Row { id: sr; required property var modelData; spacing: 18; height: 32
                    readonly property string sname: modelData.name
                    readonly property bool isPrimary: sname === Shell.primaryScreenName
                    readonly property var ch: (Config.get("screens", {}) || {})[sname] || {}
                    function setChoice(key, on) { const all = Object.assign({}, Config.get("screens", {}) || {}); const mine = Object.assign({}, all[sname] || {}); mine[key] = on; all[sname] = mine; Shell.saveConfigKey("screens", all) }
                    Text { width: 300; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; color: "white"; font.pixelSize: 13
                        text: sr.sname + "  ·  " + sr.modelData.width + " × " + sr.modelData.height + (sr.isPrimary ? "  ·  primary" : "") }
                    Row { spacing: 8; anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Bar"; color: Qt.rgba(1, 1, 1, 0.75); font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        GlassSwitch { checked: sr.ch.bar !== undefined ? !!sr.ch.bar : sr.isPrimary; onToggled: on => sr.setChoice("bar", on) } }
                    Row { spacing: 8; anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Dock"; color: Qt.rgba(1, 1, 1, 0.75); font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        GlassSwitch { checked: sr.ch.dock !== undefined ? !!sr.ch.dock : sr.isPrimary; onToggled: on => sr.setChoice("dock", on) } }
                    PillBtn { visible: !sr.isPrimary; label: "Make primary"; onTapped: Shell.saveConfigKey("primaryScreen", sr.sname) } } } } }

    Rectangle { id: pill; anchors.horizontalCenter: parent.horizontalCenter; radius: height / 2
        y: Math.round((barStrip.y + barStrip.height + dockStrip.y - height) / 2) + (screensStrip.visible ? Math.round((screensStrip.height + 14) / 2) : 0)
        width: pr.implicitWidth + 44; height: 56; color: Qt.rgba(0.07, 0.08, 0.11, 0.55); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20); opacity: es.show
        onYChanged: regions.restart(); onWidthChanged: regions.restart()
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Row { id: pr; anchors.centerIn: parent; spacing: 12
            Text { text: "Editing the desktop"; color: "white"; font.pixelSize: 14; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter; rightPadding: 8 }
            PillBtn { label: "Reset bar"; onTapped: Shell.removeConfigKeys(es.keysOf(es.barTabs, ["barLeft", "barCenter", "barRight"])) }
            PillBtn { label: "Reset dock"; onTapped: Shell.removeConfigKeys(es.keysOf(es.dockTabs, [])) }
            PillBtn { label: "More settings…"; onTapped: es.moreSettings() }
            PillBtn { label: "Done"; primary: true; onTapped: es.done() } } }
}
