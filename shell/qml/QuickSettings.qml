// Quick settings, designed for Sirca Shell (not a port): a header with the user and the session buttons, a grid of glass
// tiles (network, Bluetooth, do not disturb, night light, power profile, caffeine, microphone, displays, settings), a
// "follow the sun" row, and brightness / volume as thin glass sliders. Two detail pages slide in: Sound (devices) and Network (connections). Same visual language as the launcher,
// the settings window and the media popup: faint white fills, hairline rims, pills, Inter, no accent colour.
// Backends are plain QML modules (NetworkManager, BlueZ, PulseAudio/PipeWire, brightness, night light, notification
// manager, session management); the small helper objects come from qml/control.
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kcmutils                                  // KCMLauncher
import org.kde.notificationmanager as NotificationManager
import SircaShell
import "Glass"
import "control" as Control

Item {
    id: qs
    property bool expanded: false
    signal closeRequested()
    onExpandedChanged: if (!expanded) { page = "main"; shownPage = "main"; paletteOpen = false }
    // our own sliders drive the bar's volume display DIRECTLY while they move (the normal route, PulseAudio -> plasmashell ->
    // D-Bus -> the bar, trails the pointer by a round trip per step)
    signal osdRequested(string icon, real fraction)
    property bool paletteOpen: false                   // the colour theme popover under the palette button
    readonly property var themeNames: { const hue = n => { const h = Qt.color((Config.themes[n] || {}).accent || "#888").hslHue; return h > 0.93 ? h - 1 : h }   // literal-ok: fallback swatch
        return Object.keys(Config.themes).filter(n => n !== "wallpaper").sort((a, b) => hue(a) - hue(b)) }       // rainbow order (the config's keys arrive alphabetically); "wallpaper" has its own chip
    // accent derived from the current wallpaper: glass-mode does the whole desktop (palette.py), the shell alone does just itself (same algorithm)
    function themeFromWallpaper() { paletteOpen = false
        if (Shell.hasProgram("glass-mode")) { Shell.runDetached("glass-mode", ["theme", "wallpaper"]); return }
        const cur = Config.wallpaper !== "" ? Config.wallpaper : Shell.plasmaWallpaper()
        Palette.themeForWallpaperAsync(cur, "", function(t) { const th = Object.assign({}, Config.themes)
            th["wallpaper"] = { accent: t.accent, dark: Config.get("wallpaperDark", cur), light: Config.get("wallpaperLight", cur) }
            Shell.saveConfigKeys({ themes: th, theme: "wallpaper", accent: t.accent }) }) }
    function pickTheme(n) { paletteOpen = false; if (n === Config.theme) return
        if (Shell.hasProgram("glass-mode")) Shell.runDetached("glass-mode", ["theme", n])
        else { const t = Config.themes[n]; Shell.saveConfigKeys({ theme: n, accent: t.accent, wallpaper: Config.dark ? t.dark : t.light }) } }
    property string page: "main"                       // "main" | "sound" | "network": decides the SIZE at once
    // what is VISIBLE follows a beat later: the old page fades out, the popup is already resizing (the bar animates the
    // lobe towards implicitHeight; no second animation here, two chained ones made the resize trail behind the content),
    // and the new page fades in while the glass edge is still moving, so content and panel arrive together.
    property string shownPage: "main"
    onPageChanged: { if (shownPage !== page) { shownPage = ""; pageIn.restart() } }
    Timer { id: pageIn; interval: 110; onTriggered: qs.shownPage = qs.page }
    implicitWidth: 388
    implicitHeight: (page === "sound" ? soundPage.implicitHeight : page === "network" ? netPage.implicitHeight : mainPage.implicitHeight) + 2 * pad
    readonly property int pad: 6
    readonly property int gap: 8

    // ---------- backends ----------
    // Everything that comes from a PRIVATE Plasma module (network, Bluetooth, brightness, night light, sound) is its own
    // small file loaded by URL: when one of those modules is missing or has changed after a Plasma update, that Loader
    // fails and only its tile / slider degrades ("Unavailable"), instead of this whole popup refusing to load.
    NotificationManager.Settings { id: notif }
    Control.UserInfo { id: user }
    Loader { id: nightL; source: "control/NightLight.qml"; onStatusChanged: if (status === Loader.Error) console.warn("quick settings: night light unavailable") }
    Loader { id: netL; source: "NetworkBackend.qml"; onStatusChanged: if (status === Loader.Error) console.warn("quick settings: network unavailable (org.kde.plasma.networkmanagement)") }
    Loader { id: btL; source: "BluetoothBackend.qml"; onStatusChanged: if (status === Loader.Error) console.warn("quick settings: Bluetooth unavailable (org.kde.bluezqt)") }
    Loader { id: brL; source: "BrightnessBackend.qml"; onStatusChanged: if (status === Loader.Error) console.warn("quick settings: brightness unavailable (org.kde.plasma.private.brightnesscontrolplugin)") }
    Loader { id: volL; source: "VolumeBackend.qml"; onStatusChanged: if (status === Loader.Error) console.warn("quick settings: sound unavailable (org.kde.plasma.private.volume)") }
    // the shell's own types (system-bus power, idle inhibit, the sun schedule): always there, they report "absent" themselves
    PowerProfiles { id: power }
    BatteryInfo { id: battery }
    property bool busy: false                          // bound by the bar (bar.busy): a full-screen window or a game has focus
    QSCaffeine { id: caffeine; busy: qs.busy }
    QSAutoMode { id: autoMode }                        // display only; Main's instance (driver: true) does the switching
    readonly property var night: nightL.item
    readonly property var net: netL.item
    readonly property var bt: btL.item
    readonly property var bright: brL.item
    readonly property var vol: volL.item
    readonly property bool canDim: bright ? bright.canDim : false
    readonly property bool hasSink: vol ? vol.hasSink : false
    readonly property int volumePct: vol ? vol.pct : 0
    function volIcon() { if (!hasSink || vol.muted || volumePct === 0) return "audio-volume-muted-symbolic"; return volumePct < 34 ? "audio-volume-low-symbolic" : volumePct < 67 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic" }
    readonly property bool hasSource: vol ? vol.hasSource : false
    readonly property bool micMuted: vol ? vol.micMuted : false
    readonly property int micUsers: vol ? vol.recording : 0
    readonly property string micStatus: !hasSource ? "" : micMuted ? "Muted" : micUsers > 0 ? "In use by " + ((vol.recorderNames || []).join(", ") || (micUsers + (micUsers === 1 ? " app" : " apps"))) : "On"
    // power profile: the name, and on battery the time left ("Balanced · 2 h 10 min left")
    function spell(sec) { if (sec <= 0) return ""; const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60); return h > 0 ? h + " h " + (m > 0 ? m + " min" : "") : m + " min" }
    readonly property string powerStatus: { if (!power.available) return "Unavailable"; let t = power.label(power.active)
        if (battery.present && !battery.charging && battery.timeToEmpty > 0) t += " · " + spell(battery.timeToEmpty) + " left"
        else if (battery.present && battery.charging && !battery.full && battery.timeToFull > 0) t += " · " + spell(battery.timeToFull) + " to full"
        if (power.degraded !== "") t += " · limited"; return t }

    readonly property bool wifiThere: net ? net.wifiThere : false
    readonly property bool wifiOn: net ? net.wifiOn : false
    readonly property string netName: net ? net.name : ""
    readonly property bool btOn: bt ? bt.on : false
    readonly property string btName: bt ? bt.name : ""
    // Do Not Disturb, timed. One tile, a tap moves on: off -> for an hour -> until tomorrow morning -> until switched off -> off.
    // The status line says which one it is ("Until 19:40"). `dndTick` makes the tile notice when a timed one runs out.
    property int dndTick: 0
    Timer { interval: 20000; running: true; repeat: true; onTriggered: qs.dndTick++ }
    readonly property var dndUntil: { qs.dndTick; const u = notif.notificationsInhibitedUntil; return (u instanceof Date && !isNaN(u.getTime()) && Date.now() < u.getTime()) ? u : null }
    readonly property bool dndOn: notif.notificationsInhibitedByApplication || dndUntil !== null
    readonly property string dndStatus: { if (!dndOn) return "Off"; if (!dndUntil) return "On"
        const left = dndUntil.getTime() - Date.now(); if (left > 300 * 86400000) return "On"
        const sameDay = dndUntil.toDateString() === new Date().toDateString()
        return "Until " + (sameDay ? "" : "tomorrow ") + Qt.formatTime(dndUntil, "hh:mm") }
    function toggleBt() { if (bt) bt.toggle() }
    function toggleDnd() {
        const now = new Date(), left = dndUntil ? dndUntil.getTime() - now.getTime() : 0
        let until
        if (!dndOn) { until = new Date(now.getTime() + 3600000) }                                                  // for an hour
        else if (dndUntil && left <= 3660000) { until = new Date(now); until.setHours(8, 0, 0, 0); if (until <= now) until.setDate(until.getDate() + 1)     // until the morning
            if (until.getTime() - now.getTime() <= 3660000) until.setDate(until.getDate() + 1) }                   // (it is almost 8 already: the next one)
        else if (dndUntil && left < 300 * 86400000) { until = new Date(now); until.setFullYear(until.getFullYear() + 1) }   // until switched off
        else { until = undefined; notif.revokeApplicationInhibitions() }
        notif.notificationsInhibitedUntil = until
        notif.save(); qs.dndTick++ }
    function openKcm(name) { KCMLauncher.openSystemSettings(name); qs.closeRequested() }

    // ---------- parts ----------
    component RoundBtn: Item { id: rb; property string icon; property string fallbackIcon: ""; property bool lit: false; property color haze: "transparent"; property int size: 34; signal tapped()
        width: size; height: size
        Rectangle { anchors.fill: parent; radius: width / 2; color: Config.fg(rt.pressed ? 0.20 : (rb.lit ? 0.16 : (rbh.hovered ? 0.12 : 0.055))); border.width: 1; border.color: Config.fg(rbh.hovered || rb.lit ? 0.18 : 0.09)
            Behavior on color { ColorAnimation { duration: Config.quick } } }
        // a colour HAZE in the button's glass (the palette button wears the current theme): not a fill but a blurred blob of
        // the colour behind the icon, fading out before the rim, like the haze under the dock's icons
        Item { id: hazeBox; visible: rb.haze.a > 0; anchors.fill: parent
            layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: hazeClip; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            Item { id: hazeSrc; anchors.fill: parent; visible: false
                Rectangle { anchors.centerIn: parent; width: parent.width * 0.62; height: width; radius: width / 2; color: rb.haze } }   // centred on the glyph (it used to sit low, "glowing up from below": it read as off-centre)
            MultiEffect { anchors.fill: parent; source: hazeSrc; autoPaddingEnabled: true; blurEnabled: true; blur: 1.0; blurMax: 22; saturation: 0.35
                opacity: rb.lit ? 0.95 : (rbh.hovered ? 0.8 : 0.62); Behavior on opacity { NumberAnimation { duration: Config.quick } } } }
        Item { id: hazeClip; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: width / 2 } }
        Kirigami.Icon { anchors.centerIn: parent; width: Math.round(rb.size * 0.47); height: width; source: rb.icon; fallback: rb.fallbackIcon; isMask: true; color: Config.fgSolid; opacity: 0.9; roundToIconSize: false }
        HoverHandler { id: rbh } TapHandler { id: rt; onTapped: rb.tapped() } }

    component Tile: Item { id: tile
        property string icon; property string title; property string status: ""; property bool on: false; property bool more: false
        signal toggled(); signal opened()
        height: 58
        Rectangle { anchors.fill: parent; radius: 18
            color: Config.fg(tile.on ? 0.15 : (th.hovered ? 0.085 : 0.055)); border.width: 1; border.color: Config.fg(tile.on ? 0.22 : 0.09)
            Behavior on color { ColorAnimation { duration: Config.quick } } }
        Rectangle { id: bubble; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 34; height: 34; radius: 17
            color: tile.on ? Config.onFill : Config.fg(0.10); scale: tt.pressed ? 0.92 : 1
            Behavior on color { ColorAnimation { duration: Config.normal } } Behavior on scale { NumberAnimation { duration: Config.quick } }
            Kirigami.Icon { anchors.centerIn: parent; width: 17; height: 17; source: tile.icon; isMask: true; roundToIconSize: false
                color: tile.on ? Config.onFg : Config.fgSolid } }
        Column { anchors.left: bubble.right; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: tile.more ? 30 : 10; anchors.verticalCenter: parent.verticalCenter; spacing: 1
            Text { width: parent.width; text: tile.title; color: Config.ink; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
            Text { width: parent.width; text: tile.status; visible: text !== ""; color: Config.inkDim; font.pixelSize: 12; elide: Text.ElideRight } }
        HoverHandler { id: th } TapHandler { id: tt; onTapped: tile.toggled() }
        // the chevron is its own target: tile = toggle, chevron = details
        Item { visible: tile.more; anchors.right: parent.right; width: 32; height: parent.height
            Rectangle { anchors.centerIn: parent; width: 24; height: 24; radius: 12; color: Config.fg(mh.hovered ? 0.14 : 0) }
            Kirigami.Icon { anchors.centerIn: parent; width: 13; height: 13; source: "go-next-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.75; roundToIconSize: false }
            HoverHandler { id: mh } TapHandler { onTapped: tile.opened() } } }

    component SliderRow: Item { id: sr
        property string icon; property real value: 0; property bool more: false; property bool enabled_: true
        signal moved(real v); signal iconTapped(); signal opened()
        height: 46; opacity: enabled_ ? 1 : 0.4
        RoundBtn { id: ib; x: 8; anchors.verticalCenter: parent.verticalCenter; size: 30; icon: sr.icon; onTapped: sr.iconTapped() }
        GlassSlider { anchors.left: ib.right; anchors.leftMargin: 10; anchors.right: val.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            from: 0; to: 100; step: 1; value: sr.value; enabled: sr.enabled_
            onMoved: v => sr.moved(v); onCommitted: v => sr.moved(v) }
        Text { id: val; anchors.right: nextBtn.left; anchors.rightMargin: sr.more ? 4 : 0; anchors.verticalCenter: parent.verticalCenter; width: 38; horizontalAlignment: Text.AlignRight
            text: Math.round(sr.value) + "%"; color: Config.inkDim; font.pixelSize: 12; font.features: { "tnum": 1 } }
        RoundBtn { id: nextBtn; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; size: sr.more ? 26 : 0; width: sr.more ? 26 : 0; visible: sr.more
            icon: "go-next-symbolic"; onTapped: sr.opened() } }

    component PageHead: Item { id: ph; property string title; property string kcm: ""
        height: 40
        RoundBtn { id: back; size: 32; anchors.verticalCenter: parent.verticalCenter; icon: "go-previous-symbolic"; onTapped: qs.page = "main" }
        Text { anchors.left: back.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: ph.title; color: Config.ink; font.pixelSize: 16; font.weight: Font.DemiBold }
        RoundBtn { visible: ph.kcm !== ""; size: 32; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; icon: "configure"; onTapped: qs.openKcm(ph.kcm) } }

    component ListRow: Item { id: lr; property string icon; property string title; property string note: ""; property bool current: false; signal tapped()
        height: 42
        Rectangle { anchors.fill: parent; anchors.topMargin: 1; anchors.bottomMargin: 1; radius: 12
            color: Config.fg(lr.current ? 0.13 : (lh.hovered ? 0.07 : 0)); border.width: 1; border.color: Config.fg(lr.current ? 0.16 : 0)
            Behavior on color { ColorAnimation { duration: Config.quick } } }
        Kirigami.Icon { id: li; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; source: lr.icon; isMask: true; color: Config.fgSolid; opacity: lr.current ? 1 : 0.7; roundToIconSize: false }
        Text { anchors.left: li.right; anchors.leftMargin: 10; anchors.right: noteText.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            text: lr.title; color: Config.ink; font.pixelSize: 13; font.weight: lr.current ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
        Text { id: noteText; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: lr.note; color: Config.inkDim; font.pixelSize: 12 }
        HoverHandler { id: lh } TapHandler { onTapped: lr.tapped() } }

    component Label_: Text { color: Config.inkDim; font.pixelSize: 11; font.weight: Font.Medium; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6; leftPadding: 6 }

    // ---------- main page ----------
    // ---- colour theme popover: hangs under the palette button, over the tiles; a pick or a click anywhere else closes it
    MouseArea { id: palCatch; anchors.fill: parent; z: 40; enabled: qs.paletteOpen; visible: enabled; acceptedButtons: Qt.AllButtons
        // anywhere but the palette button closes; a press ON the button is passed through, so the button itself toggles shut
        onPressed: m => { const p = palBtn.mapFromItem(palCatch, m.x, m.y); if (p.x >= 0 && p.y >= 0 && p.x <= palBtn.width && p.y <= palBtn.height) { m.accepted = false; return } qs.paletteOpen = false } }
    Rectangle { id: themePop; z: 41
        readonly property point anchor: { qs.width; qs.shownPage; return palBtn.mapToItem(qs, palBtn.width / 2, palBtn.height) }
        width: popRow.implicitWidth + 32; height: 50; radius: 18
        x: Math.max(qs.pad, Math.min(qs.width - qs.pad - width, anchor.x - width / 2)); y: anchor.y + 8
        readonly property color a: Config.accent
        color: Config.dark ? Qt.rgba(0.125 + a.r * 0.06, 0.125 + a.g * 0.06, 0.13 + a.b * 0.06, 0.96) : Qt.rgba(0.97 + a.r * 0.03, 0.97 + a.g * 0.03, 0.97 + a.b * 0.03, 0.97); border.width: 1; border.color: Config.fg(0.20)
        Behavior on color { ColorAnimation { duration: 260 } }
        opacity: qs.paletteOpen ? 1 : 0; visible: opacity > 0.01; scale: qs.paletteOpen ? 1 : 0.92; transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 3; anchors.bottomMargin: -7; radius: parent.radius + 2; color: Qt.rgba(0, 0, 0, Config.dark ? 0.35 : 0.12) }   // a soft drop shadow
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Row { id: popRow; anchors.centerIn: parent; spacing: 10
            Repeater { model: qs.themeNames
                Item { id: sw; required property string modelData; readonly property bool current: Config.theme === modelData
                    width: 30; height: 30
                    Rectangle { anchors.fill: parent; radius: 15; color: "transparent"; border.width: 2; border.color: sw.current ? Config.fgSolid : "transparent"; Behavior on border.color { ColorAnimation { duration: Config.quick } } }
                    Rectangle { id: dot; anchors.centerIn: parent; width: 20; height: 20; radius: 10
                        readonly property color c: (Config.themes[sw.modelData] || {}).accent || "#888"   // literal-ok: fallback swatch
                        gradient: Gradient { GradientStop { position: 0; color: Qt.lighter(dot.c, 1.25) } GradientStop { position: 1; color: dot.c } }
                        scale: swh.hovered && !sw.current ? 1.15 : 1; Behavior on scale { NumberAnimation { duration: Config.quick } } }
                    HoverHandler { id: swh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: qs.pickTheme(sw.modelData) } } }
            // "from the wallpaper": a round thumbnail of the current picture; current when the derived theme is active
            Item { id: wsw; readonly property bool current: Config.theme === "wallpaper"; width: 30; height: 30
                Rectangle { anchors.fill: parent; radius: 15; color: "transparent"; border.width: 2; border.color: wsw.current ? Config.fgSolid : Config.fg(0.25); Behavior on border.color { ColorAnimation { duration: Config.quick } } }
                Item { anchors.centerIn: parent; width: 20; height: 20; scale: wswh.hovered && !wsw.current ? 1.15 : 1; Behavior on scale { NumberAnimation { duration: Config.quick } }
                    Image { anchors.fill: parent; source: Config.wallpaper !== "" ? "file://" + Config.wallpaper : ""; sourceSize: Qt.size(40, 40); fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true; visible: false; id: wimg }
                    Rectangle { id: wmask; anchors.fill: parent; radius: 10; visible: false }
                    MultiEffect { anchors.fill: parent; source: wimg; maskEnabled: true; maskSource: wmask } }
                HoverHandler { id: wswh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: qs.themeFromWallpaper() } } } }

    Column { id: mainPage; x: qs.pad; y: qs.pad; width: qs.width - 2 * qs.pad; spacing: qs.gap + 2
        opacity: qs.shownPage === "main" ? 1 : 0; visible: opacity > 0.01
        transform: Translate { x: qs.shownPage === "main" ? 0 : -22; Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Item { width: parent.width; height: 40
            Item { id: avatar; width: 36; height: 36; anchors.verticalCenter: parent.verticalCenter
                Rectangle { anchors.fill: parent; radius: 18; color: Config.fg(0.08); border.width: 1; border.color: Config.fg(0.18) }
                Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "user-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.8; visible: face.status !== Image.Ready; roundToIconSize: false }
                Rectangle { id: faceMask; anchors.fill: parent; anchors.margins: 2; radius: width / 2; visible: false; layer.enabled: true; layer.smooth: true }
                Image { id: face; anchors.fill: faceMask; source: user.urlAvatar; sourceSize: Qt.size(96, 96); fillMode: Image.PreserveAspectCrop; visible: false; layer.enabled: true; mipmap: true }
                MultiEffect { anchors.fill: faceMask; source: face; maskEnabled: true; maskSource: faceMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; visible: face.status === Image.Ready } }
            Text { anchors.left: avatar.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: String(user.name).replace(/^\S+\s+/, ""); color: Config.ink; font.pixelSize: 15; font.weight: Font.Medium }
            Row { id: headBtns; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                // colour themes: a palette button wearing the current colour as a haze; a click drops a small popover with
                // the swatches (see themePop below)
                RoundBtn { id: palBtn; visible: qs.themeNames.length > 1; icon: "qrc:/qt/qml/SircaShell/qml/icons/palette-symbolic.svg"; lit: qs.paletteOpen      // our own glyph: no installed theme has a real palette
                    haze: Config.accent; onTapped: qs.paletteOpen = !qs.paletteOpen }
                // light / dark for the whole desktop: the shell flips itself at once, glass-mode (glass-desktop) brings the colour
                // scheme, GTK, icons and wallpaper along. The icon shows what a click switches TO.
                RoundBtn { icon: Config.dark ? "weather-clear-symbolic" : "weather-clear-night-symbolic"
                    onTapped: { const want = Config.dark ? "light" : "dark"; Shell.saveConfigKey("mode", want); if (Shell.hasProgram("glass-mode")) Shell.runDetached("glass-mode", [want]) } }
                RoundBtn { icon: "configure"; onTapped: { Shell.dbusSend("onur.SircaShell", "/SircaShell", "onur.SircaShell", "openSettings"); qs.closeRequested() } }
                RoundBtn { icon: "system-lock-screen-symbolic"; onTapped: { Shell.dbusSend("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver", "Lock"); qs.closeRequested() } }   // (not org.kde.plasma.private.sessions: one private module less)
                RoundBtn { icon: "system-shutdown-symbolic"; onTapped: { qs.closeRequested(); Shell.dbusSend("onur.SircaShell", "/SircaShell", "onur.SircaShell", "togglePowerMenu") } } } }

        Grid { enabled: !qs.paletteOpen   /* pointer handlers keep a passive grab: the catcher above cannot stop them, so a swatch click also hit the tile under it */; width: parent.width; columns: 2; spacing: qs.gap
            readonly property real tw: (width - spacing) / 2
            Tile { width: parent.tw; icon: qs.net ? qs.net.icon : "network-wired-symbolic"; title: "Network"; on: qs.netName !== ""; more: !!qs.net
                status: !qs.net ? "Unavailable" : qs.netName !== "" ? qs.netName + (qs.net.activeVpn !== "" && qs.netName.indexOf(qs.net.activeVpn) < 0 ? " · " + qs.net.activeVpn : "") : "Not connected"
                onToggled: { if (!qs.net) return; if (qs.wifiThere) qs.net.enableWireless(!qs.wifiOn); else qs.page = "network" } onOpened: if (qs.net) qs.page = "network" }
            Tile { width: parent.tw; icon: qs.btOn ? "network-bluetooth-activated-symbolic" : "network-bluetooth-inactive-symbolic"; title: "Bluetooth"
                status: !qs.bt ? "Unavailable" : !qs.btOn ? "Off" : (qs.btName !== "" ? qs.btName : "On"); on: qs.btOn; more: true; onToggled: qs.toggleBt(); onOpened: qs.openKcm("kcm_bluetooth") }
            Tile { width: parent.tw; icon: qs.dndOn ? "notifications-disabled-symbolic" : "notifications-symbolic"; title: "Do Not Disturb"; status: qs.dndStatus; on: qs.dndOn; onToggled: qs.toggleDnd() }
            Tile { width: parent.tw; icon: "redshift-status-on"; title: "Night Light"; status: qs.night ? qs.night.statusText : "Unavailable"; on: qs.night ? qs.night.on : false; more: true; onToggled: if (qs.night) qs.night.toggle(); onOpened: qs.openKcm("kcm_nightlight") }
            // a tap steps power-saver -> balanced -> performance; lit unless it sits on the middle one. Absent daemon: no tile.
            Tile { width: parent.tw; visible: power.available; icon: power.icon(power.active); title: "Power profile"; status: qs.powerStatus; on: power.available && power.active !== "balanced"; more: true
                onToggled: power.cycle(); onOpened: qs.openKcm("kcm_powerdevilprofilesconfig") }
            Tile { width: parent.tw; icon: caffeine.active ? "system-suspend-inhibited" : "system-suspend-uninhibited"; title: "Caffeine"; status: caffeine.status; on: caffeine.active; onToggled: caffeine.toggle() }
            // the default source's mute; lit while the microphone is live. No source (no microphone at all): no tile.
            Tile { width: parent.tw; visible: qs.hasSource; icon: qs.micMuted ? "mic-off-symbolic" : "mic-on-symbolic"; title: "Microphone"; status: qs.micStatus; on: qs.hasSource && !qs.micMuted; more: true
                onToggled: if (qs.vol) qs.vol.toggleMicMute(); onOpened: qs.page = "sound" }
            Tile { width: parent.tw; icon: "video-display-symbolic"; title: "Displays"; status: qs.bright ? qs.bright.label : ""; onToggled: qs.openKcm("kcm_kscreen") }
            Tile { width: parent.tw; icon: "preferences-system-symbolic"; title: "System Settings"; onToggled: qs.openKcm("") } }

        // follow the sun: light by day, dark by night (QSAutoMode; the schedule from Night Light, else a configured location)
        Rectangle { enabled: !qs.paletteOpen; width: parent.width; height: 44; radius: 18; color: Config.fg(0.055); border.width: 1; border.color: Config.fg(0.09)
            Kirigami.Icon { id: sunIcon; x: 14; anchors.verticalCenter: parent.verticalCenter; width: 17; height: 17; source: autoMode.on && autoMode.wantDark ? "weather-clear-night-symbolic" : "weather-clear-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.9; roundToIconSize: false }
            Column { anchors.left: sunIcon.right; anchors.leftMargin: 12; anchors.right: sunSwitch.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                Text { width: parent.width; text: "Follow the sun"; color: Config.ink; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
                Text { width: parent.width; visible: text !== ""; text: autoMode.canSchedule ? autoMode.nextText : (autoMode.on ? "No schedule: " : "") + autoMode.nextText; color: Config.inkDim; font.pixelSize: 12; elide: Text.ElideRight } }
            GlassSwitch { id: sunSwitch; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; checked: autoMode.on; opacity: autoMode.canSchedule || autoMode.on ? 1 : 0.45
                onToggled: on => autoMode.setOn(on) } }
        // sliders share one glass tile, a hairline between them
        Rectangle { enabled: !qs.paletteOpen; width: parent.width; height: sliders.implicitHeight + 8; radius: 18; color: Config.fg(0.055); border.width: 1; border.color: Config.fg(0.09)
            Column { id: sliders; y: 4; width: parent.width
                SliderRow { width: parent.width; visible: qs.canDim; icon: "brightness-high-symbolic"
                    value: qs.bright ? qs.bright.pct : 0
                    onMoved: v => { if (qs.bright) qs.bright.setPct(v) } }
                Rectangle { visible: qs.canDim; x: 14; width: parent.width - 28; height: 1; color: Config.fg(0.07) }
                SliderRow { width: parent.width; icon: qs.volIcon(); value: qs.volumePct; more: true; enabled_: qs.hasSink
                    onMoved: v => { if (qs.hasSink) { qs.vol.setPct(v, true); qs.osdRequested(qs.volIcon(), Math.round(v) / 100) } }
                    onIconTapped: if (qs.vol) qs.vol.toggleMute()
                    onOpened: qs.page = "sound" } } }
    }

    // ---------- sound page ----------
    Column { id: soundPage; x: qs.pad; y: qs.pad; width: qs.width - 2 * qs.pad; spacing: qs.gap
        opacity: qs.shownPage === "sound" ? 1 : 0; visible: opacity > 0.01
        transform: Translate { x: qs.shownPage === "sound" ? 0 : 22; Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        PageHead { width: parent.width; title: "Sound"; kcm: "kcm_pulseaudio" }
        Rectangle { width: parent.width; height: 54; radius: 18; color: Config.fg(0.055); border.width: 1; border.color: Config.fg(0.09)
            SliderRow { width: parent.width; anchors.verticalCenter: parent.verticalCenter; icon: qs.volIcon(); value: qs.volumePct; enabled_: qs.hasSink
                onMoved: v => { if (qs.hasSink) { qs.vol.setPct(v, false); qs.osdRequested(qs.volIcon(), Math.round(v) / 100) } }
                onIconTapped: if (qs.vol) qs.vol.toggleMute() } }
        Label_ { text: "Output" }
        Column { width: parent.width
            Repeater { model: qs.vol ? qs.vol.sinks : null
                ListRow { required property var model; width: parent.width; icon: "audio-speakers-symbolic"
                    title: model.PulseObject ? (model.PulseObject.description || model.Description || "") : (model.Description || "")
                    current: model.PulseObject ? (model.PulseObject.default ?? false) : false
                    note: current ? "✓" : ""; onTapped: if (model.PulseObject) model.PulseObject.default = true } } }
        Label_ { text: "Input" }
        Column { width: parent.width
            Repeater { model: qs.vol ? qs.vol.sources : null
                ListRow { required property var model; width: parent.width; icon: "audio-input-microphone-symbolic"
                    title: model.PulseObject ? (model.PulseObject.description || model.Description || "") : (model.Description || "")
                    current: model.PulseObject ? (model.PulseObject.default ?? false) : false
                    note: current ? "✓" : ""; onTapped: if (model.PulseObject) model.PulseObject.default = true } } }
    }

    // ---------- network page ----------
    Column { id: netPage; x: qs.pad; y: qs.pad; width: qs.width - 2 * qs.pad; spacing: qs.gap
        opacity: qs.shownPage === "network" ? 1 : 0; visible: opacity > 0.01
        transform: Translate { x: qs.shownPage === "network" ? 0 : 22; Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        PageHead { width: parent.width; title: "Network"; kcm: "kcm_networkmanagement" }
        Item { width: parent.width; height: 44; visible: qs.wifiThere
            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: "Wi-Fi"; color: Config.ink; font.pixelSize: 14 }
            GlassSwitch { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; checked: qs.wifiOn; onToggled: on => { if (qs.net) qs.net.enableWireless(on) } } }
        ListView { width: parent.width; height: Math.min(contentHeight, 6 * 42); clip: true; interactive: contentHeight > height; boundsBehavior: Flickable.StopAtBounds
            model: qs.net ? qs.net.networks : null
            delegate: ListRow { required property var model; width: ListView.view.width
                readonly property bool active: model.ConnectionState === qs.net.stateActivated
                icon: model.ConnectionIcon || "network-wired-symbolic"; title: model.ItemUniqueName || model.Name || ""; current: active
                note: active ? "Connected" : (model.ConnectionState === qs.net.stateActivating ? "Connecting…" : (model.SecurityType > 0 && !model.ConnectionPath ? "Secured" : ""))
                onTapped: { if (active) qs.net.deactivate(model.ConnectionPath, model.DevicePath);
                            else if (model.ConnectionPath) qs.net.activate(model.ConnectionPath, model.DevicePath, model.SpecificPath);
                            else qs.openKcm("kcm_networkmanagement") } } }     // a new secured network needs a password: System Settings asks for it
        // VPNs: NetworkManager's VPN plugin connections and WireGuard tunnels, a tap connects / disconnects
        Label_ { text: "VPN"; visible: qs.net && qs.net.vpnCount > 0 }
        ListView { visible: qs.net && qs.net.vpnCount > 0; width: parent.width; height: Math.min(contentHeight, 4 * 42); clip: true; interactive: contentHeight > height; boundsBehavior: Flickable.StopAtBounds
            model: qs.net ? qs.net.vpns : null
            delegate: ListRow { required property var model; width: ListView.view.width
                readonly property bool active: model.ConnectionState === qs.net.stateActivated
                icon: "network-vpn-symbolic"; title: model.ItemUniqueName || model.Name || ""; current: active
                note: active ? "Connected" : (model.ConnectionState === qs.net.stateActivating ? "Connecting…" : (model.VpnType ? String(model.VpnType) : "WireGuard"))
                onTapped: { if (active) qs.net.deactivate(model.ConnectionPath, model.DevicePath); else qs.net.activate(model.ConnectionPath, model.DevicePath, model.SpecificPath) } } }
    }
}
