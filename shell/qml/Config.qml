// Design tokens + user config. Defaults reproduce the current Plasma look; ~/.config/sirca-shell/config.json overrides keys.
pragma Singleton
import QtQuick
import SircaShell

QtObject {
    id: cfg
    // re-read whenever the file changes (Shell.configRevision bumps): the settings window and hand edits apply live
    function load(revision) { return Shell.loadConfig() }          // the argument is the dependency; a bare read gets optimised away
    readonly property var user: load(Shell.configRevision)
    function get(key, fallback) { return (user && user[key] !== undefined) ? user[key] : fallback }

    // ---- light / dark. `mode` is written by the quick-settings toggle (tools: glass-mode, which also switches the KDE colour
    // scheme, GTK, icons and the wallpaper). Everything drawn ON the glass goes through fg(): white in dark mode, near-black in
    // light mode. Things that sit on a coloured fill (badges, the record pill's dot, accent buttons) stay literally white.
    // colour themes: { name: { accent: "#rrggbb", light: "/wallpaper", dark: "/wallpaper" } } from the config; `theme` is the
    // current one. Picking one (quick settings, or glass-mode theme NAME) sets the accent and the two wallpapers.
    readonly property var themes: get("themes", ({}))
    readonly property string theme: get("theme", "")
    readonly property string mode: get("mode", "dark")
    readonly property bool dark: mode !== "light"
    // `lt` runs 0 -> 1 over a quarter second when the mode flips, and every mode-dependent colour below is a MIX by it:
    // the whole shell cross-fades between its two looks instead of jumping. (Places that read `dark` directly still flip at once.)
    property real lt: dark ? 0 : 1
    Behavior on lt { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }
    function mix(a, b) { const t = lt; return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t) }
    function mixn(a, b) { return a + (b - a) * lt }
    // Light mode, third attempt (onur: flipped black = "black accents" no; everything in the theme colour = "too much"):
    // NEUTRAL slate for text, glyphs and overlays, with only a breath of the theme's hue in it, and the accent itself kept
    // for the few things that are ON (a switched-on tile's disc, a switch, today's date) and for the glow.
    //   tone(k): slate at depth k (0 = mid grey-blue, 1 = near black), 10 % of the accent mixed in so it is not dead grey
    function tone(k) { const c = accent; const base = 0.42 - 0.30 * k; const t = 0.10
        return Qt.rgba(base * (1 - t) + c.r * t * (1 - k * 0.6), base * (1 - t) + c.g * t * (1 - k * 0.6), (base + 0.03) * (1 - t) + c.b * t * (1 - k * 0.6), 1) }
    readonly property color onFill: mix(Qt.rgba(1, 1, 1, 0.92), accent)      // the fill of something that is ON; text on it: onFg
    readonly property color lightFg: tone(0.55)
    function fg(a) { return mix(Qt.rgba(1, 1, 1, a), Qt.rgba(lightFg.r, lightFg.g, lightFg.b, Math.min(1, a * 1.3))) }
    // colour haze (the blurred copy of icons / cover art under them). On light glass it must stay COLOUR: a strong saturation
    // boost and only a small lift, so a coloured icon leaves a clear tint and a dark one only a faint shade
    readonly property real hazeFactor: dark ? 1.0 : 1.0
    readonly property real hazeLift: mixn(0.04, 0.16)
    readonly property real hazeSaturation: mixn(0.55, 1.6)
    readonly property color fgSolid: mix(Qt.rgba(1, 1, 1, 1), tone(0.50))
    readonly property color glow: mix(Qt.rgba(1, 1, 1, 1), accent)                 // what an "open" icon glows in
    readonly property color onFg: mix(Qt.color("#1b1d20"), Qt.color("#ffffff"))        // text / glyphs on a filled fg shape (today's date, a switched-on tile)
    // solid little surfaces that float over other content (tooltips) and the settings window's sidebar
    readonly property color popSurface: mix(Qt.rgba(24/255, 25/255, 27/255, 0.94), Qt.rgba(0.985, 0.985, 0.99, 0.96))
    readonly property color sidebarTint: mix(Qt.rgba(24/255, 25/255, 27/255, 0.62), Qt.rgba(244/255, 245/255, 248/255, 0.46))
    // the glass body: a dark smoke in dark mode, milk in light mode (which needs more of it to carry dark text)
    // milk: how much denser the light glass is than the dark one. 0.60 for popups (text over anything); the bar passes less
    function glassTint(a, milk) { return mix(Qt.rgba(32/255, 35/255, 38/255, a), Qt.rgba(0.975, 0.98, 0.99, Math.min(0.94, a + (milk === undefined ? 0.60 : milk)))) }   // milk has to be dense enough that dark text reads over a busy window behind it

    // material
    readonly property color tint: glassTint(get("tintAlpha", 0.15))
    readonly property color rim: Qt.rgba(1, 1, 1, get("rimAlpha", 0.09) * mixn(1, 3.2))
    readonly property real sheen: get("sheenAlpha", 0.06) * mixn(1, 2.5)
    readonly property color ink: mix(Qt.color("#eff0f1"), tone(0.85))
    readonly property color inkDim: mix(Qt.rgba(239/255, 240/255, 241/255, 0.68), Qt.rgba(tone(0.75).r, tone(0.75).g, tone(0.75).b, 0.74))
    function hex(c) { const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2); return "#" + h(c.a) + h(c.r) + h(c.g) + h(c.b) }   // #AARRGGBB for StyledText
    readonly property color attention: "#f6a03a"
    readonly property color accent: get("accent", "#4c6ed6")         // selection frames, edit mode, primary buttons (the desktop itself stays monochrome)
    readonly property real cornerRadius: get("cornerRadius", 22)

    // motion
    readonly property int bounceRoom: 24               // extra outline height so a lobe's overshoot still has glass behind it
    readonly property int quick: 120
    readonly property int normal: 220
    readonly property int slow: 320

    // top bar
    // Default bar width follows ITS monitor: 46.4 % of its width (= 2374 px on the 5120-wide screen this was designed on),
    // but never narrower than what the bar's content needs (1400 px) and never wider than the screen minus a margin.
    // Each bar passes its own Screen.width to barWidthAutoFor (a second screen is rarely the same size); barWidthAuto is
    // the primary screen's value, for the settings pages. A width set by the user (edit mode / settings) wins.
    readonly property int screenWidth: Qt.application.screens.length > 0 ? Qt.application.screens[0].width : 1920
    function barWidthAutoFor(w) { return Math.round(Math.max(Math.min(1400, w - 48), Math.min(w - 48, w * 0.46367))) }
    readonly property int barWidthAuto: barWidthAutoFor(screenWidth)
    readonly property int barWidth: get("barWidth", barWidthAuto)
    // "auto" = scaled to the monitor (above), "fill" = the whole screen width minus barFillMargin on each side,
    // "fit" = as wide as its widgets need, "custom" = barWidth from the config
    readonly property string barWidthMode: get("barWidthMode", user && user["barWidth"] !== undefined ? "custom" : "auto")
    readonly property int barFillMargin: get("barFillMargin", 8)
    readonly property int barPad: get("barPad", 20)                  // air between the bar's ends and its first / last widget
    readonly property int barSpacing: get("barSpacing", 16)          // air between two widgets
    // which widgets, where, in which order. Names: desktop workspaces tray title clock date system media bell gear
    readonly property var barLeft: get("barLeft", ["desktop", "workspaces", "tray", "title"])
    // weather (Open-Meteo, network): "weather": true/false decides; with no key, placing the bar widget counts as the opt-in
    readonly property bool weatherOn: user && user.weather !== undefined ? user.weather === true : (barLeft.indexOf("weather") >= 0 || barCenter.indexOf("weather") >= 0 || barRight.indexOf("weather") >= 0)
    readonly property var barCenter: get("barCenter", ["clock"])
    readonly property var barRight: get("barRight", ["media", "bell", "gear"])
    // …plus "user:<name>" for every folder in ~/.config/<app>/widgets (UserWidgets, watched: a new widget appears in the edit shelf at once)
    readonly property var barWidgetNames: { const m = { desktop: "Show desktop", workspaces: "Workspaces", tray: "Tray", title: "Window title", clock: "Clock", date: "Date",
                                                        system: "CPU / memory", media: "Now playing", bell: "Notifications", gear: "Quick settings", weather: "Weather",
                                                        battery: "Battery", mic: "Microphone", privacy: "Privacy", keyboard: "Keyboard layout",
                                                        "tile:volume": "Volume", "tile:network": "Network", "tile:bluetooth": "Bluetooth", "tile:dnd": "Do Not Disturb", "tile:nightlight": "Night Light",
                                                        "tile:power": "Power profile", "tile:caffeine": "Caffeine", "tile:mic": "Microphone (tile)" }
        const u = UserWidgets.names; for (let i = 0; i < u.length; ++i) m["user:" + u[i]] = UserWidgets.label(u[i]); return m }   // (a QStringList is not iterable with for…of)
    readonly property int titleMaxWidth: get("titleMaxWidth", 420)
    readonly property bool titleIcon: get("titleIcon", true)
    readonly property bool clock24h: get("clock24h", false)
    readonly property bool clockSeconds: get("clockSeconds", false)
    readonly property bool clockDate: get("clockDate", false)          // date inside the clock pill
    readonly property bool clockBold: get("clockBold", true)
    readonly property string dateFormat: get("dateFormat", "ddd d MMM")
    readonly property bool barHoverPills: get("barHoverPills", true)   // the soft pill behind a widget under the pointer
    readonly property real barIconScale: get("barIconScale", 1.0)
    // look, per surface (each falls back to the shared value from Appearance)
    readonly property bool barBlur: get("barBlur", true)
    readonly property real barTintAlpha: get("barTintAlpha", 0.62)        // dark mode: the bar wears the THEME's app glass (24,25,27 at 62 %), like title bars and sidebars
    readonly property color barTint: mix(Qt.rgba(24/255, 25/255, 27/255, barTintAlpha), Qt.rgba(0.975, 0.98, 0.99, Math.min(0.94, get("barTintAlphaLight", 0.15) + barMilk)))
    readonly property real barMilk: get("barMilk", 0.36)                 // light mode: the bar was 75 % white, which on a light wallpaper reads as a solid strip, not glass
    readonly property real barRimAlpha: get("barRimAlpha", get("rimAlpha", 0.09))
    readonly property real barSheen: get("barSheen", get("sheenAlpha", 0.06))
    readonly property real barShadow: get("barShadow", 0.55)
    readonly property bool dockBlur: get("dockBlur", true)
    readonly property real dockTintAlpha: get("dockTintAlpha", get("tintAlpha", 0.15))
    readonly property real dockRimAlpha: get("dockRimAlpha", get("rimAlpha", 0.09))
    readonly property real dockSheen: get("dockSheen", get("sheenAlpha", 0.06))
    readonly property real dockShadow: get("dockShadow", 0.55)
    // ---- visibility (#7): "always" reserves space (windows never touch the surface), "dodge" slides it away under a
    // window (the old default), "below" keeps it in place with windows going under it. The old barDodge / dodge booleans map.
    readonly property string barVisibility: { const v = get("barVisibility", ""); if (v === "always" || v === "dodge" || v === "below") return v; return get("barDodge", get("dodge", true)) ? "dodge" : "always" }
    readonly property string dockVisibility: { const v = get("dockVisibility", ""); if (v === "always" || v === "dodge" || v === "below") return v; return get("dockDodge", get("dodge", true)) ? "dodge" : "always" }
    readonly property bool barDodge: barVisibility === "dodge"
    readonly property bool dockDodge: dockVisibility === "dodge"
    // ---- the look per state: "touched" (a window lies over the surface's strip), "maximized" (a maximised window on its
    // screen; "touched" = same settings), "fullscreen" (a full-screen window has focus; "hide" = the old behaviour, "keep"
    // = the surface stays, raised above the window). Every state has its own opacity, blur, (bar) width and corners.
    readonly property real barTouchedOpacity: get("barTouchedOpacity", 0.92)
    readonly property bool barTouchedBlur: get("barTouchedBlur", true)
    readonly property string barTouchedWidth: get("barTouchedWidth", "keep")          // "keep" | "fill"
    readonly property string barTouchedCorners: get("barTouchedCorners", "round")     // "round" | "square"
    readonly property string barMaximizedMode: get("barMaximizedMode", "touched")     // "touched" | "custom"
    readonly property real barMaximizedOpacity: get("barMaximizedOpacity", 0.92)
    readonly property bool barMaximizedBlur: get("barMaximizedBlur", true)
    readonly property string barMaximizedWidth: get("barMaximizedWidth", "keep")
    readonly property string barMaximizedCorners: get("barMaximizedCorners", "round")
    readonly property string barFullscreenMode: get("barFullscreenMode", "hide")      // "hide" | "keep"
    readonly property real barFullscreenOpacity: get("barFullscreenOpacity", 1.0)
    readonly property bool barFullscreenBlur: get("barFullscreenBlur", false)
    readonly property string barFullscreenWidth: get("barFullscreenWidth", "fill")
    readonly property string barFullscreenCorners: get("barFullscreenCorners", "square")
    readonly property real dockTouchedOpacity: get("dockTouchedOpacity", get("dockTintAlphaTouched", 0.85))
    readonly property bool dockTouchedBlur: get("dockTouchedBlur", true)
    readonly property string dockMaximizedMode: get("dockMaximizedMode", "touched")
    readonly property real dockMaximizedOpacity: get("dockMaximizedOpacity", 0.85)
    readonly property bool dockMaximizedBlur: get("dockMaximizedBlur", true)
    readonly property string dockFullscreenMode: get("dockFullscreenMode", "hide")
    readonly property real dockFullscreenOpacity: get("dockFullscreenOpacity", 1.0)
    readonly property bool dockFullscreenBlur: get("dockFullscreenBlur", false)
    // the resolved look of a surface in a state: { opacity, blur, width, corners }; opacity < 0 = the normal one
    function lookFor(prefix, state) {
        const norm = { opacity: -1, blur: prefix === "bar" ? barBlur : dockBlur, width: "keep", corners: "round" }
        if (state === "maximized" && (prefix === "bar" ? barMaximizedMode : dockMaximizedMode) === "touched") state = "touched"
        if (state === "touched") return prefix === "bar" ? { opacity: barTouchedOpacity, blur: barTouchedBlur, width: barTouchedWidth, corners: barTouchedCorners } : { opacity: dockTouchedOpacity, blur: dockTouchedBlur, width: "keep", corners: "round" }
        if (state === "maximized") return prefix === "bar" ? { opacity: barMaximizedOpacity, blur: barMaximizedBlur, width: barMaximizedWidth, corners: barMaximizedCorners } : { opacity: dockMaximizedOpacity, blur: dockMaximizedBlur, width: "keep", corners: "round" }
        if (state === "fullscreen") return prefix === "bar" ? { opacity: barFullscreenOpacity, blur: barFullscreenBlur, width: barFullscreenWidth, corners: barFullscreenCorners } : { opacity: dockFullscreenOpacity, blur: dockFullscreenBlur, width: "keep", corners: "round" }
        return norm }
    // the bar's tint at another alpha (a state look): the same dark / light bases as barTint
    function barTintAt(a) { return a < 0 ? barTint : mix(Qt.rgba(24/255, 25/255, 27/255, a), Qt.rgba(0.975, 0.98, 0.99, Math.min(0.97, a))) }
    readonly property int barHeight: get("barHeight", 37)
    readonly property int barGap: get("barGap", 8)
    readonly property int sheetWidth: get("sheetWidth", 440)
    readonly property int sheetHeight: get("sheetHeight", 640)

    readonly property int lobePad: get("lobePad", 10)          // air between a popup's content and the glass edge
    readonly property int clockSize: get("clockSize", 15)

    readonly property bool levelMeter: get("levelMeter", true)  // the bar's now-playing bars follow the real audio level (repaints the bar ~25x a second while music plays)
    readonly property bool recordSound: get("recordSound", true) // screen recordings include what the computer plays (not the microphone)
    readonly property bool showFps: get("showFps", false)       // frame meter on every surface
    readonly property bool dodge: get("dodge", true)            // bars slide away under windows instead of reserving space

    // dock
    readonly property int dockHeight: get("dockHeight", 60)
    readonly property int dockGap: get("dockGap", 8)
    readonly property int dockRadius: get("dockRadius", 20)
    readonly property int dockCell: get("dockCell", 60)
    readonly property int dockIcon: get("dockIcon", 46)
    readonly property string launcherIcon: get("launcherIcon", "start-here-kde-symbolic")
    readonly property string dockWidthMode: get("dockWidthMode", "fit")   // "fit" = as wide as its icons, "fill" = the whole screen width minus dockFillMargin
    readonly property int dockFillMargin: get("dockFillMargin", 8)
    readonly property bool dockIndicators: get("dockIndicators", true)    // the pills under running apps
    readonly property bool dockBadges: get("dockBadges", true)            // unread counts and progress from apps
    readonly property bool dockPreviews: get("dockPreviews", true)        // window previews on hover
    readonly property int dockPreviewDelay: get("dockPreviewDelay", 380)
    readonly property bool dockHop: get("dockHop", true)                  // the icon hops while its app starts
    readonly property bool dockSpotlight: get("dockSpotlight", true)      // the soft light under the hovered icon
    readonly property real barHazeStrength: get("barHazeStrength", 0.26)   // same haze in the top bar; a touch lighter, the bar is thin and busy
    readonly property real hazeStrength: get("hazeStrength", 0.33)   // colour haze under dock icons, 0 = off
    // wallpaper drawn by the shell (background layer). Harmless while plasmashell runs (its desktop covers it).
    // "auto" = only while Plasma's desktop is not running (above it, ours would cover its desktop icons); true / false force it
    readonly property var ownWallpaper: get("ownWallpaper", "auto")
    readonly property string wallpaper: get("wallpaper", "")            // "" = follow what Plasma shows
    readonly property string wallpaperFolder: get("wallpaperFolder", Shell.picturesPath() + "/Wallpapers")   // the xdg Pictures folder, wherever that is
    // the session runs without plasmashell (set by sirca-shell-switch): the shell serves the volume / brightness display itself
    readonly property bool withoutPlasmashell: get("withoutPlasmashell", false)
    onWithoutPlasmashellChanged: Shell.setWithoutPlasmashell(withoutPlasmashell)
    Component.onCompleted: Shell.setWithoutPlasmashell(withoutPlasmashell)
    readonly property bool quietWhenBusy: get("quietWhenBusy", true)      // no notification popups while a game / full-screen window has focus
    readonly property bool nativeCalendar: get("nativeCalendar", true)     // the popup behind the clock: ours, or the hosted digital clock applet
    readonly property bool nativeNotifications: get("nativeNotifications", true)   // cards + history: ours (NotificationManager), or the hosted applet
    readonly property bool nativeTray: get("nativeTray", true)           // tray icons + menus: ours (TrayHost), or the hosted Plasma tray
    readonly property string quickSettingsStyle: get("quickSettingsStyle", "glass")   // "glass" = QuickSettings.qml (our design), "classic" = the ported Glass Control pages
    readonly property bool nativeControl: get("nativeControl", true)   // quick settings: qml/control, or the hosted onur.glasscontrol applet
    // launcher: our own (AppsModel) or, as a fallback, the hosted Kickoff fork
    readonly property bool nativeLauncher: get("nativeLauncher", true)
    readonly property var favorites: get("favorites", ["firefox.desktop", "org.kde.dolphin.desktop", "org.kde.konsole.desktop", "systemsettings.desktop", "org.kde.discover.desktop"])
    readonly property real dockMagnify: get("dockMagnify", 1.22)
    readonly property var launchers: get("launchers", [
        "preferred://browser", "preferred://filemanager", "applications:org.kde.konsole.desktop", "applications:systemsettings.desktop" ])
}
