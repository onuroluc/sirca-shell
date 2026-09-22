import QtQuick
import org.kde.taskmanager as TaskManager
import SircaShell

QtObject {
    id: main
    // ---- one set (wallpaper + bar + dock) per screen; main.topBar / main.dock are the PRIMARY screen's, which the rest of
    // the shell (shortcuts, D-Bus, popups) talks to. See ScreenSet.qml.
    // (Qt.application.screens is a plain list: an Instantiator gives its delegates an index only, so the screen is looked up)
    property var sets: Instantiator { model: Qt.application.screens.length; delegate: ScreenSet { required property int index; screen: Qt.application.screens[index]; host: main }
        onObjectAdded: (i, o) => main.rescan(); onObjectRemoved: (i, o) => main.rescan() }
    property var primarySet: null
    function rescan() { let p = null; for (let i = 0; i < sets.count; ++i) { const o = sets.objectAt(i); if (o && o.primary) { p = o; break } } if (!p && sets.count) p = sets.objectAt(0); primarySet = p }
    property var _ps: Connections { target: Shell; function onPrimaryScreenChanged() { main.rescan() } }
    readonly property var topBar: primarySet ? primarySet.bar : null
    readonly property var dock: primarySet ? primarySet.dock : null
    // what every bar and dock reads (the task model is global; the flags used to live on the one dock)
    readonly property bool fullscreenActive: dock ? dock.fullscreenActive : false
    readonly property bool gameActive: dock ? dock.gameActive : false
    property bool launcherOpen: dock ? dock.launcherOpen : false
    onLauncherOpenChanged: if (dock && dock.launcherOpen !== launcherOpen) dock.launcherOpen = launcherOpen
    function closeLobes() { for (let i = 0; i < sets.count; ++i) { const o = sets.objectAt(i); if (o && o.bar) o.bar.openLobe = "" } }
    function openDesktopMenu(screen, x, y) { const m = win("desktopMenu"); if (!m.visible) m.screen = screen; m.openAt(x, y) }

    // ---- Alt+Tab
    // the clipboard manager lives for the whole session (it keeps the clipboard alive), the panel only shows it
    property var clipboard: ClipboardModel {}
    // ---- windows that are not on screen at start are built on first use, not at start-up (they were 8 full-screen or
    // large windows' worth of QML in the start-up path). warm builds them one by one once the shell has settled, so the
    // first Alt+Tab or Meta+Space does not pay for it either.
    property var _made: ({})
    readonly property var _lazy: ({ clipboardPanel: _cClipboardPanel, powerMenu: _cPowerMenu, welcome: _cWelcome, capture: _cCapture, settings: _cSettings, switcher: _cSwitcher, search: _cSearch, tiles: _cTiles, editScene: _cEdit, desktopMenu: _cDesktopMenu })
    function win(name) { let w = _made[name]; if (!w) { const t = Date.now(); w = _lazy[name].createObject(main); _made[name] = w; if (!w) console.warn("could not build", name, _lazy[name].errorString()); else console.log("start-up: built", name, "in", Date.now() - t, "ms") } return w }
    function closePopups() { main.closeLobes(); for (let i = 0; i < sets.count; ++i) { const o = sets.objectAt(i); if (o && o.dock) { o.dock.launcherOpen = false; o.dock.previewShown = false } } }
    property var _warm: Timer { interval: 2500; running: true; repeat: true; property var todo: ["switcher", "search", "clipboardPanel", "tiles", "powerMenu", "capture", "settings"]
        onTriggered: { interval = 200; const n = todo.shift(); if (n) main.win(n); if (todo.length === 0) stop() } }
    property var _cClipboardPanel: Component { ClipboardPanel { entries: main.clipboard; onOpened: main.closePopups() } }
    property var _cPowerMenu: Component { PowerMenu { onOpened: main.closePopups() } }
    property var _cWelcome: Component { Welcome { onOpened: main.closePopups() } }
    // first run (no "welcomed" key in the config): the card comes up once, a few seconds after the bar and dock
    property var _welcomeOnce: Timer { interval: 4000; running: Config.get("welcomed", false) !== true; onTriggered: if (Config.get("welcomed", false) !== true) main.win("welcome").open() }
    property var _cCapture: Component { Capture { onOpened: main.closePopups(); onRecordRequested: (x, y, w, h) => main.recorder.start(x, y, w, h) } }
    // every visible window's frame, top-most first, for "click = that window" in the screenshot overlay
    function windowRects() {
        const m = windows; if (!m) return []; const R_ = TaskManager.AbstractTasksModel; const out = [];
        for (let i = 0; i < m.count; ++i) { const idx = m.makeModelIndex(i); if (m.data(idx, R_.IsMinimized)) continue
            const g = m.data(idx, R_.Geometry); if (g && g.width > 0) out.push({ x: g.x, y: g.y, width: g.width, height: g.height, z: m.data(idx, R_.StackingOrder) }) }
        out.sort((a, b) => b.z - a.z); return out }
    property var _dmr: Connections { target: Shell; function onDesktopMenuRequested(x, y) { if (x < 0) main.win("desktopMenu").close_(); else main.win("desktopMenu").openAt(x, y) } }   // negative = close
    property var _cDesktopMenu: Component { DesktopMenu { onOpened: main.closePopups(); onAction: id => main.desktopAction(id) } }
    function desktopAction(id) {
        if (id === "wallpaper") win("settings").openIt(4)
        else if (id === "edit") setEditing(true)
        else if (id === "glass") win("settings").openIt()
        else if (id === "terminal") Shell.runDetached(Shell.defaultTerminal(), [])
        else if (id === "files") Shell.runDetached("xdg-open", [Shell.homePath()])
        else if (id === "displays") Shell.runDetached("systemsettings", ["kcm_kscreen"])
        else if (id === "system") Shell.runDetached("systemsettings", [])
        else if (id === "lock") Shell.dbusSend("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver", "Lock")
        else if (id === "power") { const p = win("powerMenu"); p.dryRun = false; p.toggle() }
        else if (id === "mode") { const want = Config.dark ? "light" : "dark"; Shell.saveConfigKey("mode", want); if (Shell.hasProgram("glass-mode")) Shell.runDetached("glass-mode", [want]) }
        else if (id.startsWith("theme:")) { const n = id.substring(6); if (Shell.hasProgram("glass-mode")) Shell.runDetached("glass-mode", ["theme", n]); else { const t = Config.themes[n]; Shell.saveConfigKeys({ theme: n, accent: t.accent, wallpaper: Config.dark ? t.dark : t.light }) } }
    }
    property var _cSettings: Component { Settings {} }
    property var _cSwitcher: Component { Switcher {} }
    property var recorder: Recorder {}
    property var _rr: Connections { target: Shell; function onRecordRegionRequested(x, y, w, h) { main.recorder.start(x, y, w, h) } }
    // scripted screenshot without the overlay: grab a frame, cut the rectangle out of it
    property rect _grabRect
    property bool _grabPending: false
    property var _gr: Connections { target: Shell; function onGrabRegionRequested(x, y, w, h) { main._grabRect = Qt.rect(x, y, w, h); main._grabPending = true; Screenshot.grab(Qt.application.screens[0].name) } }
    property var _gr2: Connections { target: Screenshot; function onFrameChanged() { if (!main._grabPending || !Screenshot.ready) return; main._grabPending = false
        const r = main._grabRect; const p = Screenshot.finish(r.x, r.y, r.width, r.height, Qt.application.screens[0].width, true, true); Screenshot.drop(); console.log("grabRegion ->", p) } }
    // the lock screen wears the desktop's look: when the wallpaper, mode or accent changes, its state file is rewritten
    // (glass-lock-sync comes with Glass Desktop's lock screen; without it this does nothing)
    readonly property string lockLook: Config.get("wallpaper", "") + "|" + Config.get("mode", "dark") + "|" + Config.get("accent", "")
    onLockLookChanged: lockSync.restart()
    property var _lockSync: Timer { id: lockSync; interval: 900; onTriggered: if (Shell.hasProgram("glass-lock-sync")) Shell.runDetached("glass-lock-sync", []) }
    property var _themeLater: Timer { id: themeLater; interval: 350; onTriggered: { const q = main.topBar.nativeControl; if (q && q.paletteOpen !== undefined) q.paletteOpen = true } }
    // ---- edit mode (right click on the bar or the dock, or D-Bus toggleEditMode)
    property bool editing: false
    function setEditing(on) { if (on === editing) return; if (on) closePopups(); editing = on; const s = win("editScene"); if (on) s.open(); else s.close_() }
    property var _cEdit: Component { EditScene {
        screen: main.primarySet ? main.primarySet.screen : null
        barHole: main.topBar ? Qt.rect(main.topBar.x + main.topBar.barRect.x - 30, 0, main.topBar.barRect.width + 60, main.topBar.barRect.y + main.topBar.barRect.height + 10) : Qt.rect(0, 0, 0, 0)
        dockHole: main.dock ? Qt.rect(main.dock.x + main.dock.barRect.x - 12, main.dock.y + main.dock.barRect.y - 12, main.dock.barRect.width + 24, main.dock.barRect.height + 24) : Qt.rect(0, 0, 0, 0)
        onDone: main.setEditing(false); onMoreSettings: { main.setEditing(false); main.win("settings").openIt() } } }
    property var _cTiles: Component { Tiles { onOpened: main.closePopups() } }
    property var _cSearch: Component { Search { onOpened: main.closePopups() } }
    property var _sw: Connections { target: Shell; function onSwitcherRequested(reverse) { main.topBar.openLobe = ""; main.dock.launcherOpen = false; main.win("switcher").step(reverse) } }

    // ---- the shell's own global shortcuts (window operations are already done in C++; these are the shell-side ones)
    property var _keys: Connections { target: Shell
        function onLobeToggleRequested(name) { if (name === "media") { if (!main.topBar.mediaAvailable) return; if (main.topBar.openLobe !== "media") main.topBar.placeMedia() } main.topBar.toggle(name) }
        function onTrayMenuRequested(i) { main.topBar.openTrayMenuAt(i) }
        function onSettingsRequested() { main.win("settings").openIt() }
        function onSearchPreviewRequested(q) { main.win("search").preview(q) }
        function onShortcutActivated(id) {
            if (id === "search") { main.win("search").toggle(); return }
            if (id === "record") { main.recorder.toggleOrAsk(() => { const c = main.win("capture"); c.dryRun = false; c.mode = "record"; c.begin(main.windowRects(), "") }); return }
            if (id === "screenshot" || id === "screenshot-2") { main.win("capture").mode = "shot"; main.win("capture").dryRun = false; main.win("capture").begin(main.windowRects(), ""); return }
            if (id === "screenshot-preview") { main.win("capture").dryRun = true; main.win("capture").begin(main.windowRects(), Config.wallpaper !== "" ? Config.wallpaper : Shell.plasmaWallpaper()); return }
            if (id === "theme-picker") { main.topBar.openLobe = "gear"; themeLater.restart(); return }
            if (id === "edit") { main.setEditing(!main.editing); return }
            if (id === "tiles" || id === "tiles-preview") { const t = main.win("tiles"); t.dryRun = id === "tiles-preview"; t.toggle(); return }
            if (id === "clipboard") { main.win("clipboardPanel").toggle(); return }
            if (id === "welcome") { main.win("welcome").open(); return }
            if (id === "power") { main.win("powerMenu").dryRun = false; main.win("powerMenu").toggle(); return }
            if (id === "power-preview") { main.win("powerMenu").dryRun = true; main.win("powerMenu").toggle(); return }
            if (id === "show-desktop") Shell.setShowingDesktop(!main.showingDesktop);
            else if (id.startsWith("dock-")) { const n = parseInt(id.substring(5)) - 1; if (main.dock.tasksModel && n < main.dock.tasksModel.count) main.dock.activateCell(n); }
        } }

    // ---- click outside closes whatever is open
    readonly property bool popupOpen: !!topBar && !!dock && (topBar.openLobe !== "" || dock.launcherOpen || (dock.previewShown && dock.lobeMode === "menu"))
    // (no click catcher any more: popups close on focus loss, see Surface.popupFocus. Catcher.qml is unused.)
    // a press on one of our surfaces closes the OTHER surface's popups (that one keeps the keyboard focus, because the
    // pressed surface does not take it, so focus loss alone would not notice)
    property var _cross: Connections { target: main.dock; function onPressedAnywhere() { if (main.topBar.openLobe !== "") main.topBar.openLobe = "" } }
    property var _cross2: Connections { target: main.topBar; function onPressedAnywhere() { if (main.dock.launcherOpen) main.dock.launcherOpen = false; if (main.dock.previewShown && main.dock.lobeMode === "menu") main.dock.previewShown = false } }

    // ---- window watcher for dodging: every visible window on this desktop, ungrouped, with its geometry
    property int rev: 0
    // Show Desktop (Meta+D) hides every window but leaves its geometry alone, so the overlap test alone would keep the
    // bars away from an empty desktop. KWin announces the state; nothing is covered while it is on.
    property bool showingDesktop: false
    property var _sd: Connections { target: Shell
        function onDbusSignal(iface, member, args) { if (iface === "org.kde.KWin" && member === "showingDesktopChanged") { if (main.dbg) console.log("showingDesktopChanged", args[0]); main.showingDesktop = !!args[0] } } }
    Component.onCompleted: {
        Shell.dbusListen("org.kde.KWin", "/KWin", "org.kde.KWin", "showingDesktopChanged");
        main.showingDesktop = !!Shell.dbusCall("org.kde.KWin", "/KWin", "org.freedesktop.DBus.Properties", "Get", ["org.kde.KWin", "showingDesktop"]);
    }
    property var windows: null
    property var _vd: TaskManager.VirtualDesktopInfo { id: vdInfo }
    property var _act: TaskManager.ActivityInfo { id: actInfo }
    property var _late: Timer { interval: 1200; running: true; onTriggered: { main.windows = watchComp.createObject(main); bump.kick() } }
    // a throttle, not a debounce: a window being dragged reports its frame continuously, and restarting the timer on every
    // report kept the bars from reacting until the drag paused. kick() lets the first report through within one frame.
    property var _bump: Timer { id: bump; interval: 16; onTriggered: main.rev++; function kick() { if (!running) start() } }
    property var _comp: Component { id: watchComp
        TaskManager.TasksModel {
            groupMode: TaskManager.TasksModel.GroupDisabled
            sortMode: TaskManager.TasksModel.SortDisabled
            filterByVirtualDesktop: true; virtualDesktop: vdInfo.currentDesktop
            filterByActivity: true; activity: actInfo.currentActivity
            // (filterNotMinimized would keep ONLY minimised windows; minimised ones are skipped in overlaps() instead)
            onDataChanged: bump.kick()
            onCountChanged: bump.kick()
            onRowsInserted: bump.kick()
            onRowsRemoved: bump.kick()
            onModelReset: bump.kick()
            onVirtualDesktopChanged: bump.kick()
            onActiveTaskChanged: { main.refreshActive(); bump.kick() }
        } }
    readonly property bool dbg: Qt.application.arguments.indexOf("--debug") >= 0
    // the focused window, for the bar's title element (this model is ungrouped, so it is the real window, not its group)
    property string activeTitle: ""
    property string activeApp: ""
    property var activeIcon
    onRevChanged: refreshActive()
    function refreshActive() {
        const m = windows; const R_ = TaskManager.AbstractTasksModel; let a = null;
        // scan for the active row: `activeTask` stays invalid until the first activation change after the model is built
        if (m && !showingDesktop) for (let i = 0; i < m.count; ++i) { const idx = m.makeModelIndex(i); if (m.data(idx, R_.IsActive)) { a = idx; break; } }
        if (dbg) console.log("refreshActive", a ? m.data(a, 0) : "-", m ? m.count : -1, showingDesktop);
        if (!a) { activeTitle = ""; activeApp = ""; activeIcon = undefined; return; }
        activeTitle = m.data(a, 0) || ""; activeApp = m.data(a, R_.AppName) || ""; activeIcon = m.data(a, 1);
    }
    property var _slow: Timer { interval: 2500; running: true; repeat: true; onTriggered: main.refreshActive() }   // titles change without a model signal we can rely on
    onShowingDesktopChanged: refreshActive()
    function overlaps(r) {
        const m = windows; if (!m) return false;
        const G = TaskManager.AbstractTasksModel.Geometry;
        if (dbg) { let t = []; for (let i = 0; i < m.count; ++i) t.push(m.data(m.makeModelIndex(i), TaskManager.AbstractTasksModel.AppId) + " " + m.data(m.makeModelIndex(i), G)); console.log("overlaps?", r, t.join(" | ")); }
        for (let i = 0; i < m.count; ++i) {
            if (m.data(m.makeModelIndex(i), TaskManager.AbstractTasksModel.IsMinimized)) continue;
            const g = m.data(m.makeModelIndex(i), G);
            if (g && g.width > 0 && g.x < r.x + r.width && g.x + g.width > r.x && g.y < r.y + r.height && g.y + g.height > r.y) return true;
        }
        return false;
    }
}
