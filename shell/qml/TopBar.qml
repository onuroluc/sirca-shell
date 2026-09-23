// The top bar: one surface holding the bar and the lobes that grow out of it. Each lobe hosts a real Plasma applet in
// its full form (Kickoff, the digital clock's calendar, Glass Control); the tray sits in the bar in its compact form.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import QtQuick.Layouts
import SircaShell
import "Glass"

Surface {
    id: bar
    edge: "top"
    readonly property int gap: Config.barGap
    readonly property int barH: Config.barHeight
    readonly property int headroom: 40
    // ---- width: scaled to the monitor, the whole screen, as wide as the widgets need, or a fixed number (bar.barWMode)
    readonly property int screenW: Screen.width > 0 ? Screen.width : Config.screenWidth
    readonly property int fitW: Math.round(Math.max(480, Math.min(screenW - 16, 2 * Math.max(barContent.leftW, barContent.rightW) + barContent.centerW + 56)))
    // (barWMode was read but never declared until 2026-09-23, so "fill" and "fit" silently behaved as the custom width)
    readonly property string barWMode: Config.barWidthMode
    readonly property int barW: bar.barWMode === "fill" ? screenW - 2 * Config.barFillMargin
                              : bar.barWMode === "fit" ? fitW
                              : bar.barWMode === "auto" ? Math.min(screenW, Config.barWidthAutoFor(screenW))
                              : Math.min(screenW, Config.barWidth)
    property bool editing: false                // edit mode: widgets become chips (see the edit overlay in barContent)
    signal editRequested()
    readonly property int sidePad: Math.max(0, Math.min(32, Math.floor((screenW - barW) / 2)))   // room for the shadow left/right of the bar
    strut: gap + barH + gap
    slideMax: gap + barH + 44                  // far enough that the shadow leaves the screen too
    readonly property real topY: gap - slide    // everything hangs off this, so the whole shape slides as one
    edgeStrip: Qt.rect(sidePad, 0, bar.barW, 0)
    holdOpen: openLobe !== "" || cardCount > 0 || clockBox.osdOn || editing
    dodge: Config.barDodge
    blur: Config.barBlur

    property bool showingDesktop: false
    property string activeTitle: ""
    property string activeApp: ""
    property var activeIcon
    // Keyboard: none while the bar is just a bar (an on-demand layer surface gets focused when it maps and on every click,
    // which takes focus away from the app you are in and leaves no window 'active'); on-demand only while something that
    // may need typing is open (tray popups, quick settings, a notification's reply field).
    readonly property bool wantsKeys: openLobe !== "" || cardCount > 0
    // a lobe takes the keyboard and closes when it loses it (Surface.popupFocus); notification cards only make the bar
    // focusable on demand (a reply field), they must never pull the keyboard away from what you are typing in
    popupFocus: openLobe !== ""
    restingKeyboardMode: cardCount > 0 ? "ondemand" : "none"
    onFocusLost: openLobe = ""
    property var recorder: null                // Main's Recorder: the bar shows a pill while it records
    signal showDesktopRequested()
    property bool busy: false                  // a full-screen window or a game has focus: notifications do not pop up (Config.quietWhenBusy)
    property string openLobe: ""             // "" | "tray" | "clock" | "gear" | "media" | "notif" | "disks" | "system"  (the launcher lives in the dock)
    readonly property alias notifications: notifCenter   // Main's "notif-clear" shortcut reaches clearAll() through this
    readonly property string clockFormat: (Config.clock24h ? "HH:mm" : "h:mm") + (Config.clockSeconds ? ":ss" : "") + (Config.clock24h ? "" : " AP")
    function clockString() { const d = new Date(); return (Config.clockDate ? Qt.formatDate(d, Config.dateFormat) + "   " : "") + Qt.formatTime(d, clockFormat) }
    function toggle(name) { openLobe = (openLobe === name) ? "" : name }
    // quick settings, opened on its Sound page (the privacy widget): the panel is built on demand if it is not yet
    function openSoundPage() { warm = true; const q = controlLoader.item; if (q && q.page !== undefined) q.page = "sound"; openLobe = "gear" }

    // a hosted applet's own preferred size, clamped; fallbacks until it has loaded
    function prefW(host, fallback) { const f = (host && host.appletItem) ? host.appletItem.fullRepresentationItem : null; return (f && f.Layout && f.Layout.preferredWidth > 0) ? Math.min(f.Layout.preferredWidth, 900) + 2 * Config.lobePad : fallback + 2 * Config.lobePad }
    function prefH(host, fallback) { const f = (host && host.appletItem) ? host.appletItem.fullRepresentationItem : null; return (f && f.Layout && f.Layout.preferredHeight > 0) ? Math.min(f.Layout.preferredHeight + 2 * Config.lobePad, Config.sheetHeight) : fallback }

    // calendar: our own panel, or the hosted digital clock applet as a fallback (Config.nativeCalendar off)
    readonly property real clockW: Config.nativeCalendar ? calendarPanel.implicitWidth + 2 * Config.lobePad : prefW(hostedClockLoader.item, 560)
    readonly property real clockFullH: Config.nativeCalendar ? calendarPanel.implicitHeight + 2 * Config.lobePad : prefH(hostedClockLoader.item, 420)
    // heavy popup content (quick settings: ~50 ms) is built shortly after start, or at the first open, not in the start-up path
    property bool warm: false
    Timer { interval: 1500; running: true; onTriggered: bar.warm = true }
    // quick settings: our own panel (qml/control), or the hosted applet as a fallback (Config.nativeControl off)
    readonly property Item nativeControl: Config.nativeControl ? controlLoader.item : null
    readonly property real gearW: nativeControl ? nativeControl.implicitWidth + 2 * Config.lobePad : prefW(hostedControlLoader.item, Config.sheetWidth)
    readonly property real gearFullH: nativeControl ? Math.min(nativeControl.implicitHeight + 2 * Config.lobePad, Config.sheetHeight) : prefH(hostedControlLoader.item, Config.sheetHeight)

    // tray lobe: the tray's own expanded view (hidden icons, or the popup of a tray item), adopted from onur.glasstray
    // Native tray (Config.nativeTray): the lobe under an icon is that item's MENU (TrayMenu). The hosted Plasma tray is
    // still loaded, invisibly, only because the notification cards applet lives inside it (until the native notification
    // server exists). With nativeTray off the hosted tray is shown and the lobe is its expanded view, as before.
    QtObject { id: noTray; property var appletItem: null; property real x: 50; property real width: 0 }
    readonly property var tray: hostedTrayLoader.item ? hostedTrayLoader.item : noTray
    readonly property Item trayView: (!Config.nativeTray && tray.appletItem) ? tray.appletItem.glassExpandedItem : null
    readonly property bool trayWantsOpen: (!Config.nativeTray && tray.appletItem) ? tray.appletItem.glassExpanded : false
    readonly property real trayW: Config.nativeTray ? trayMenu.implicitWidth + 2 * Config.lobePad : 440
    readonly property real trayFullH: Config.nativeTray ? Math.min(trayMenu.implicitHeight + 2 * Config.lobePad, 560) : 460
    property real trayMenuX: sidePad + 66                     // frozen while open: under the clicked icon
    readonly property real trayX: Config.nativeTray ? trayMenuX : sidePad + 66
    function openTrayMenuAt(n) { nativeTray.requestMenuAt(n) }
    function openTrayMenu(item, centerX) {
        if (openLobe === "tray" && nativeTray.openItem === item) { openLobe = ""; return }
        // A lobe must stay clear of the bar's rounded ends: the outline needs the straight part of the bar's bottom edge
        // plus room for the fillet on each side (half the bar height + fillet 14 + a little air). Closer than that, the
        // left rim vanished and the bottom-left corner ran off on its own radius.
        const clear = Math.ceil(barH / 2) + 14 + 10;
        trayMenuX = Math.max(sidePad + clear, Math.min(sidePad + bar.barW - clear - trayW, barRect.x + nativeTray.x + centerX - trayW / 2));
        nativeTray.openItem = item; trayMenu.show(item); openLobe = "tray" }
    property real trayH: openLobe === "tray" ? trayFullH : 0
    Behavior on trayH { Spring {} }
    onTrayWantsOpenChanged: { if (trayWantsOpen) openLobe = "tray"; else if (openLobe === "tray") openLobe = "" }
    onOpenLobeChanged: { if (openLobe !== "") { warm = true; refreshAnchors() } if (openLobe !== "tray") { nativeTray.openItem = null; if (tray.appletItem && tray.appletItem.glassExpanded) tray.appletItem.glassCollapse() } }
    function adoptTrayView() {
        if (!trayView) return;
        if (trayView.parent !== trayContent) trayView.parent = trayContent;
        // fixed size at the lobe's FULL height inside a container that is only as tall as the lobe right now: the content
        // is revealed and swallowed by the moving edge like in the other lobes (anchors.fill made it pop in place)
        trayView.anchors.fill = undefined; const p = Config.lobePad + 2;
        trayView.x = p; trayView.y = p; trayView.width = trayW - 2 * p; trayView.height = trayFullH - 2 * p; trayView.visible = true;
    }
    onTrayViewChanged: adoptTrayView()
    onTrayHChanged: if (trayH > 1) adoptTrayView()
    // notification cards: the forked notifications applet (nested in the tray) parents its popups into one Column,
    // which we adopt into a lobe at the right end of the bar; the lobe is as tall as the cards and folds when empty
    property Item notifItem: null
    readonly property Item cardsItem: Config.nativeNotifications ? nativeCards : (notifItem ? notifItem.glassCardsItem : null)
    readonly property int cardCount: (openLobe === "notif") ? 0 : (Config.nativeNotifications ? nativeCards.count : (notifItem ? notifItem.glassCardCount : 0))   // no popups over the open history
    // (the hosted applet appears a few seconds after start-up at most; after 20 tries = 30 s it is not coming, so the poll stops)
    Timer { running: !bar.notifItem && !Config.nativeNotifications && tries < 20; interval: 1500; repeat: true; property int tries: 0
        onTriggered: { bar.notifItem = Shell.appletItem("onur.glassnotifications"); tries++ } }
    onCardsItemChanged: if (cardsItem && !Config.nativeNotifications) { cardsItem.parent = cardsContent; cardsItem.x = Config.lobePad; cardsItem.y = Config.lobePad; cardsItem.visible = true }
    readonly property real cardsW: cardsItem ? cardsItem.width + 2 * Config.lobePad : 380
    readonly property real cardsFullH: cardCount > 0 && cardsItem ? Math.min(cardsItem.height + 2 * Config.lobePad, Config.sheetHeight) : 0
    property real cardsH: cardsFullH
    readonly property bool debug: Qt.application.arguments.indexOf("--debug") >= 0
    onNotifItemChanged: if (debug) console.log("notifItem", notifItem, cardsItem)
    onCardCountChanged: if (debug) console.log(Date.now() % 100000, "cardCount", cardCount, "cards h", cardsItem ? cardsItem.height : -1, "w", cardsItem ? cardsItem.width : -1, "children", cardsItem ? cardsItem.children.length : -1)
    property real cardsMaskH: 0                   // blur/input mask height: the last real height, so it does not change per frame while folding
    onCardsFullHChanged: if (cardsFullH > 0) cardsMaskH = cardsFullH
    Behavior on cardsH { Spring {} }
    readonly property bool cardsUp: cardsH > 1
    // right-aligned like the gear lobe; steps aside to its left while that one is open
    property real cardsX: sidePad + bar.barW - 40 - cardsW - (gearH > 1 ? gearW + 44 : 0) - (notifH > 1 ? notifW + 44 : 0) - (mediaH > 1 ? Math.max(0, sidePad + bar.barW - 40 - mediaAnchorX + 4) : 0)
    Behavior on cardsX { Spring {} }
    readonly property rect cardsRect: Qt.rect(cardsX, topY + barH, cardsW, cardsH)
    property real clockH: openLobe === "clock" ? clockFullH : 0
    readonly property real notifW: notifCenter.implicitWidth + 2 * Config.lobePad
    readonly property real notifFullH: Math.min(notifCenter.implicitHeight + 2 * Config.lobePad, Config.sheetHeight + 40)
    property real notifH: openLobe === "notif" ? notifFullH : 0
    Behavior on notifH { Spring {} }
    readonly property bool notifUp: notifH > 1
    // Lobes hang under the widget that opens them, kept clear of the bar's rounded ends; the position is taken when the
    // lobe opens (and whenever the layout changes while everything is closed), so it never slides under the pointer.
    function under(item, w) { const c = barRect.x + (item ? item.x + item.width / 2 : bar.barW / 2);
        return Math.max(sidePad + Math.ceil(barH / 2) + 24, Math.min(sidePad + bar.barW - 40 - w, c - w / 2)) }
    property real notifX: sidePad + bar.barW - notifW - 40
    property real gearX: sidePad + bar.barW - gearW - 40
    property real clockX: sidePad + (bar.barW - clockW) / 2
    function refreshAnchors() { notifX = under(bell, notifW); gearX = under(gear, gearW); clockX = under(clockBox, clockW); disksX = under(disksBtn, disksW); sysmonX = under(sysW, sysmonW) }
    onNotifWChanged: if (openLobe !== "notif") notifX = under(bell, notifW); else notifX = Math.min(notifX, sidePad + bar.barW - 40 - notifW)
    onGearWChanged: gearX = under(gear, gearW)
    onClockWChanged: clockX = under(clockBox, clockW)
    onBarWChanged: refreshAnchors()
    onTopYChanged: island.layoutTick++
    readonly property rect notifRect: Qt.rect(notifX, topY + barH, notifW, notifH)
    // removable disks lobe (RemovableMedia): only there while a removable drive is plugged in
    readonly property real disksW: disksPanel.implicitWidth + 2 * Config.lobePad
    readonly property real disksFullH: disksPanel.implicitHeight + 2 * Config.lobePad
    property real disksH: openLobe === "disks" ? disksFullH : 0
    Behavior on disksH { Spring {} }
    readonly property bool disksUp: disksH > 1
    property real disksX: sidePad + bar.barW - disksW - 40
    onDisksWChanged: disksX = under(disksBtn, disksW)
    readonly property rect disksRect: Qt.rect(disksX, topY + barH, disksW, disksH)
    // system monitor lobe (SysMon.qml) under the CPU / memory widget; its readers only run while it is open
    readonly property real sysmonW: sysmonPanel.implicitWidth + 2 * Config.lobePad
    readonly property real sysmonFullH: Math.min(sysmonPanel.implicitHeight + 2 * Config.lobePad, Config.sheetHeight)
    property real sysmonH: openLobe === "system" ? sysmonFullH : 0
    Behavior on sysmonH { Spring {} }
    readonly property bool sysmonUp: sysmonH > 1
    property real sysmonX: sidePad + bar.barW - sysmonW - 40
    readonly property rect sysmonRect: Qt.rect(sysmonX, topY + barH, sysmonW, sysmonH)
    property real gearH: openLobe === "gear" ? gearFullH : 0
    Behavior on clockH { Spring {} }
    Behavior on gearH { Spring {} }
    // now-playing lobe: native panel under the media widget, kept clear of the bar's right end
    readonly property real mediaW: (mediaPanel.item ? mediaPanel.item.implicitWidth : 0) + 2 * Config.lobePad
    readonly property real mediaFullH: (mediaPanel.item ? mediaPanel.item.implicitHeight : 0) + 2 * Config.lobePad
    property real mediaH: openLobe === "media" ? mediaFullH : 0
    Behavior on mediaH { Spring {} }
    readonly property bool mediaUp: mediaH > 1
    readonly property bool mediaAvailable: island.hasTrack
    property real mediaAnchorX: sidePad + bar.barW - 40 - mediaW        // frozen while open, so the lobe does not slide when the widget resizes
    function placeMedia() { const c = barRect.x + island.x + island.width / 2; mediaAnchorX = Math.max(sidePad + Math.ceil(barH / 2) + 24, Math.min(sidePad + bar.barW - 40 - mediaW, c - mediaW / 2)) }
    readonly property rect mediaRect: Qt.rect(mediaAnchorX, topY + barH, mediaW, mediaH)

    readonly property rect barRect: Qt.rect(sidePad, topY, bar.barW, barH)
    readonly property rect trayRect: Qt.rect(trayX, topY + barH, trayW, trayH)
    readonly property rect clockRect: Qt.rect(clockX, topY + barH, clockW, clockH)
    readonly property rect gearRect: Qt.rect(gearX, topY + barH, gearW, gearH)

    width: bar.barW + 2 * sidePad
    height: gap + barH + Config.sheetHeight + headroom
    title: "Sirca Shell — top bar"

    LobeShape {
        id: shape
        anchors.fill: parent
        bar: bar.barRect
        reach: bar.polygon                 // the fully grown outline: the shadow layers are sized once per open/close, not per frame
        tint: Config.barTint; rim: Qt.rgba(1, 1, 1, Config.barRimAlpha * Config.mixn(1, 3.2)); sheen: Config.barSheen * Config.mixn(1, 2.5); shadowStrength: Config.barShadow   // literal-ok: the rim is white light in both modes
        lobes: [{ x: trayRect.x, w: trayRect.width, h: trayH }, { x: clockRect.x, w: clockRect.width, h: clockH }, { x: gearRect.x, w: gearRect.width, h: gearH }, { x: notifRect.x, w: notifRect.width, h: notifH }, { x: disksRect.x, w: disksRect.width, h: disksH }, { x: sysmonRect.x, w: sysmonRect.width, h: sysmonH }, { x: mediaRect.x, w: mediaRect.width, h: mediaH }, { x: cardsRect.x, w: cardsRect.width, h: cardsH }]
        onPolygonChanged: bar.pushShape()
    }
    // blur region + input mask: the fully grown outline of whatever is open (or still closing)
    // (bound to booleans and constants only, so it re-evaluates when a lobe opens or has finished closing, not per frame)
    readonly property bool trayUp: trayH > 1
    readonly property bool clockUp: clockH > 1
    readonly property bool gearUp: gearH > 1
    polygon: shape.polygonFor(Qt.rect(sidePad, gap, bar.barW, barH), [
        { x: trayX, w: trayW, h: trayUp ? trayFullH + Config.bounceRoom : 0 },
        { x: clockX, w: clockW, h: clockUp ? clockFullH + Config.bounceRoom : 0 },
        { x: gearX, w: gearW, h: gearUp ? gearFullH + Config.bounceRoom : 0 },
        { x: notifX, w: notifW, h: notifUp ? notifFullH + Config.bounceRoom : 0 },
        { x: disksX, w: disksW, h: disksUp ? disksFullH + Config.bounceRoom : 0 },
        { x: sysmonX, w: sysmonW, h: sysmonUp ? sysmonFullH + Config.bounceRoom : 0 },
        { x: mediaAnchorX, w: mediaW, h: mediaUp ? mediaFullH + Config.bounceRoom : 0 },
        { x: cardsX, w: cardsW, h: cardsUp ? cardsMaskH + Config.bounceRoom : 0 }], false, 14)
    // The Glass KWin effect draws its bevel/outline from the same boxes (org.kde.KWin /Glass, effect fork branch "lobes")
    function pushShape() {
        if (!Config.barBlur) { Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "clearLobes", "sii", ["sirca-shell", bar.width, bar.height]); return }
        let boxes = [barRect.x, barRect.y, barRect.width, barRect.height];
        // lobe boxes reach up into the bar: their own rounded top corners must hide inside it, or they notch the junction
        const up = Math.min(Config.cornerRadius, barH - 15);
        for (const r of [trayRect, clockRect, gearRect, notifRect, disksRect, sysmonRect, mediaRect, cardsRect]) if (r.height > 1) boxes = boxes.concat([r.x, r.y - up, r.width, r.height + up]);
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "setLobes", "siivdd", ["sirca-shell", bar.width, bar.height, boxes, Config.cornerRadius, shape.fillet * 1.17]);
    }
    Component.onCompleted: {
        Shell.setKeyboardMode(bar, "none");
        pushShape();
        for (const n of ["clock", "gear", "media", "notif", "system"]) if (Qt.application.arguments.indexOf("--open-" + n) >= 0) openLobe = n;
        if (Qt.application.arguments.indexOf("--open-tray") >= 0) openTrayLater.start();
        if (Qt.application.arguments.indexOf("--test-showdesktop") >= 0) sdTest.start();
    }
    onWidthChanged: { pushShape(); island.layoutTick++ }
    onHeightChanged: pushShape()
    Component.onDestruction: Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "clearLobes", "sii", ["sirca-shell", bar.width, bar.height])

    // ---- colour haze, same idea as the dock: a blurred, saturated copy of everything in the bar (tray icons, the focused
    // app's icon, cover art, glyphs, text) lies under the content and inside the glass outline.
    // The haze layer and its mask cover the bar plus the blur's reach (40 px), not the whole surface (which is the bar plus
    // a sheet's worth of lobe room): the haze cannot exist further from the bar than its blur radius anyway. The mask's
    // Shape is shifted back so the outline (in surface coordinates) lands in the right place; mask and layer are the same
    // size, so they line up pixel for pixel. Whole pixels: a layer that changes size is re-allocated.
    readonly property rect hazeRect: { const r = 40; const x = Math.max(0, Math.floor(barContent.x - r)), y = Math.max(0, Math.floor(barContent.y - r))
        return Qt.rect(x, y, Math.max(1, Math.min(Math.ceil(width), Math.ceil(barContent.x + barContent.width + r)) - x), Math.max(1, Math.min(Math.ceil(height), Math.ceil(barContent.y + barContent.height + r)) - y)) }
    Item {
        x: bar.hazeRect.x; y: bar.hazeRect.y; width: bar.hazeRect.width; height: bar.hazeRect.height
        visible: Config.barHazeStrength > 0.01
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: barHazeMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        MultiEffect { x: barContent.x - bar.hazeRect.x; y: barContent.y - bar.hazeRect.y; width: barContent.width; height: barContent.height
            source: barHazeSrc; autoPaddingEnabled: true
            blurEnabled: true; blur: 1.0; blurMax: 40; saturation: Config.dark ? 0.6 : 1.6; brightness: Config.dark ? 0.05 : 0.18
            opacity: Math.min(1, Config.barHazeStrength * 2.2) }
    }
    // What the haze is made of: ONLY the coloured things in the bar (app icons in the tray, the focused app's icon, the cover
    // of what is playing). It used to be a blurred copy of everything, and a blurred monochrome glyph or label is a grey
    // smudge behind every button, dark on light glass.
    Item { id: barHazeSrc; visible: false; x: barContent.x; y: barContent.y; width: barContent.width; height: barContent.height; layer.enabled: true
        ShaderEffectSource { visible: nativeTray.visible; sourceItem: nativeTray.hazeSource; x: nativeTray.x; y: nativeTray.y; width: nativeTray.width; height: nativeTray.height }
        Kirigami.Icon { visible: titleRow.visible && Config.titleIcon && bar.activeTitle !== ""; opacity: titleRow.opacity; x: titleRow.x; y: (parent.height - height) / 2; width: 16; height: 16; source: bar.activeIcon || ""; roundToIconSize: false }
        Image { readonly property point at: { island.x; island.width; return island.coverItem ? island.coverItem.mapToItem(island, 0, 0) : Qt.point(0, 0) }
            visible: island.visible && island.coverUrl !== ""; x: island.x + at.x; y: island.y + at.y; width: 19; height: 19; source: island.coverUrl; sourceSize: Qt.size(76, 76); fillMode: Image.PreserveAspectCrop }
    }
    Item { id: barHazeMask; x: bar.hazeRect.x; y: bar.hazeRect.y; width: bar.hazeRect.width; height: bar.hazeRect.height; visible: false; layer.enabled: true
        Shape { x: -bar.hazeRect.x; y: -bar.hazeRect.y; width: bar.width; height: bar.height; preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: -1; fillColor: "black"; PathSvg { path: shape.pathData } } } }

    // ---- bar content ---------------------------------------------------------------------------
    Item {
        id: barContent
        x: barRect.x; y: barRect.y; width: barRect.width; height: barRect.height
        // ---- layout: three groups (left, centre, right), each an ordered list of widget names from the config. A widget
        // that is in no list is hidden; one that has nothing to show right now (no second desktop, nothing playing) takes
        // no room. Positions are computed here instead of anchoring widgets to each other, so any order works.
        function itemOf(n) { switch (n) { case "desktop": return desk; case "workspaces": return workspaces; case "tray": return Config.nativeTray ? nativeTray : hostedTrayLoader
            case "title": return titleRow; case "clock": return clockBox; case "date": return dateW; case "system": return sysW; case "media": return island; case "bell": return bell; case "gear": return gear
            case "battery": return batteryW; case "mic": return micW; case "privacy": return privacyW; case "keyboard": return keyboardW; case "weather": return weatherW; case "disks": return disksBtn }
            if (n.startsWith("user:")) { for (let i = 0; i < userWidgets.count; ++i) { const it = userWidgets.itemAt(i); if (it && it.name === n.substring(5)) return it } }
            return null }
        function placed(n) { return Config.barLeft.indexOf(n) >= 0 || Config.barCenter.indexOf(n) >= 0 || Config.barRight.indexOf(n) >= 0 }
        function live(n) { if (!placed(n)) return false
            if (n === "workspaces") return workspaces.count > 1; if (n === "media") return island.hasTrack; if (n === "bell") return Config.nativeNotifications
            // widgets that have nothing to say take no room: no battery, nobody recording, nothing private going on, one layout
            if (n === "battery") return batteryW.shown; if (n === "mic") return micW.shown; if (n === "privacy") return privacyW.shown; if (n === "keyboard") return keyboardW.shown
            if (n === "weather") return weatherW.hasData || weatherW.pending; if (n === "disks") return disksPanel.count > 0
            if (n.startsWith("user:")) return userWidgets.count > 0 && !!itemOf(n)   // reads count: the layout re-runs when a widget folder appears
            return true }
        // the title is elastic: last in its group it takes what is left; followed by other widgets it gets a fixed slot
        function slot(n, last) { if (n === "title") return last ? 0 : Config.titleMaxWidth; const it = itemOf(n); return it ? it.width : 0 }
        readonly property var layout: {
            const pos = {}, g = Config.barSpacing, P = Config.barPad, L = Config.barLeft.filter(live), C = Config.barCenter.filter(live), R = Config.barRight.filter(live)
            let c = P; for (let i = 0; i < L.length; ++i) { pos[L[i]] = c; c += slot(L[i], i === L.length - 1) + g } const leftEnd = c
            let cw = 0; for (let i = 0; i < C.length; ++i) cw += slot(C[i], false) + (i ? g : 0)
            let cx = (width - cw) / 2; const centreStart = cx; for (let i = 0; i < C.length; ++i) { pos[C[i]] = cx; cx += slot(C[i], false) + g }
            let r = width - P; for (let i = R.length - 1; i >= 0; --i) { const last = i === R.length - 1; r -= (R[i] === "title" && last) ? Math.min(titleRow.naturalW, Config.titleMaxWidth) : slot(R[i], false); pos[R[i]] = r; r -= g }
            const rightStart = R.length ? r + g : width - P
            // room for the elastic title
            let room = Config.titleMaxWidth
            if (L.length && L[L.length - 1] === "title") room = (C.length ? centreStart : rightStart) - pos["title"] - 28
            pos["title.room"] = Math.max(0, room); pos["left.w"] = leftEnd; pos["centre.w"] = cw; pos["right.w"] = width - rightStart + P
            return pos }
        function at(n) { const v = layout[n]; return v === undefined ? 0 : v }
        // for "fit content" width: what each side needs (the title counted at its natural width, capped)
        readonly property real leftW: { let w = Config.barPad; for (const n of Config.barLeft.filter(live)) w += (n === "title" ? Math.min(titleRow.naturalW, Config.titleMaxWidth) : slot(n, false)) + Config.barSpacing; return w }
        readonly property real rightW: { let w = Config.barPad; for (const n of Config.barRight.filter(live)) w += (n === "title" ? Math.min(titleRow.naturalW, Config.titleMaxWidth) : slot(n, false)) + Config.barSpacing; return w }
        readonly property real centerW: { let w = 0; for (const n of Config.barCenter.filter(live)) w += (n === "title" ? Math.min(titleRow.naturalW, Config.titleMaxWidth) : slot(n, false)) + Config.barSpacing; return w }
        onLayoutChanged: { if (bar.openLobe === "") bar.refreshAnchors(); island.layoutTick++ }   // (the tick: the media island re-maps its meter slot)
        readonly property real contentOpacity: bar.editing ? 0 : 1
        // system tray: the real Plasma applet, compact, hosted in the bar zone (its popups are still Plasma dialogs for now)
        // the tray only publishes a minimum width; anything wider gets spread between its icons
        // show desktop: far left, like on the Plasma bar; glows while the desktop is showing
        Rectangle { visible: desk.visible && Config.barHoverPills; x: desk.x - 8; anchors.verticalCenter: parent.verticalCenter; width: desk.width + 16; height: 27; radius: 13.5; color: Config.fg(dh.hovered && !bar.showingDesktop ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
        GlowIcon { id: desk; visible: barContent.live("desktop") && !bar.editing; x: barContent.at("desktop"); anchors.verticalCenter: parent.verticalCenter; size: Math.round(16 * Config.barIconScale); source: "user-desktop-symbolic"; active: bar.showingDesktop; hovered: dh.hovered
            HoverHandler { id: dh }
            TapHandler { onTapped: bar.showDesktopRequested() } }
        // The hosted Plasma tray is loaded only while something still needs it: its icons (nativeTray off) or the
        // notification cards applet nested in it (nativeNotifications off). With both native, no hosted tray at all.
        // virtual desktops, right after the desktop button (takes no room while there is only one)
        Workspaces { id: workspaces; allowed: barContent.placed("workspaces") && !bar.editing; x: barContent.at("workspaces"); anchors.verticalCenter: parent.verticalCenter }
        readonly property real trayX: at("tray")
        Loader { id: hostedTrayLoader; active: !Config.nativeTray || !Config.nativeNotifications; x: barContent.trayX; y: 0; height: parent.height; visible: !Config.nativeTray && barContent.placed("tray") && !bar.editing
            width: item ? item.width : 0
            sourceComponent: AppletHost { plugin: "onur.glasstray"; zone: "bar"; height: hostedTrayLoader.height
                width: appletItem ? Math.max(appletItem.Layout.minimumWidth, appletItem.Layout.preferredWidth, 24) : 24 } }
        Tray { id: nativeTray; visible: Config.nativeTray && barContent.placed("tray") && !bar.editing; x: barContent.trayX; anchors.verticalCenter: parent.verticalCenter
            onMenuRequested: (item, centerX) => bar.openTrayMenu(item, centerX) }
        // focused window: app icon + title, between the tray and the clock; fades with focus changes, empty on the desktop
        Row { id: titleRow; visible: barContent.placed("title") && !bar.editing; x: barContent.at("title"); anchors.verticalCenter: parent.verticalCenter; spacing: 8
            readonly property real room: barContent.at("title.room")
            readonly property real naturalW: bar.activeTitle !== "" ? titleText.implicitWidth + (Config.titleIcon ? 24 : 0) : 0
            opacity: bar.activeTitle !== "" ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Config.normal } }
            Kirigami.Icon { visible: Config.titleIcon; width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter; source: bar.activeIcon || ""; roundToIconSize: false }
            Text { id: titleText; anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, Math.max(0, titleRow.room - 24)); elide: Text.ElideRight
                text: bar.activeTitle; color: Config.inkDim; font.pixelSize: 13; font.weight: Font.Medium } }
        // Clock pill. Volume / brightness / layout changes (plasmashell's osdService signals) briefly turn it into a meter:
        // the pill widens in place, shows icon + bar + value, then relaxes back to the time.
        // Recording pill, right of the clock: red dot (blinks once a second, in steps: no running animation on this wide
        // surface), elapsed time, stop square. Click anywhere on it to stop. Shows "Saving" while the file is finished.
        Item { id: recPill; readonly property bool on: !!bar.recorder && (bar.recorder.recording || bar.recorder.finishing)
            x: clockBox.x + clockBox.width + 10; anchors.verticalCenter: parent.verticalCenter; height: 27
            width: on ? recRow.implicitWidth + 24 : 0; opacity: on ? 1 : 0; visible: opacity > 0.01; clip: true
            Behavior on width { NumberAnimation { duration: Config.normal; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Config.normal } }
            Rectangle { anchors.fill: parent; radius: 13.5; color: Qt.rgba(229/255, 72/255, 77/255, rh.hovered ? 0.34 : 0.22); border.width: 1; border.color: Qt.rgba(229/255, 72/255, 77/255, 0.55)
                Behavior on color { ColorAnimation { duration: Config.quick } } }
            Row { id: recRow; anchors.centerIn: parent; spacing: 8
                Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 0.30, 0.32, 1)
                    opacity: bar.recorder && bar.recorder.recording && bar.recorder.seconds % 2 === 1 ? 0.35 : 1 }
                Text { anchors.verticalCenter: parent.verticalCenter; color: Config.fgSolid; font.pixelSize: 12; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                    text: !bar.recorder ? "" : (bar.recorder.finishing ? "Saving" : bar.recorder.clock) }
                Rectangle { visible: !!bar.recorder && bar.recorder.recording; width: 9; height: 9; radius: 2; color: Config.fgSolid; opacity: rh.hovered ? 1 : 0.75; anchors.verticalCenter: parent.verticalCenter } }
            HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: if (bar.recorder) bar.recorder.stop() } }
        Item { id: clockBox; visible: barContent.placed("clock") && !bar.editing; x: barContent.at("clock"); height: parent.height
            property bool osdOn: false
            property string osdIcon: ""
            property real osdFrac: -1            // < 0: text-only message
            property string osdLabel: ""
            width: osdOn ? (osdFrac >= 0 ? 300 : Math.max(160, osdMsg.implicitWidth + 64)) : clockText.width + 24
            Behavior on width { Spring {} }
            Timer { id: osdHide; interval: 1700; onTriggered: clockBox.osdOn = false }
            function showOsd(icon, frac, label) { osdIcon = icon; osdFrac = frac; osdLabel = label; osdOn = true; osdHide.restart() }
            // driven locally (our own slider is being dragged): the value is exact and immediate, so the fill does not ease and
            // the echoes of the same changes that arrive over D-Bus a moment later are ignored
            property double localUntil: 0
            readonly property bool local: localTick.running
            Timer { id: localTick; interval: 450 }
            function showLocal(icon, frac) { localUntil = Date.now() + 450; localTick.restart(); showOsd(icon, frac, "") }
            Rectangle { anchors.centerIn: parent; width: parent.width; height: 27; radius: 13.5; color: Config.fg(clockBox.osdOn || bar.openLobe === "clock" ? 0.12 : (ch.hovered ? 0.07 : 0)); Behavior on color { ColorAnimation { duration: Config.quick } } }
            Text { id: clockText; anchors.centerIn: parent; color: Config.ink; font.pixelSize: Config.clockSize; font.weight: Config.clockBold ? Font.Bold : Font.Medium
                opacity: clockBox.osdOn ? 0 : 1; Behavior on opacity { NumberAnimation { duration: Config.quick } }
                Timer { interval: bar.quiet ? 30000 : 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: clockText.text = bar.clockString() } }
            Item { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; clip: true
                opacity: clockBox.osdOn ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Config.quick } }
                GlowIcon { id: osdGlyph; anchors.verticalCenter: parent.verticalCenter; size: 16; source: clockBox.osdIcon; hovered: true }
                Rectangle { id: track; visible: clockBox.osdFrac >= 0; anchors.left: osdGlyph.right; anchors.leftMargin: 10; anchors.right: osdValue.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    height: 6; radius: 3; color: Config.fg(0.16)
                    Rectangle { height: parent.height; radius: 3; color: Config.fg(0.92); width: Math.max(height, parent.width * Math.min(1, Math.max(0, clockBox.osdFrac)))
                        Behavior on width { enabled: !clockBox.local; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } } } }
                Text { id: osdValue; visible: clockBox.osdFrac >= 0; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 34; horizontalAlignment: Text.AlignRight
                    text: Math.round(clockBox.osdFrac * 100) + "%"; color: Config.ink; font.pixelSize: 12; font.weight: Font.DemiBold }
                Text { id: osdMsg; visible: clockBox.osdFrac < 0; anchors.left: osdGlyph.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    text: clockBox.osdLabel; color: Config.ink; font.pixelSize: 13; font.weight: Font.DemiBold } }
            HoverHandler { id: ch }
            TapHandler { onTapped: bar.toggle("clock") }
            Connections { target: Shell
                function onDbusSignal(iface, member, args) {
                    if (iface !== "org.kde.osdService") return;
                    if (Date.now() < clockBox.localUntil) return;                // our own slider is driving the display right now
                    if (member === "osdProgress") clockBox.showOsd(args[0], args[1] / 100, args[3] || "");
                    else if (member === "osdText") clockBox.showOsd(args[0], -1, args[1] || "");
                } }
            Component.onCompleted: { Shell.dbusListen("org.kde.plasmashell", "/org/kde/osdService", "org.kde.osdService", "osdProgress"); Shell.dbusListen("org.kde.plasmashell", "/org/kde/osdService", "org.kde.osdService", "osdText") }
        }
        Rectangle { visible: gear.visible && Config.barHoverPills; x: gear.x - 9; anchors.verticalCenter: parent.verticalCenter; width: gear.width + 18; height: 27; radius: 13.5; color: Config.fg(gh.hovered && bar.openLobe !== "gear" ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
        MediaIsland { id: island; quiet: bar.quiet || (bar.hiddenFully && bar.openLobe === ""); barLeft: Math.floor((bar.screenW - bar.width) / 2); slideY: bar.topY;   /* slid away under a window: nothing to animate */ lobeOpen: bar.openLobe === "media"; onClicked: { if (bar.openLobe !== "media") bar.placeMedia(); bar.toggle("media") }
            onHasTrackChanged: if (!hasTrack && bar.openLobe === "media") bar.openLobe = ""
            allowed: barContent.placed("media") && !bar.editing; x: barContent.at("media"); anchors.verticalCenter: parent.verticalCenter }
        Rectangle { visible: bell.visible && Config.barHoverPills; x: bell.x - 7; anchors.verticalCenter: parent.verticalCenter; width: bell.width + 14; height: 27; radius: 13.5; color: Config.fg(bh.hovered && bar.openLobe !== "notif" ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
        GlowIcon { id: bell; visible: barContent.live("bell") && !bar.editing; x: barContent.at("bell"); anchors.verticalCenter: parent.verticalCenter; size: Math.round(22 * Config.barIconScale)
            source: notifCenter.dnd ? "notifications-disabled-symbolic" : "notifications-symbolic"; active: bar.openLobe === "notif"; hovered: bh.hovered
            HoverHandler { id: bh }
            TapHandler { onTapped: bar.toggle("notif") }
            Rectangle { visible: notifCenter.unread > 0 && bar.openLobe !== "notif"; x: parent.width - 7; y: 0; width: 8; height: 8; radius: 4; color: Config.attention; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.45) } }
        // date and CPU / memory: two plain text widgets
        Text { id: dateW; visible: barContent.placed("date") && !bar.editing; x: barContent.at("date"); anchors.verticalCenter: parent.verticalCenter
            color: Config.ink; font.pixelSize: 13; font.weight: Font.Medium; text: Qt.formatDate(new Date(), Config.dateFormat)
            Timer { interval: 60000; running: dateW.visible; repeat: true; onTriggered: dateW.text = Qt.formatDate(new Date(), Config.dateFormat) } }
        Rectangle { visible: sysW.visible && Config.barHoverPills; x: sysW.x - 9; anchors.verticalCenter: parent.verticalCenter; width: sysW.width + 18; height: 27; radius: 13.5; color: Config.fg(sysh.hovered && bar.openLobe !== "system" ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
        Row { id: sysW; visible: barContent.placed("system") && !bar.editing; x: barContent.at("system"); anchors.verticalCenter: parent.verticalCenter; spacing: 10
            property real cpu: 0; property real mem: 0
            HoverHandler { id: sysh }
            TapHandler { onTapped: bar.toggle("system") }               // the system monitor lobe (SysMon.qml)
            Timer { interval: 2000; running: sysW.visible && !bar.quiet; repeat: true; triggeredOnStart: true; onTriggered: { const v = Shell.sysStats(); sysW.cpu = v.cpu; sysW.mem = v.mem } }
            Repeater { model: [ { t: "CPU", k: "cpu" }, { t: "RAM", k: "mem" } ]
                Row { required property var modelData; spacing: 5; anchors.verticalCenter: parent.verticalCenter
                    Text { text: modelData.t; color: Config.inkDim; font.pixelSize: 11; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: 30; text: Math.round(100 * sysW[modelData.k]) + "%"; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 }; anchors.verticalCenter: parent.verticalCenter } } } }
        GlowIcon { id: gear; visible: barContent.placed("gear") && !bar.editing; x: barContent.at("gear"); anchors.verticalCenter: parent.verticalCenter; size: Math.round(22 * Config.barIconScale); source: "configure"; active: bar.openLobe === "gear"; hovered: gh.hovered
            HoverHandler { id: gh }
            TapHandler { onTapped: bar.toggle("gear") } }
        // ---- status widgets that show only when they have something to say (each a file of its own, see Bar*.qml)
        // The microphone and privacy widgets share one plasma-pa backend (a PRIVATE Plasma module, by URL: a missing module
        // leaves them empty, not the bar broken); it is loaded only while one of them is placed.
        Loader { id: audioL; active: barContent.placed("mic") || barContent.placed("privacy"); source: "VolumeBackend.qml"; onStatusChanged: if (status === Loader.Error) console.warn("bar: microphone state unavailable (org.kde.plasma.private.volume)") }
        BarBattery { id: batteryW; allowed: barContent.placed("battery") && !bar.editing; x: barContent.at("battery"); anchors.verticalCenter: parent.verticalCenter; onClicked: bar.toggle("gear") }
        BarMic { id: micW; allowed: barContent.placed("mic") && !bar.editing; audio: audioL.item; x: barContent.at("mic"); anchors.verticalCenter: parent.verticalCenter }
        BarPrivacy { id: privacyW; allowed: barContent.placed("privacy") && !bar.editing; audio: audioL.item; x: barContent.at("privacy"); anchors.verticalCenter: parent.verticalCenter; onClicked: bar.openSoundPage() }
        BarKeyboard { id: keyboardW; allowed: barContent.placed("keyboard") && !bar.editing; x: barContent.at("keyboard"); anchors.verticalCenter: parent.verticalCenter }
        WeatherWidget { id: weatherW; allowed: barContent.placed("weather") && !bar.editing; x: barContent.at("weather"); anchors.verticalCenter: parent.verticalCenter; onClicked: bar.toggle("clock"); onSetupRequested: Shell.openSettingsPage(3) }
        GlowIcon { id: disksBtn; visible: barContent.live("disks") && !bar.editing; x: barContent.at("disks"); anchors.verticalCenter: parent.verticalCenter; size: Math.round(20 * Config.barIconScale)
            source: "drive-removable-media-symbolic"; active: bar.openLobe === "disks"; hovered: dkh.hovered
            HoverHandler { id: dkh }
            TapHandler { onTapped: bar.toggle("disks") } }
        // user widgets (~/.config/<app>/widgets/<name>, see examples/widgets), placed like any other widget under the kind "user:<name>"
        Repeater { id: userWidgets; model: UserWidgets.names
            UserWidget { required property string modelData; name: modelData; height: parent.height; y: 0; quiet: bar.busy
                visible: barContent.placed("user:" + name) && !bar.editing; x: barContent.at("user:" + name) } }
    }

    // ---- edit mode -------------------------------------------------------------------------------------------------
    // Every placed widget is a chip in its group; drag a chip to another spot (or another group), × takes it off the bar.
    // Clock and quick settings cannot be removed (no way back in without them). The two handles resize the bar.
    Item { id: editLayer; visible: bar.editing; x: barRect.x; y: barRect.y; width: barRect.width; height: barRect.height
        function chipsOf(row) { const out = []; for (let i = 0; i < row.children.length; ++i) if (row.children[i].chipName !== undefined) out.push(row.children[i]); return out }
        function drop(chip) {
            const cx = chip.mapToItem(editLayer, chip.width / 2, 0).x
            const group = cx < width * 0.36 ? "barLeft" : (cx > width * 0.64 ? "barRight" : "barCenter")
            const row = group === "barLeft" ? leftChips : group === "barRight" ? rightChips : centreChips
            let index = 0; for (const c of chipsOf(row)) if (c !== chip && c.mapToItem(editLayer, c.width / 2, 0).x < cx) index++
            const lists = { barLeft: Config.barLeft.filter(n => n !== chip.chipName), barCenter: Config.barCenter.filter(n => n !== chip.chipName), barRight: Config.barRight.filter(n => n !== chip.chipName) }
            lists[group].splice(index, 0, chip.chipName); Shell.saveConfigKeys(lists) }
        function remove(name) { Shell.saveConfigKeys({ barLeft: Config.barLeft.filter(n => n !== name), barCenter: Config.barCenter.filter(n => n !== name), barRight: Config.barRight.filter(n => n !== name) }) }
        component Chip: Rectangle { id: chip; required property string modelData
            readonly property string chipName: modelData
            readonly property bool locked: modelData === "clock" || modelData === "gear"
            height: 27; width: ct.implicitWidth + (locked ? 24 : 40); radius: 13.5; z: dh.active ? 10 : 0
            color: Config.fg(dh.active ? 0.22 : (hh.hovered ? 0.15 : 0.10)); border.width: 1.5; border.color: Config.accent
            scale: dh.active ? 1.06 : 1; Behavior on scale { NumberAnimation { duration: Config.quick } }
            Text { id: ct; x: 12; anchors.verticalCenter: parent.verticalCenter; text: Config.barWidgetNames[chip.modelData] || chip.modelData; color: Config.fgSolid; font.pixelSize: 12; font.weight: Font.Medium }
            Rectangle { visible: !chip.locked; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: Config.fg(xh.hovered ? 0.45 : 0.18)
                Text { anchors.centerIn: parent; text: "×"; color: Config.fgSolid; font.pixelSize: 12; font.weight: Font.Bold }
                HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: editLayer.remove(chip.modelData) } }
            HoverHandler { id: hh; cursorShape: dh.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
            DragHandler { id: dh; yAxis.enabled: false; onActiveChanged: if (!active) editLayer.drop(chip) } }
        Row { id: leftChips; x: Config.barPad - 6; anchors.verticalCenter: parent.verticalCenter; spacing: 8; Repeater { model: Config.barLeft; Chip {} } }
        Row { id: centreChips; anchors.centerIn: parent; spacing: 8; Repeater { model: Config.barCenter; Chip {} } }
        Row { id: rightChips; anchors.right: parent.right; anchors.rightMargin: Config.barPad - 6; anchors.verticalCenter: parent.verticalCenter; spacing: 8; Repeater { model: Config.barRight; Chip {} } } }
    // outline + the two width handles (they sit in the shadow margin beside the bar)
    Rectangle { visible: bar.editing; x: barRect.x - 4; y: barRect.y - 4; width: barRect.width + 8; height: barRect.height + 8; radius: height / 2; color: "transparent"; border.width: 2; border.color: Config.accent; opacity: 0.9 }
    Repeater { model: bar.editing ? 2 : 0
        Rectangle { id: grip; required property int index; readonly property bool rightSide: index === 1
            x: rightSide ? barRect.x + barRect.width - 8 : barRect.x - width + 8; y: barRect.y + (barRect.height - height) / 2; width: 18; height: 44; radius: 9; z: 20
            color: Config.accent; border.width: 1; border.color: Config.fg(0.6); scale: gm.pressed ? 1.12 : (gm.containsMouse ? 1.06 : 1)
            Column { anchors.centerIn: parent; spacing: 4; Repeater { model: 3; Rectangle { width: 8; height: 2; radius: 1; color: Config.fgSolid } } }
            MouseArea { id: gm; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.SizeHorCursor
                property real startX; property int startW
                onPressed: e => { startX = mapToItem(null, e.x, 0).x; startW = bar.barW }
                // the bar is centred, so a handle moves both ends: twice the pointer's travel
                onPositionChanged: e => { if (!pressed) return; const dx = mapToItem(null, e.x, 0).x - startX; const w = Math.round(Math.max(480, Math.min(bar.screenW, startW + 2 * (grip.rightSide ? dx : -dx))) / 2) * 2
                    if (w !== Config.barWidth || Config.barWidthMode !== "custom") widthWrite.go(w) } } } }
    Timer { id: widthWrite; interval: 40; property int w; function go(v) { w = v; if (!running) start() } onTriggered: Shell.saveConfigKeys({ barWidthMode: "custom", barWidth: w }) }
    // an empty spot on the bar, right click: edit mode
    TapHandler { acceptedButtons: Qt.RightButton; enabled: !bar.editing
        onTapped: (ev) => { const p = barContent.mapFromItem(null, ev.position.x, ev.position.y); if (p.y < 0 || p.y > barContent.height || p.x < 0 || p.x > barContent.width) return
            const c = barContent.childAt(p.x, p.y); if (!c || c === titleRow || c === dateW || c === sysW) bar.editRequested() } }

    // self-test: show desktop once, and unconditionally back off 4 s later (never loops)
    Timer { id: sdTest; interval: 6000; onTriggered: { bar.showDesktopRequested(); sdBack.start() } }
    Timer { id: sdBack; interval: 7000; onTriggered: bar.showDesktopRequested() }
    Timer { id: openTrayLater; interval: 2500; onTriggered: if (tray.appletItem) tray.appletItem.glassExpand() }

    // ---- lobe contents: hosted applets, clipped to the lobe while it grows ------------------------
    Item { id: trayContent; x: trayRect.x; y: topY + barH; width: trayRect.width; height: trayH; clip: true; visible: trayH > 1; opacity: Math.min(1, trayH / 140) 
        TrayMenu { id: trayMenu; visible: Config.nativeTray; x: Config.lobePad; y: Config.lobePad; width: implicitWidth; onCloseRequested: bar.openLobe = "" } }
    Item { x: clockRect.x; y: topY + barH; width: clockRect.width; height: clockH; clip: true; opacity: Math.min(1, clockH / 140)
        CalendarPanel { id: calendarPanel; visible: Config.nativeCalendar; x: Config.lobePad; y: Config.lobePad; width: implicitWidth; open: bar.openLobe === "clock" }
        Loader { id: hostedClockLoader; active: !Config.nativeCalendar; x: Config.lobePad; y: Config.lobePad; width: bar.clockW - 2 * Config.lobePad; height: bar.clockFullH - 2 * Config.lobePad
            sourceComponent: AppletHost { plugin: "org.kde.plasma.digitalclock"; zone: "lobe"
                expanded: bar.openLobe === "clock"
                onExpandedChanged: if (!expanded && bar.openLobe === "clock") bar.openLobe = "" } } }
    Item { x: gearRect.x; y: topY + barH; width: gearRect.width; height: gearH; clip: true; opacity: Math.min(1, gearH / 140)
        Loader { id: controlLoader; active: Config.nativeControl && bar.warm; x: Config.lobePad; y: Config.lobePad; width: bar.gearW - 2 * Config.lobePad; height: bar.gearFullH - 2 * Config.lobePad
            source: Config.quickSettingsStyle === "classic" ? "qrc:/qt/qml/SircaShell/qml/control/ControlPanel.qml" : "QuickSettings.qml"
            onLoaded: { item.expanded = (bar.openLobe === "gear"); if (item.busy !== undefined) item.busy = Qt.binding(() => bar.busy) }   // busy: the Caffeine tile's "auto while full-screen"
            Connections { target: bar; function onOpenLobeChanged() { if (controlLoader.item) controlLoader.item.expanded = (bar.openLobe === "gear") } }
            Connections { target: controlLoader.item; ignoreUnknownSignals: true; function onCloseRequested() { if (bar.openLobe === "gear") bar.openLobe = "" }
                function onOsdRequested(icon, fraction) { clockBox.showLocal(icon, fraction) } } }
        Loader { id: hostedControlLoader; active: !Config.nativeControl; x: Config.lobePad; y: Config.lobePad; width: bar.gearW - 2 * Config.lobePad; height: bar.gearFullH - 2 * Config.lobePad
            sourceComponent: AppletHost { plugin: "onur.glasscontrol"; zone: "lobe"
                expanded: bar.openLobe === "gear"
                onExpandedChanged: if (!expanded && bar.openLobe === "gear") bar.openLobe = "" } } }

    // the container runs up into the bar (short of its top) so the cover's haze is not cut along the bar's bottom edge
    Item { readonly property real up: Math.max(0, barH - 6)
        x: mediaRect.x; y: topY + barH - up; width: mediaRect.width; height: mediaH + up; clip: true; visible: mediaH > 1; opacity: Math.min(1, mediaH / 140)
        // by URL, like the island's source: MediaPanel imports the private MPRIS module; a failure there must not take the bar down
        Loader { id: mediaPanel; source: "MediaPanel.qml"; x: Config.lobePad; y: Config.lobePad + parent.up
            onLoaded: { item.mpris = Qt.binding(() => island.model); item.open = Qt.binding(() => bar.openLobe === "media"); item.width = Qt.binding(() => item.implicitWidth); item.hazeUp = Qt.binding(() => parent.up) } } }
    Item { id: cardsContent; x: cardsRect.x; y: topY + barH; width: cardsRect.width; height: cardsH; clip: true; opacity: Math.min(1, cardsH / 60) 
        NotificationCards { id: nativeCards; muted: bar.busy && Config.quietWhenBusy; visible: Config.nativeNotifications; x: Config.lobePad; y: Config.lobePad } }
    Item { x: notifRect.x; y: topY + barH; width: notifRect.width; height: notifH; clip: true; visible: notifH > 1; opacity: Math.min(1, notifH / 140)
        NotificationCenter { id: notifCenter; x: Config.lobePad; y: Config.lobePad; width: implicitWidth; open: bar.openLobe === "notif" } }
    Item { x: disksRect.x; y: topY + barH; width: disksRect.width; height: disksH; clip: true; visible: disksH > 1; opacity: Math.min(1, disksH / 140)
        RemovableMedia { id: disksPanel; x: Config.lobePad; y: Config.lobePad; width: implicitWidth; open: bar.openLobe === "disks" } }
    Item { x: sysmonRect.x; y: topY + barH; width: sysmonRect.width; height: sysmonH; clip: true; visible: sysmonH > 1; opacity: Math.min(1, sysmonH / 140)
        SysMon { id: sysmonPanel; x: Config.lobePad; y: Config.lobePad; width: implicitWidth; height: implicitHeight; open: bar.openLobe === "system" } }

    Shortcut { sequence: "Escape"; onActivated: bar.openLobe = "" }
    Timer { running: Qt.application.arguments.indexOf("--demo") >= 0; interval: 2500; repeat: true
        onTriggered: bar.openLobe = ({ "": "clock", "clock": "gear", "gear": "" })[bar.openLobe] }
}
