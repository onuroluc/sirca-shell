// The dock: one bottom surface, width fitted to content, driven by the real task model (org.kde.taskmanager).
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami
import SircaShell
import "Glass"

Surface {
    id: dock
    edge: "bottom"
    readonly property int gap: Config.dockGap
    readonly property int dockH: Config.dockHeight
    readonly property int headroom: 44            // room above the bar for hover magnification / the future shelf
    readonly property int pad: 12
    readonly property int sidePad: 32
    strut: gap + dockH + gap
    slideMax: gap + dockH + 30
    edgeStrip: Qt.rect((width - dockW) / 2, 0, dockW, 0)
    holdOpen: launcherOpen || previewShown || dragging || editing || dodgeExempt
    dodge: Config.dockDodge
    blur: look.blur
    visibility: Config.dockVisibility
    keepOnFullscreen: Config.dockFullscreenMode === "keep"
    maximizedHere: anyMaximized
    quiet: fullscreenActive
    property int hoverIndex: -2                   // -1 = launcher glyph, >= 0 task index, -2 none
    // ---- dodge modes (config dockDodgeMode). Main's watcher only says whether ANY window lies over the dock's strip
    // (`covered`, "all"). With "active" only the focused window counts, with "maximized" only a maximised one: for every
    // other window the dock stays put, which holdOpen does; the test walks the dock's own model (its children are the windows).
    readonly property string dodgeMode: String(Config.get("dockDodgeMode", "all"))
    property bool modeCovered: false
    readonly property bool dodgeExempt: dodgeMode !== "all" && covered && !modeCovered
    // a window lies over the strip and the dock does not move (dodge off, or the mode exempts that window): denser glass, so
    // the icons still read over whatever is behind them (config dockTintAlphaTouched)
    readonly property bool touched: covered && (!Config.dockDodge || dodgeExempt)
    // the look for the dock's state (#7): touched / maximised / full-screen have their own opacity and blur (Config.lookFor)
    readonly property var look: Config.lookFor("dock", touched && lookState === "normal" ? "touched" : lookState)
    property real tintA: look.opacity < 0 ? Config.dockTintAlpha : look.opacity
    Behavior on tintA { NumberAnimation { duration: Config.slow } }
    // a maximised window on this screen and desktop: the "maximized" state of both surfaces (the bar reads it through ScreenSet)
    property bool anyMaximized: false
    function refreshMaximized() { const m = tasksModel; if (!m) { anyMaximized = false; return }
        const R_ = TaskManager.AbstractTasksModel; const cur = vdInfo.currentDesktop; const sr = Qt.rect(screenX, screenY, screenW, Screen.height)
        const hit = idx => { if (m.data(idx, R_.IsMinimized) || m.data(idx, R_.IsLauncher) || !m.data(idx, R_.IsMaximized)) return false
            if (!m.data(idx, R_.IsOnAllVirtualDesktops)) { const vds = m.data(idx, R_.VirtualDesktops); if (vds && vds.length && vds.indexOf(cur) < 0) return false }
            const g = m.data(idx, R_.Geometry); return !!g && g.width > 0 && g.x < sr.x + sr.width && g.x + g.width > sr.x && g.y < sr.y + sr.height && g.y + g.height > sr.y }
        let c = false
        for (let i = 0; i < m.count && !c; ++i) { const idx = m.makeModelIndex(i)
            if (m.data(idx, R_.IsGroupParent)) { const n = m.rowCount(idx); for (let k = 0; k < n && !c; ++k) c = hit(m.makeModelIndex(i, k)) } else c = hit(idx) }
        anyMaximized = c }
    function refreshModeCovered() {
        const m = tasksModel; if (!m || dodgeMode === "all") { modeCovered = covered; return }
        const R_ = TaskManager.AbstractTasksModel; const cur = vdInfo.currentDesktop
        const r = Qt.rect(screenX + x + (width - dockW) / 2, screenY + y + height - strutSize, dockW, strutSize)     // the strip Main tests, in desktop coordinates
        const hit = idx => { if (m.data(idx, R_.IsMinimized) || m.data(idx, R_.IsLauncher)) return false
            if (dodgeMode === "active" ? !m.data(idx, R_.IsActive) : !m.data(idx, R_.IsMaximized)) return false
            if (!m.data(idx, R_.IsOnAllVirtualDesktops)) { const vds = m.data(idx, R_.VirtualDesktops); if (vds && vds.length && vds.indexOf(cur) < 0) return false }   // the model is not desktop-filtered
            const g = m.data(idx, R_.Geometry); return !!g && g.width > 0 && g.x < r.x + r.width && g.x + g.width > r.x && g.y < r.y + r.height && g.y + g.height > r.y }
        let c = false
        for (let i = 0; i < m.count && !c; ++i) { const idx = m.makeModelIndex(i)
            if (m.data(idx, R_.IsGroupParent)) { const n = m.rowCount(idx); for (let k = 0; k < n && !c; ++k) c = hit(m.makeModelIndex(i, k)) } else c = hit(idx) }
        modeCovered = c
    }
    onCoveredChanged: modeRefresh.kick()
    onDodgeModeChanged: modeRefresh.kick()
    Timer { id: modeRefresh; interval: 40; onTriggered: { dock.refreshModeCovered(); dock.refreshMaximized() } function kick() { if (!running) start() } }   // a throttle: a dragged window reports its frame continuously

    TaskManager.ActivityInfo { id: activityInfo }
    TaskManager.VirtualDesktopInfo { id: vdInfo }
    // libtaskmanager binds KWin's window-management global with a short timeout at construction; give the
    // Wayland registry a moment after the surfaces are up before creating the model.
    property var tasksModel: null
    Timer { interval: 900; running: true; onTriggered: dock.tasksModel = modelComp.createObject(dock) }
    Component {
        id: modelComp
        TaskManager.TasksModel {
            launcherList: Config.launchers
            groupMode: TaskManager.TasksModel.GroupApplications
            groupInline: false
            separateLaunchers: true
            hideActivatedLaunchers: true
            launchInPlace: true
            sortMode: TaskManager.TasksModel.SortManual
            filterByVirtualDesktop: false
            filterByScreen: false
            filterByActivity: true
            activity: activityInfo.currentActivity
            virtualDesktop: vdInfo.currentDesktop
        }
    }

    readonly property int contentW: pad + Config.dockCell + row.spacing + (tasksModel ? tasksModel.count : 0) * Config.dockCell + pad
    readonly property int screenW: Screen.width > 0 ? Screen.width : Config.screenWidth
    readonly property int dockW: Config.dockWidthMode === "fill" ? screenW - 2 * Config.dockFillMargin : Math.max(contentW, 120)
    readonly property real rowShift: Math.max(0, (dockW - contentW) / 2)      // "fill": the icons stay centred in the wider dock
    property bool editing: false                 // edit mode: pinned icons show an unpin badge, previews and the launcher stay shut
    signal editRequested()
    property int launcherRev: 0                  // bumps when the pinned set changes (launcherPosition is a function, not a property)
    readonly property real rad: Config.dockRadius

    // ---- what grows out of the dock ------------------------------------------------------------
    // launcher : Kickoff, always a wide PANEL above the dock (drawn as "panel with the dock hanging under it")
    // preview  : the hovered app's windows; a LOBE over the icon when it fits inside the dock, else a panel too
    property bool launcherOpen: false
    readonly property int lobePad: Config.lobePad
    property bool warm: false                                                     // heavy popup content exists (see nativeLauncher)
    Timer { interval: 1200; running: true; onTriggered: dock.warm = true }
    readonly property Item hostedLauncher: kickoffLoader.item                     // only exists with nativeLauncher off
    function hostedPref(which, fallback) { const a = hostedLauncher ? hostedLauncher.appletItem : null; const f = a ? a.fullRepresentationItem : null;
        const v = (f && f.Layout) ? (which === "w" ? f.Layout.preferredWidth : f.Layout.preferredHeight) : 0; return v > 0 ? v : fallback }
    readonly property real launcherFullW: Config.nativeLauncher ? nativeLauncher.implicitWidth : Math.min(hostedPref("w", 560), 900)
    readonly property real launcherFullH: Config.nativeLauncher ? nativeLauncher.implicitHeight : Math.min(hostedPref("h", 600), Config.sheetHeight + 120)
    property real launcherGrow: launcherOpen ? 1 : 0
    Behavior on launcherGrow { Spring {} }

    property int previewIndex: -1                 // task row whose windows are shown, -1 = none
    property var previewWindows: []               // [{title, uuid, child, active}]
    property var previewIcon
    property bool previewShown: false
    readonly property int thumbW: 214
    readonly property int thumbH: 156
    property string lobeMode: "windows"            // what the lobe over an icon shows: "windows" (hover) or "menu" (right-click)
    property var menuItems: []                     // [{label, icon, act}]
    // Previews that fit over the dock's straight top edge are a LOBE over their icon. More of them become a PANEL, and a
    // panel is never narrower than the dock plus its overhang: with two or three windows that left the thumbnails floating
    // in the middle with wide empty margins. In a panel the thumbnails grow (same aspect, up to 1.3x) to use that width.
    readonly property int pvCount: Math.max(1, previewWindows.length)
    readonly property real pvWBase: pvCount * (thumbW + 8) + 8
    readonly property bool pvLobeMode: (lobeMode === "menu" ? 232 : pvWBase) <= dockW - 2 * (rad + 14)
    readonly property real thumbScale: (lobeMode === "menu" || pvLobeMode) ? 1 : Math.max(1, Math.min(1.3, ((dockW + 2 * stemMargin - 8) / pvCount - 8) / thumbW))
    readonly property real tW: Math.round(thumbW * thumbScale)
    readonly property real tH: Math.round(thumbH * thumbScale)
    readonly property real pvW: lobeMode === "menu" ? 232 : pvCount * (tW + 8) + 8
    // ---- per-app audio (DockAudio.qml, behind a Loader by URL: org.kde.plasma.private.volume is a private Plasma module;
    // if it is missing or has changed, the dock loses its volume row and nothing else)
    Loader { id: audioLoader; source: "DockAudio.qml"; onLoaded: { item.dock = dock; item.refresh() }
        onStatusChanged: if (status === Loader.Error) console.warn("dock: per-app audio unavailable (org.kde.plasma.private.volume)") }
    readonly property var audio: audioLoader.item
    readonly property bool hasAudio: audio ? audio.hasAudio : false
    readonly property int audioRowH: 40
    readonly property int audioRev: audio ? audio.rev : 0     // bumped on stream changes: the row's bindings re-read volume / muted
    function refreshAppStreams() { if (audio) audio.refresh() }
    onPreviewIndexChanged: refreshAppStreams()
    readonly property real pvH: lobeMode === "menu" ? menuItems.length * 34 + 16 : tH + 16 + (hasAudio ? audioRowH : 0)
    property real previewGrow: previewShown ? 1 : 0
    Behavior on previewGrow { Spring {} }
    onPreviewGrowChanged: if (previewGrow < 0.002 && !previewShown) { previewIndex = -1; previewWindows = [] }

    readonly property string panelKind: launcherGrow > 0.002 ? "launcher" : (previewGrow > 0.002 && !pvLobeMode ? "preview" : "")
    readonly property real stemMargin: rad + 14 + 4                                  // a panel overhangs the dock by this much per side
    readonly property real panelG: Math.max(0, panelKind === "launcher" ? launcherGrow : previewGrow)
    readonly property real panelFullW: Math.max(panelKind === "preview" ? pvW : launcherFullW + 2 * lobePad, dockW + 2 * stemMargin)
    readonly property real panelW: dockW + 2 * stemMargin + (panelFullW - dockW - 2 * stemMargin) * Math.min(1, panelG * 1.6)
    readonly property real panelH: panelKind === "" ? 0 : panelG * (panelKind === "preview" ? pvH : launcherFullH + 2 * lobePad)
    readonly property bool panelUp: panelH > 1
    // lobe-mode preview: centred over its icon, kept inside the dock's straight top edge
    function cellCenter(row) { return barRect.x + rowShift + pad + Config.dockCell * (row + 1) + Config.dockCell / 2 }
    property real lobeX: Math.max(barRect.x + rad + 14, Math.min(barRect.x + dockW - rad - 14 - pvW, cellCenter(Math.max(0, previewIndex)) - pvW / 2))
    Behavior on lobeX { enabled: dock.previewGrow > 0.5; Spring {} }
    readonly property real lobeH: (panelKind === "" && pvLobeMode) ? Math.max(0, previewGrow) * pvH : 0

    width: Math.min(screenW, Math.max(dockW + 2 * stemMargin, launcherFullW, 900) + 2 * sidePad)   // never wider than the screen ("fill")
    height: Math.max(headroom, Config.sheetHeight + 36) + gap + dockH + gap
    title: "Sirca Shell — dock"
    readonly property real dockTopRest: height - gap - dockH
    readonly property real dockTop: dockTopRest + slide      // the dock and whatever hangs off it slide down as one
    readonly property rect barRect: Qt.rect((width - dockW) / 2, dockTop, dockW, dockH)
    readonly property rect panelRect: Qt.rect((width - panelW) / 2, dockTop - panelH, panelW, panelH)

    LobeShape {
        id: shape
        anchors.fill: parent
        reach: dock.polygon                // the fully grown outline: the shadow layers are sized once per open/close, not per frame
        flip: !dock.panelUp
        bar: dock.panelUp ? dock.panelRect : dock.barRect
        lobes: dock.panelUp ? [{ x: dock.barRect.x, w: dock.barRect.width, h: dock.dockH }] : (dock.lobeH > 0.5 ? [{ x: dock.lobeX, w: dock.pvW, h: dock.lobeH }] : [])
        radius: dock.rad
        tint: Config.glassTint(dock.tintA); rim: Qt.rgba(1, 1, 1, Config.dockRimAlpha * Config.mixn(1, 3.2)); sheen: Config.dockSheen * Config.mixn(1, 2.5); shadowStrength: Config.dockShadow   // literal-ok: the rim is white light in both modes
        fillet: Math.max(1, Math.min(14, (dock.panelUp ? dock.panelH : dock.lobeH) / 2))
        onPolygonChanged: dock.pushShape()
    }
    // blur region + input mask: the fully grown outline (sent once per open/close, not per frame)
    readonly property bool lobeUp: lobeH > 1
    readonly property real maskPanelH: (panelKind === "preview" ? pvH : launcherFullH + 2 * lobePad) + Config.bounceRoom
    polygon: panelUp ? shape.polygonFor(Qt.rect((width - panelFullW) / 2, dockTopRest - maskPanelH, panelFullW, maskPanelH), [{ x: (width - dockW) / 2, w: dockW, h: dockH }], false, 14)
                     : shape.polygonFor(Qt.rect((width - dockW) / 2, dockTopRest, dockW, dockH), lobeUp ? [{ x: lobeX, w: pvW, h: pvH + Config.bounceRoom }] : [], true, 14)
    // the Glass effect draws its bevel/mask from these boxes (same D-Bus path as the top bar). A box that joins another
    // reaches INTO it, so its own rounded corners never notch the junction.
    function pushShape() {
        if (!Config.dockBlur) { Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "clearLobes", "sii", ["sirca-shell", dock.width, dock.height]); return }
        let boxes = [barRect.x, barRect.y, barRect.width, barRect.height];
        if (panelUp) {
            const up = Math.min(rad, panelH * 0.5);
            boxes = [panelRect.x, panelRect.y, panelRect.width, panelRect.height, barRect.x, barRect.y - up, barRect.width, barRect.height + up];
        } else if (lobeH > 1) {
            boxes = boxes.concat([lobeX, dockTop - lobeH, pvW, lobeH + Math.min(rad, dockH - 15)]);
        }
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "setLobes", "siivdd", ["sirca-shell", dock.width, dock.height, boxes, rad, (panelUp || lobeH > 1) ? shape.fillet * 1.17 : 1]);
    }
    onBarRectChanged: pushShape()
    // The window-preview lobe: the boxes follow lobeH, but the mask polygon only follows lobeUp. While the lobe closes the
    // polygon stops changing before lobeH reaches 0, so the LAST box sent could be a sliver of a lobe: the effect then drew
    // a second, smaller rim inside the dock's top edge until the next resize. Follow lobeH itself.
    onLobeHChanged: pushShape()
    onLobeXChanged: if (lobeH > 1) pushShape()

    // ---- behaviour -----------------------------------------------------------------------------
    function openPreview(row) {
        const m = tasksModel; if (!m || row < 0 || dragging) return;
        lobeMode = "windows";
        const idx = m.makeModelIndex(row);
        if (m.data(idx, TaskManager.AbstractTasksModel.IsLauncher) || launcherOpen) { previewShown = false; return; }
        const R_ = TaskManager.AbstractTasksModel; const wins = [];
        const one = (i, child) => { const ids = m.data(i, R_.WinIdList); wins.push({ title: m.data(i, 0) || "", uuid: ids && ids.length ? ids[0] : "", child: child, active: !!m.data(i, R_.IsActive) }); };
        if (m.data(idx, R_.IsGroupParent)) { const n = m.rowCount(idx); for (let c = 0; c < n; ++c) one(m.makeModelIndex(row, c), c); } else one(idx, -1);
        previewIcon = m.data(idx, 1); previewWindows = wins; previewIndex = row; previewShown = wins.length > 0;
    }
    // hovering a thumbnail shows that window (KWin's highlight-window effect fades the others out)
    function peek(uuid) { Shell.dbusSendTyped("org.kde.KWin.HighlightWindow", "/org/kde/KWin/HighlightWindow", "org.kde.KWin.HighlightWindow", "highlightWindows", "S", [uuid ? [uuid] : []]) }
    onPreviewShownChanged: { if (!previewShown) peek(""); refreshAppStreams() }
    function refreshPreview() { if (previewShown && previewIndex >= 0 && lobeMode === "windows") openPreview(previewIndex) }
    // right-click: the same lobe, holding actions instead of thumbnails
    function openMenu(row) {
        const m = tasksModel; if (!m || row < 0) return;
        const R_ = TaskManager.AbstractTasksModel; const idx = m.makeModelIndex(row);
        const isLauncher = !!m.data(idx, R_.IsLauncher), isGroup = !!m.data(idx, R_.IsGroupParent);
        const url = m.data(idx, R_.LauncherUrlWithoutIcon); const pinned = url && m.launcherPosition(url) >= 0;
        const items = [];
        if (isLauncher) items.push({ label: "Open", icon: "system-run-symbolic", act: "new" });
        else items.push({ label: "New Window", icon: "window-new-symbolic", act: "new" });
        if (url && url.toString() !== "") items.push(pinned ? { label: "Unpin from Dock", icon: "window-unpin-symbolic", act: "unpin" } : { label: "Pin to Dock", icon: "window-pin-symbolic", act: "pin" });
        if (!isLauncher) { items.push({ label: "Minimize", icon: "window-minimize-symbolic", act: "min" }); items.push({ label: isGroup ? "Close All Windows" : "Close Window", icon: "window-close-symbolic", act: "close" }); }
        items.push({ label: "Edit Dock…", icon: "document-edit-symbolic", act: "edit" });
        launcherOpen = false;          // the launcher's panel and this menu share the space over the dock: with it open, the menu never appeared
        openTimer.stop(); peek(""); previewWindows = []; previewIcon = m.data(idx, 1); menuItems = items; lobeMode = "menu"; previewIndex = row; previewShown = true;
    }
    function runMenu(act) {
        const m = tasksModel; const R_ = TaskManager.AbstractTasksModel; const idx = m.makeModelIndex(previewIndex); const url = m.data(idx, R_.LauncherUrlWithoutIcon);
        if (act === "edit") { previewShown = false; editRequested(); return }
        if (act === "new") { m.requestNewInstance(idx); launched(previewIndex); }
        else if (act === "pin") { m.requestAddLauncher(url); saveLaunchers(); }
        else if (act === "unpin") { m.requestRemoveLauncher(url); saveLaunchers(); }
        else if (act === "min") m.requestToggleMinimized(idx);
        else if (act === "close") m.requestClose(idx);
        previewShown = false;
    }
    function saveLaunchers() { Qt.callLater(() => { if (tasksModel) Shell.saveConfigKey("launchers", tasksModel.launcherList); launcherRev++ }) }
    signal launched(int row)
    // the focused window is fullscreen (a game, a video): the shell goes quiet
    property bool fullscreenActive: false
    property bool gameActive: false
    onFullscreenActiveChanged: if (debug) console.log("fullscreenActive", fullscreenActive)
    function refreshFullscreen() { const m = tasksModel; if (!m) return; const R_ = TaskManager.AbstractTasksModel; const a = m.activeTask; if (debug) console.log("refreshFullscreen", a, a ? a.valid : "-", a && a.valid ? m.data(a, R_.IsFullScreen) : "-"); fullscreenActive = !!(a && a.valid && m.data(a, R_.IsFullScreen));
        // a game does not have to be full screen here (centred borderless 3440x1440 on the 32:9 panel): Proton / Steam games
        // have the window class steam_app_<id>, gamescope its own
        const id = (a && a.valid) ? String(m.data(a, R_.AppId) || "") : ""; gameActive = /^(steam_app_|gamescope)/i.test(id) }
    Connections { target: dock.tasksModel; function onActiveTaskChanged() { dock.refreshFullscreen(); modeRefresh.kick() } function onDataChanged() { fsSettle.restart(); modeRefresh.kick() }
        function onRowsInserted() { modeRefresh.kick() } function onRowsRemoved() { modeRefresh.kick() } }
    Timer { id: fsSettle; interval: 400; onTriggered: dock.refreshFullscreen() }
    property bool dragging: false

    // badges + progress from apps (com.canonical.Unity.LauncherEntry, what Discord, Telegram, Dolphin copy jobs… emit)
    property var badges: ({})
    Connections { target: Shell
        function onDbusSignal(iface, member, args) {
            if (iface !== "com.canonical.Unity.LauncherEntry" || member !== "Update" || !args[1]) return;
            const id = String(args[0]).replace(/^application:\/\//, "").replace(/\.desktop$/, "");
            const b = Object.assign({}, badges); b[id] = Object.assign({}, b[id] || {}, args[1]); badges = b;
        } }

    // click: launcher entry → start it; one window → focus, or minimise when already focused; several → cycle through them
    readonly property bool debug: Qt.application.arguments.indexOf("--debug") >= 0
    function activateCell(row) {
        if (debug) console.log("activateCell", row);
        const m = tasksModel; if (!m) return;
        const R_ = TaskManager.AbstractTasksModel; const idx = m.makeModelIndex(row);
        previewShown = false; openTimer.stop();
        if (m.data(idx, R_.IsLauncher)) { m.requestNewInstance(idx); launched(row); return; }
        if (m.data(idx, R_.IsGroupParent)) {
            const n = m.rowCount(idx); let a = -1;
            for (let c = 0; c < n; ++c) if (m.data(m.makeModelIndex(row, c), R_.IsActive)) { a = c; break; }
            if (debug) console.log("group", row, "children", n, "active", a, "->", (a + 1) % Math.max(1, n));
            m.requestActivate(m.makeModelIndex(row, (a + 1) % Math.max(1, n)));
            return;
        }
        if (debug) console.log("single", row, "active", m.data(idx, R_.IsActive), "minimized", m.data(idx, R_.IsMinimized));
        if (m.data(idx, R_.IsActive)) m.requestToggleMinimized(idx); else m.requestActivate(idx);
    }
    // the mouse wheel over an app with several windows walks through them: dir +1 = the next one, -1 = the previous
    function cycleWindows(row, dir) {
        const m = tasksModel; if (!m) return;
        const R_ = TaskManager.AbstractTasksModel; const idx = m.makeModelIndex(row);
        if (!m.data(idx, R_.IsGroupParent)) { m.requestActivate(idx); return; }
        const n = m.rowCount(idx); if (n < 1) return; let a = -1;
        for (let c = 0; c < n; ++c) if (m.data(m.makeModelIndex(row, c), R_.IsActive)) { a = c; break; }
        const base = a < 0 ? (dir > 0 ? -1 : 0) : a;              // none focused: the first one going down, the last one going up
        m.requestActivate(m.makeModelIndex(row, (base + dir + n) % n));
    }
    // a file or a link dropped on an app opens it with that app (the task model runs the launcher with the urls)
    function openUrls(row, urls) {
        const m = tasksModel; if (!m || row < 0 || !urls || !urls.length) return;
        previewShown = false; openTimer.stop();
        m.requestOpenUrls(m.makeModelIndex(row), urls); launched(row);
    }
    Timer { id: openTimer; interval: Config.dockPreviewDelay; onTriggered: if (dock.hoverIndex >= 0 && Config.dockPreviews && !dock.editing) dock.openPreview(dock.hoverIndex) }
    Timer { id: closeTimer; interval: dock.lobeMode === "menu" ? 700 : 260; onTriggered: if (dock.hoverIndex < 0 && !pvHover.hovered) dock.previewShown = false }
    onHoverIndexChanged: {
        if (debug) console.log("hoverIndex", hoverIndex);
        if (hoverIndex >= 0) { closeTimer.stop(); if (previewShown && lobeMode === "windows") openPreview(hoverIndex); else if (!previewShown) openTimer.restart(); }
        else { openTimer.stop(); closeTimer.restart(); }
    }
    onLauncherOpenChanged: {
        if (launcherOpen) warm = true
        if (launcherOpen) previewShown = false;
    }
    // the launcher and a right-click menu take the keyboard and close when they lose it (Surface.popupFocus)
    popupFocus: launcherOpen || (previewShown && lobeMode === "menu")
    onFocusLost: { launcherOpen = false; previewShown = false }
    Connections { target: Shell; function onLauncherToggleRequested() { dock.launcherOpen = !dock.launcherOpen } }
    onWidthChanged: pushShape()
    onHeightChanged: pushShape()
    onVisibleChanged: if (visible) { pushShape(); pushAgain.start() }
    Timer { id: pushAgain; interval: 300; onTriggered: dock.pushShape() }
    Component.onDestruction: Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "clearLobes", "sii", ["sirca-shell", dock.width, dock.height])

    function magFor(i) {
        if (hoverIndex === -2) return 1;
        const d = Math.abs(i - hoverIndex);
        return d === 0 ? Config.dockMagnify : (d === 1 ? 1 + (Config.dockMagnify - 1) * 0.45 : 1);
    }

    // ---- colour haze: every icon throws a blurred pool of its own colours into the glass beneath it. One layer, masked
    // to the dock's rounded outline, holds all of them; it sits under the icons and above the dock's tint.
    // The layer and its mask cover the dock plus what the haze can reach (the mask fades it out 90 px above the dock, the
    // icons' blurred pools spread ~46 px around them), not the whole surface, which is as wide as the screen and as tall
    // as the launcher. Whole pixels: a layer that changes size is re-allocated. The mask's Shape and the pools are shifted
    // back by the rect's origin so everything stays where it was; mask and layer are the same size, pixel for pixel.
    readonly property rect hazeRect: { const l = 48, up = 96, down = 40; const x = Math.max(0, Math.floor(barRect.x - l)), y = Math.max(0, Math.floor(barRect.y - up))
        return Qt.rect(x, y, Math.max(1, Math.min(Math.ceil(width), Math.ceil(barRect.x + barRect.width + l)) - x), Math.max(1, Math.min(Math.ceil(height), Math.ceil(barRect.y + barRect.height + down)) - y)) }
    Item {
        id: hazeLayer
        x: dock.hazeRect.x; y: dock.hazeRect.y; width: dock.hazeRect.width; height: dock.hazeRect.height
        visible: Config.hazeStrength > 0.01
        layer.enabled: true
        // threshold 0.5 + spread 1.0 = smoothstep(0, 1, maskAlpha): a soft, proportional mask. (0.0 + 1.0 evaluates to
        // smoothstep(-1, 0, a) = 1 everywhere — the mask stops masking and the haze spills over the wallpaper.)
        layer.effect: MultiEffect { maskEnabled: true; maskSource: hazeMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        Repeater {
            model: dock.tasksModel
            delegate: IconHaze {
                required property int index
                required property var model
                source: model.decoration
                iconSize: Config.dockIcon
                x: barRect.x + dock.pad + Config.dockCell * (index + 1) + Config.dockCell / 2 - width / 2 - dock.hazeRect.x
                y: barRect.y + dockH / 2 - height / 2 + 4 - dock.hazeRect.y
                strength: Config.hazeStrength * (model.IsActive ? 1.35 : (dock.hoverIndex === index ? 1.2 : 1.0)) * (model.IsLauncher ? 0.7 : 1.0)
            }
        }
    }
    // mask = exactly the outline that is drawn (dock + whatever has grown out of it), so there is no seam at the dock's top edge
    Item { id: hazeMask; x: dock.hazeRect.x; y: dock.hazeRect.y; width: dock.hazeRect.width; height: dock.hazeRect.height; visible: false; layer.enabled: true
        Shape { x: -dock.hazeRect.x; y: -dock.hazeRect.y; width: dock.width; height: dock.height; preferredRendererType: Shape.CurveRenderer
            // full strength inside the dock, then a smooth fade over the first ~90 px of whatever has grown above it: the haze
            // reaches up into a preview or the launcher and dies away, instead of smearing colour across the whole panel
            ShapePath { strokeWidth: -1
                fillGradient: LinearGradient { x1: 0; x2: 0; y1: dock.barRect.y - 90; y2: dock.barRect.y + 6
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.35) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 1) } }
                PathSvg { path: shape.pathData } } } }

    Rectangle { visible: dock.editing; x: barRect.x - 4; y: barRect.y - 4; width: barRect.width + 8; height: barRect.height + 8; radius: dock.rad + 4; color: "transparent"; border.width: 2; border.color: Config.accent; opacity: 0.9 }
    TapHandler { acceptedButtons: Qt.RightButton; enabled: !dock.editing
        onTapped: (ev) => { const p = ev.position; if (p.x < barRect.x || p.x > barRect.x + barRect.width || p.y < barRect.y || p.y > barRect.y + barRect.height) return
            const inRow = p.x >= row.x && p.x <= row.x + row.width; if (!inRow) dock.editRequested() } }
    Row {
        id: row
        x: barRect.x + dock.rowShift + dock.pad; y: barRect.y; height: dockH
        spacing: 0
        // launcher glyph
        Item { width: Config.dockCell; height: dockH
            readonly property real mag: dock.magFor(-1)
            Spotlight { visible: Config.dockSpotlight; anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 1; strength: dock.hoverIndex === -1 && !dock.launcherOpen ? 0.16 : 0 }
            // same box as the app icons, so the glyph reads at their size; glows while the launcher is open
            GlowIcon { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
                anchors.bottomMargin: (dockH - Config.dockIcon) / 2
                // Rendered once at the magnified size and zoomed with `scale`: animating `size` re-rasterised the glyph and
                // re-created both glow blurs on every frame, which stuttered the panel when it was opened mid-hover.
                size: Math.round(Config.dockIcon * Config.dockMagnify); source: Config.launcherIcon; calm: true; hovered: dock.hoverIndex === -1; active: dock.launcherOpen
                transformOrigin: Item.Bottom
                scale: parent.mag / Config.dockMagnify
                Behavior on scale { Spring {} } }
            HoverHandler { onHoveredChanged: dock.hoverIndex = hovered ? -1 : (dock.hoverIndex === -1 ? -2 : dock.hoverIndex) }
            TapHandler { onTapped: if (!dock.editing) dock.launcherOpen = !dock.launcherOpen }
        }
        Repeater {
            model: dock.tasksModel
            delegate: Item {
                id: cell
                required property int index
                required property var model
                width: Config.dockCell; height: dockH
                readonly property real mag: dock.magFor(index)
                readonly property bool hovered: dock.hoverIndex === index
                readonly property int windows: model.IsLauncher ? 0 : (model.IsGroupParent ? Math.max(model.ChildCount, 2) : 1)
                property int activeChild: -1
                function refreshActive() {
                    if (!model.IsGroupParent) { activeChild = model.IsActive ? 0 : -1; return; }
                    let f = -1;
                    for (let i = 0; i < model.ChildCount; ++i)
                        if (dock.tasksModel.data(dock.tasksModel.makeModelIndex(index, i), TaskManager.AbstractTasksModel.IsActive)) { f = i; break; }
                    activeChild = f;
                }
                Timer { id: settle; interval: 120; onTriggered: cell.refreshActive() }
                Connections { target: dock.tasksModel; function onActiveTaskChanged() { cell.refreshActive(); settle.restart(); } }
                onWindowsChanged: { settle.restart(); geoLater.restart(); if (dock.previewIndex === index) dock.refreshPreview() }
                Component.onCompleted: { refreshActive(); geoLater.restart() }
                // Tell KWin where this window's icon is: the minimise / restore animation (squash) flies to and from that
                // rectangle. Without it windows just vanish. Uses the dock's resting position, also while it is dodging.
                function publishGeometry() {
                    if (!dock.tasksModel || model.IsLauncher) return;
                    const gx = dock.x + dock.barRect.x + dock.pad + Config.dockCell * (index + 1) + (Config.dockCell - Config.dockIcon) / 2;
                    const gy = dock.y + dock.dockTopRest + (dock.dockH - Config.dockIcon) / 2;
                    dock.tasksModel.requestPublishDelegateGeometry(dock.tasksModel.makeModelIndex(index), Qt.rect(Math.round(gx), Math.round(gy), Config.dockIcon, Config.dockIcon), cell);
                }
                Timer { id: geoLater; interval: 300; onTriggered: cell.publishGeometry() }
                onIndexChanged: geoLater.restart()
                Connections { target: dock; function onDockWChanged() { geoLater.restart() } function onXChanged() { geoLater.restart() } }

                // launch feedback: two hops on launch, a gentle loop while the app is still starting
                property real hop: 0
                SequentialAnimation { id: hopAnim
                    NumberAnimation { target: cell; property: "hop"; to: 16; duration: 170; easing.type: Easing.OutQuad }
                    NumberAnimation { target: cell; property: "hop"; to: 0; duration: 210; easing.type: Easing.InQuad }
                    NumberAnimation { target: cell; property: "hop"; to: 7; duration: 130; easing.type: Easing.OutQuad }
                    NumberAnimation { target: cell; property: "hop"; to: 0; duration: 160; easing.type: Easing.InQuad } }
                Connections { target: dock; function onLaunched(row) { if (row === cell.index && Config.dockHop) hopAnim.restart() } }
                readonly property bool starting: model.IsStartup === true
                onStartingChanged: if (starting && Config.dockHop) hopAnim.restart()
                Timer { running: cell.starting && Config.dockHop; interval: 900; repeat: true; onTriggered: hopAnim.restart() }
                readonly property var badge: { const id = String(model.AppId || "").replace(/\.desktop$/, ""); return dock.badges[id] || null }
                // a window asks for attention: the icon shakes ONCE (whole pixels: the dock is a wide surface), then the pills
                // stay orange until it is looked at. Not while a game has the screen: nobody would see it, and the shell is quiet.
                property real wiggleX: 0
                readonly property bool attention: model.IsDemandingAttention === true
                onAttentionChanged: if (attention && !dock.quiet) wiggleAnim.restart()
                SequentialAnimation { id: wiggleAnim
                    NumberAnimation { target: cell; property: "wiggleX"; to: -7; duration: 60; easing.type: Easing.OutQuad }
                    NumberAnimation { target: cell; property: "wiggleX"; to: 7; duration: 90 }
                    NumberAnimation { target: cell; property: "wiggleX"; to: -5; duration: 80 }
                    NumberAnimation { target: cell; property: "wiggleX"; to: 4; duration: 70 }
                    NumberAnimation { target: cell; property: "wiggleX"; to: 0; duration: 80; easing.type: Easing.OutQuad } }
                // drop a file or a link on the icon: opens it with this app. Wayland sends no hover while something is
                // being dragged, so the drop zone itself lights the cell (hoverIndex) and puts it back on leaving.
                DropArea { id: dropZone; anchors.fill: parent; enabled: !dock.editing && !drag.active
                    function urlsOf(d) { if (d.hasUrls) return d.urls; const t = d.hasText ? String(d.text).trim() : ""; return /^[a-z][a-z0-9+.-]*:\/\//i.test(t) ? [Qt.url(t)] : [] }
                    onEntered: d => { if (!urlsOf(d).length) { d.accepted = false; return } dock.hoverIndex = cell.index }
                    onExited: if (dock.hoverIndex === cell.index) dock.hoverIndex = -2
                    onDropped: d => { const u = urlsOf(d); if (!u.length) return; d.accept(Qt.CopyAction); dock.hoverIndex = -2; dock.openUrls(cell.index, u) } }
                // the wheel over an app with several windows walks through them; whole notches only, and one step per 160 ms
                // so a free-spinning wheel does not race through the group
                WheelHandler { target: null; enabled: cell.windows > 1 && !dock.editing; acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    property real acc: 0
                    onWheel: ev => { if (wheelCool.running) return; acc += ev.angleDelta.y; if (Math.abs(acc) < 100) return; const dir = acc > 0 ? -1 : 1; acc = 0; wheelCool.restart(); dock.cycleWindows(cell.index, dir) } }
                Timer { id: wheelCool; interval: 160 }

                // drag to reorder: the icon follows the pointer; passing half a cell swaps places in the model
                property real dragX: 0
                property int dragShift: 0
                z: drag.active ? 10 : 0
                DragHandler { id: drag; target: null; xAxis.enabled: true; yAxis.enabled: false; dragThreshold: 8
                    onActiveChanged: {
                        dock.dragging = active;
                        if (active) { dock.previewShown = false; openTimer.stop(); cell.dragShift = 0; }
                        else { cell.dragX = 0; dock.tasksModel.syncLaunchers(); dock.saveLaunchers(); }
                    }
                    onTranslationChanged: {
                        if (!active) return;
                        const w = Config.dockCell; let x = translation.x - cell.dragShift * w;
                        const n = dock.tasksModel.count;
                        if (x > w / 2 && cell.index < n - 1) { dock.tasksModel.move(cell.index, cell.index + 1); cell.dragShift += 1; x -= w; }
                        else if (x < -w / 2 && cell.index > 0) { dock.tasksModel.move(cell.index, cell.index - 1); cell.dragShift -= 1; x += w; }
                        cell.dragX = x;
                    } }
                Behavior on dragX { enabled: !drag.active; Spring {} }

                Spotlight { visible: Config.dockSpotlight; anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 1; strength: model.IsActive ? 0.36 : (cell.hovered || drag.active ? 0.16 : 0) }
                Item { id: icon; anchors.horizontalCenter: parent.horizontalCenter; anchors.horizontalCenterOffset: cell.dragX + Math.round(cell.wiggleX); anchors.bottom: parent.bottom; anchors.bottomMargin: (dockH - Config.dockIcon) / 2 + cell.hop
                    width: Config.dockIcon * (drag.active ? Config.dockMagnify : cell.mag); height: width
                    Behavior on width { Spring {} }
                    // The picture itself is rendered once, at the magnified size, and only scaled into this box. Animating the
                    // icon's own size re-rasterised it on the GUI thread every frame, which made a popup that opened during the
                    // hover zoom (the launcher, clicked fast) stutter.
                    Kirigami.Icon { readonly property int full: Math.round(Config.dockIcon * Config.dockMagnify)
                        width: full; height: full; source: model.decoration; roundToIconSize: false
                        transformOrigin: Item.TopLeft; scale: icon.width / full } }
                // unread badge / progress reported by the app
                Rectangle { visible: Config.dockBadges && !!(cell.badge && cell.badge["count-visible"] && cell.badge["count"] > 0); anchors.right: icon.right; anchors.top: icon.top; anchors.rightMargin: -4; anchors.topMargin: -2
                    height: 17; width: Math.max(17, badgeText.implicitWidth + 9); radius: 8.5; color: "#e5484d"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.35)
                    Text { id: badgeText; anchors.centerIn: parent; text: cell.badge ? (cell.badge["count"] > 99 ? "99+" : String(cell.badge["count"] || "")) : ""; color: "white"; font.pixelSize: 10; font.weight: Font.Bold } }   // literal-ok: text on a red badge
                // progress (a copy job, a download): a thin bar along the icon's bottom edge, above the window pills
                Rectangle { visible: Config.dockBadges && !!(cell.badge && cell.badge["progress-visible"]); anchors.horizontalCenter: icon.horizontalCenter; anchors.bottom: icon.bottom; anchors.bottomMargin: 1; width: Math.round(icon.width * 0.8); height: 3; radius: 1.5; color: Qt.rgba(0, 0, 0, 0.55)
                    Rectangle { height: parent.height; radius: 1.5; color: "white"; width: Math.round(parent.width * Math.min(1, Math.max(0, (cell.badge && cell.badge["progress"]) || 0)))   // literal-ok: white on the dark track, both modes
                        Behavior on width { NumberAnimation { duration: Config.normal } } } }
                // edit mode: a pinned app can be taken off the dock right here
                Rectangle { id: unpin; visible: dock.editing && cell.pinnedUrl !== ""; z: 5; anchors.right: icon.right; anchors.top: icon.top; anchors.rightMargin: -6; anchors.topMargin: -6
                    width: 19; height: 19; radius: 9.5; color: Qt.rgba(229/255, 72/255, 77/255, uh.hovered ? 1 : 0.92); border.width: 1; border.color: "white"
                    Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 13; font.weight: Font.Bold }   // literal-ok: on a red badge
                    HoverHandler { id: uh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { dock.tasksModel.requestRemoveLauncher(cell.pinnedUrl); dock.saveLaunchers() } } }
                readonly property string pinnedUrl: { dock.launcherRev; const u = model.LauncherUrlWithoutIcon; return (u && u.toString() !== "" && dock.tasksModel.launcherPosition(u) >= 0) ? u.toString() : "" }
                Pills { visible: Config.dockIndicators; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                    count: cell.windows; activeIndex: cell.activeChild; groupActive: model.IsActive; minimized: model.IsMinimized; attention: model.IsDemandingAttention }
                HoverHandler { onHoveredChanged: dock.hoverIndex = hovered ? cell.index : (dock.hoverIndex === cell.index ? -2 : dock.hoverIndex) }
                TapHandler { onTapped: dock.activateCell(cell.index) }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: dock.openMenu(cell.index) }
                TapHandler { acceptedButtons: Qt.MiddleButton; onTapped: { dock.tasksModel.requestNewInstance(dock.tasksModel.makeModelIndex(cell.index)); dock.launched(cell.index) } }
            }
        }
    }

    // launcher content, clipped to the panel while it grows: our own Launcher, or the hosted Kickoff as a fallback
    Item { x: (dock.width - dock.launcherFullW) / 2; y: dock.dockTop - dock.panelH; width: dock.launcherFullW; height: dock.panelH; clip: true
        visible: dock.panelKind === "launcher" && dock.panelUp; opacity: Math.min(1, dock.panelH / 140)
        // built shortly after start (or at the first open, whichever comes first): reading every installed app and building
        // the grid was ~50 ms of the start-up path
        Loader { id: nativeLauncher; active: Config.nativeLauncher && dock.warm; y: dock.lobePad; width: dock.launcherFullW; height: dock.launcherFullH
            sourceComponent: Launcher { open: dock.launcherOpen && Config.nativeLauncher; onDone: dock.launcherOpen = false } }
        Loader { id: kickoffLoader; active: !Config.nativeLauncher; y: dock.lobePad; width: dock.launcherFullW; height: dock.launcherFullH
            sourceComponent: AppletHost { plugin: "onur.kickoffglow"; zone: "lobe"
                expanded: dock.launcherOpen
                onExpandedChanged: if (!expanded && dock.launcherOpen) dock.launcherOpen = false } }   // Kickoff closes itself after launching
    }
    // window previews of the hovered app
    Item { id: pvBox; clip: true; visible: dock.previewGrow > 0.002 && dock.panelKind !== "launcher"
        readonly property real h: dock.pvLobeMode ? dock.lobeH : dock.panelH
        x: dock.pvLobeMode ? dock.lobeX : (dock.width - dock.pvW) / 2; y: dock.dockTop - h; width: dock.pvW; height: h; opacity: Math.min(1, h / 90)
        HoverHandler { id: pvHover; onHoveredChanged: if (hovered) closeTimer.stop(); else if (dock.hoverIndex < 0) closeTimer.restart() }
        Column { x: 8; y: 8; width: parent.width - 16; visible: dock.lobeMode === "menu"
            Repeater { model: dock.lobeMode === "menu" ? dock.menuItems : []
                Rectangle { required property var modelData; width: parent.width; height: 34; radius: 10; color: Config.fg(mh.hovered ? 0.10 : 0)
                    Behavior on color { ColorAnimation { duration: Config.quick } }
                    Kirigami.Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; source: parent.modelData.icon; isMask: true; color: Config.ink }
                    Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; color: Config.ink; font.pixelSize: 13 }
                    HoverHandler { id: mh }
                    TapHandler { onTapped: dock.runMenu(parent.modelData.act) } } } }
        Row { x: 8; y: 8; spacing: 8; visible: dock.lobeMode === "windows"
            Repeater { model: dock.lobeMode === "windows" ? dock.previewWindows : []
                WindowPreview { required property var modelData
                    width: dock.tW; height: dock.tH; title: modelData.title; uuid: modelData.uuid; icon: dock.previewIcon; isActive: modelData.active
                    function idx() { return modelData.child >= 0 ? dock.tasksModel.makeModelIndex(dock.previewIndex, modelData.child) : dock.tasksModel.makeModelIndex(dock.previewIndex) }
                    onPeek: on => dock.peek(on ? modelData.uuid : "")
                    onActivate: { dock.tasksModel.requestActivate(idx()); dock.previewShown = false }
                    onClose: dock.tasksModel.requestClose(idx()) } } }
        // the app's volume (see refreshAppStreams). Every stream of the app moves together: one slider.
        Item { id: audioRow; visible: dock.lobeMode === "windows" && dock.hasAudio; x: 8; y: 8 + dock.tH + 4; width: dock.pvW - 16; height: dock.audioRowH
            readonly property int pct: { dock.audioRev; return dock.audio ? dock.audio.volumePct() : 0 }
            readonly property bool muted: { dock.audioRev; return dock.audio ? dock.audio.muted() : false }
            Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: Config.fg(0.08) }
            Rectangle { id: ab; x: 6; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; radius: 14; color: Config.fg(abh.hovered ? 0.12 : 0.06)
                Behavior on color { ColorAnimation { duration: Config.quick } }
                Kirigami.Icon { anchors.centerIn: parent; width: 15; height: 15; isMask: true; color: Config.ink
                    source: audioRow.muted || audioRow.pct === 0 ? "audio-volume-muted-symbolic" : audioRow.pct < 34 ? "audio-volume-low-symbolic" : audioRow.pct < 67 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic" }
                HoverHandler { id: abh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: if (dock.audio) dock.audio.setMuted(!audioRow.muted) } }
            GlassSlider { anchors.left: ab.right; anchors.leftMargin: 10; anchors.right: apct.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                from: 0; to: 100; step: 1; value: audioRow.pct; opacity: audioRow.muted ? 0.45 : 1     // muted: the level is kept but greyed, so "100 % and silent" reads as what it is
                onMoved: v => { if (dock.audio) dock.audio.setVolumePct(v, true) }
                onCommitted: v => { if (dock.audio) dock.audio.setVolumePct(v, false) } }
            Text { id: apct; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 44; horizontalAlignment: Text.AlignRight
                text: audioRow.muted ? "muted" : audioRow.pct + "%"; color: Config.inkDim; font.pixelSize: 12; font.features: { "tnum": 1 } } } }
    Shortcut { sequence: "Escape"; onActivated: { dock.launcherOpen = false; dock.previewShown = false } }
    function argAfter(flag) { const a = Qt.application.arguments; const i = a.indexOf(flag); return i >= 0 && i + 1 < a.length ? parseInt(a[i + 1]) : -1 }
    Timer { running: dock.argAfter("--preview") >= 0; interval: 4000; onTriggered: dock.openPreview(dock.argAfter("--preview")) }      // capture/self-test hooks
    Timer { running: dock.argAfter("--menu") >= 0; interval: 4000; onTriggered: dock.openMenu(dock.argAfter("--menu")) }
    Timer { running: dock.argAfter("--tap") >= 0; interval: 5000; onTriggered: { console.log("selftest tap", dock.argAfter("--tap")); dock.activateCell(dock.argAfter("--tap")) } }
    // The dock never takes keyboard focus on a click: the clicked app has to still be the active one, or "is it focused?"
    // (minimise on second click, cycle to the NEXT window) can never be true. Only the open launcher wants keys.
    Component.onCompleted: { Shell.dbusListen("", "", "com.canonical.Unity.LauncherEntry", "Update"); Shell.setKeyboardMode(dock, "none"); if (Qt.application.arguments.indexOf("--open-launcher") >= 0) launcherOpen = true }
}
