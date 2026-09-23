// Sirca Settings: the shell's own settings window. Every control writes one key of ~/.config/sirca-shell/config.json;
// the shell watches that file, so changes show at once (no Apply button, no restart). "Reset" removes the key, which
// brings the built-in default back. A normal window (KWin decorates it like any app): frosted sidebar, solid content.
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import SircaShell
import "Glass"

Window {
    id: win
    title: "Sirca Settings"
    width: 880; height: 600; minimumWidth: 760; minimumHeight: 480
    color: "transparent"
    visible: false
    function openIt(atPage) { if (atPage !== undefined && atPage >= 0) page = atPage; visible = true; raise(); requestActivate(); blurLater.restart() }
    // the whole window is frosted: the sidebar clearly, the content pane slightly (same targets as app pages: 72 % dark, 64 % light)
    Timer { id: blurLater; interval: 80; onTriggered: { Shell.setBlurRegion(win, [{ x: 0, y: 0, w: win.width, h: win.height, r: 0 }]); win.requestUpdate() } }   // blur is double-buffered Wayland state: it only applies with the next commit of the surface
    onHeightChanged: if (visible) blurLater.restart()
    onWidthChanged: if (visible) blurLater.restart()

    property int page: 0
    readonly property var pages: [ { name: "Appearance", icon: "preferences-desktop-theme-global" }, { name: "Top bar", icon: "view-list-icons" },
                                   { name: "Dock", icon: "preferences-desktop-icons" }, { name: "Behaviour", icon: "preferences-system-windows-behavior" },
                                   { name: "Desktop", icon: "preferences-desktop-wallpaper" }, { name: "About", icon: "help-about" } ]
    // writes are throttled while dragging: every write re-evaluates all tokens in the shell
    property string pendingKey: ""
    property var pendingValue
    Timer { id: writeLater; interval: 50; onTriggered: if (win.pendingKey !== "") { Shell.saveConfigKey(win.pendingKey, win.pendingValue); win.pendingKey = "" } }
    function setKey(key, value, now) { if (now) { writeLater.stop(); pendingKey = ""; Shell.saveConfigKey(key, value) } else { pendingKey = key; pendingValue = value; if (!writeLater.running) writeLater.start() } }

    // ---- building blocks ----
    component Section: Column { property string title; default property alias rows: body.data; width: parent ? parent.width : 0; spacing: 8
        Text { text: parent.title; color: Config.inkDim; font.pixelSize: 11; font.weight: Font.Medium; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6; leftPadding: 4 }
        Rectangle { width: parent.width; height: body.implicitHeight + 8; radius: 14; color: Config.fg(0.045); border.width: 1; border.color: Config.fg(0.08)
            Column { id: body; x: 0; y: 4; width: parent.width } } }
    component Row_: Item { id: r; property string label; property string hint: ""; property string key: ""; default property alias control: slot.data
        width: parent ? parent.width : 0; height: hint !== "" ? 58 : 48
        readonly property bool custom: key !== "" && Config.user && Config.user[key] !== undefined
        Column { x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 2; width: parent.width * 0.42
            Text { text: r.label; color: Config.ink; font.pixelSize: 14 }
            Text { text: r.hint; visible: text !== ""; color: Config.inkDim; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight } }
        Row { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 10
            Item { id: slot; width: childrenRect.width; height: childrenRect.height; anchors.verticalCenter: parent.verticalCenter }
            // per-key reset, only while the key differs from the default
            Item { width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter; opacity: r.custom ? 1 : 0; visible: r.key !== ""
                Behavior on opacity { NumberAnimation { duration: Config.quick } }
                Rectangle { anchors.fill: parent; radius: 11; color: Config.fg(rh.hovered ? 0.14 : 0.06) }
                Kirigami.Icon { anchors.centerIn: parent; width: 13; height: 13; source: "edit-undo-symbolic"; isMask: true; color: Config.fgSolid; roundToIconSize: false }
                HoverHandler { id: rh }
                TapHandler { enabled: r.custom; onTapped: Shell.removeConfigKey(r.key) } } } }
    component Num: Row { id: n; property string key; property real from; property real to; property real step: 1; property real value; property string unit: ""; property int decimals: 0
        spacing: 10
        GlassSlider { width: 210; anchors.verticalCenter: parent.verticalCenter; from: n.from; to: n.to; step: n.step; value: n.value
            onMoved: v => win.setKey(n.key, n.decimals > 0 ? Number(v.toFixed(n.decimals)) : Math.round(v), false)
            onCommitted: v => win.setKey(n.key, n.decimals > 0 ? Number(v.toFixed(n.decimals)) : Math.round(v), true) }
        Text { width: 52; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Config.inkDim; font.pixelSize: 12; font.features: { "tnum": 1 }
            text: (n.decimals > 0 ? n.value.toFixed(n.decimals) : Math.round(n.value)) + n.unit } }
    component Chip: Rectangle { id: c; property string text; property bool on: false; property color dot: "transparent"; signal tapped()
        height: 30; width: crow.implicitWidth + 22; radius: 15
        color: Config.fg(on ? 0.18 : (ch.hovered ? 0.10 : 0.05)); border.width: 1; border.color: Config.fg(on ? 0.26 : 0.10)
        Row { id: crow; anchors.centerIn: parent; spacing: 7
            Rectangle { visible: c.dot.a > 0; width: 12; height: 12; radius: 6; color: c.dot; anchors.verticalCenter: parent.verticalCenter; border.width: 1; border.color: Config.fg(0.25) }
            Text { text: c.text; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter } }
        HoverHandler { id: ch }
        TapHandler { onTapped: c.tapped() } }

    // ---- sidebar (frosted: blur-behind is set for exactly this strip) ----
    Rectangle { id: side; width: 210; height: parent.height; color: Config.sidebarTint
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Config.fg(0.07) }
        Column { x: 10; y: 14; width: parent.width - 20; spacing: 2
            Repeater { model: win.pages
                Item { required property int index; required property var modelData; width: parent.width; height: 38
                    readonly property bool sel: win.page === index
                    Rectangle { anchors.fill: parent; radius: 10; color: Config.fg(parent.sel ? 0.14 : (sh.hovered ? 0.07 : 0)); border.width: 1; border.color: Config.fg(parent.sel ? 0.16 : 0)
                        Behavior on color { ColorAnimation { duration: Config.quick } } }
                    Kirigami.Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; source: parent.modelData.icon; roundToIconSize: false }
                    Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; color: Config.ink; font.pixelSize: 14; font.weight: parent.sel ? Font.DemiBold : Font.Normal }
                    HoverHandler { id: sh }
                    TapHandler { onTapped: win.page = parent.index } } } } }

    // ---- content ----
    Rectangle { x: side.width; width: parent.width - side.width; height: parent.height; color: Config.mix(Qt.rgba(0.086, 0.090, 0.094, 0.72), Qt.rgba(0.953, 0.957, 0.965, 0.64))   // literal-ok: both modes given to Config.mix
        Flickable { anchors.fill: parent; anchors.margins: 22; contentHeight: stack.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column { id: stack; width: parent.width; spacing: 18
                Text { text: win.pages[win.page].name; color: Config.ink; font.pixelSize: 24; font.weight: Font.DemiBold }

                // Appearance
                Column { visible: win.page === 0; width: parent.width; spacing: 18
                    Section { title: "Glass"
                        Row_ { label: "Tint"; hint: "How much the glass is tinted"; key: "tintAlpha"; Num { key: "tintAlpha"; from: 0; to: 0.6; step: 0.01; decimals: 2; value: Config.get("tintAlpha", 0.15) } }        // the STORED value: Config.tint is already adjusted for the mode
                        Row_ { label: "Rim"; hint: "Brightness of the glass edge"; key: "rimAlpha"; Num { key: "rimAlpha"; from: 0; to: 0.3; step: 0.01; decimals: 2; value: Config.get("rimAlpha", 0.09) } }
                        Row_ { label: "Sheen"; hint: "Light from above"; key: "sheenAlpha"; Num { key: "sheenAlpha"; from: 0; to: 0.2; step: 0.01; decimals: 2; value: Config.get("sheenAlpha", 0.06) } }
                        Row_ { label: "Corner radius"; key: "cornerRadius"; Num { key: "cornerRadius"; from: 8; to: 30; value: Config.cornerRadius; unit: " px" } } }
                    Section { title: "Colour haze"
                        Row_ { label: "Dock"; hint: "Icon colours caught in the dock's glass"; key: "hazeStrength"; Num { key: "hazeStrength"; from: 0; to: 0.7; step: 0.01; decimals: 2; value: Config.hazeStrength } }
                        Row_ { label: "Top bar"; key: "barHazeStrength"; Num { key: "barHazeStrength"; from: 0; to: 0.7; step: 0.01; decimals: 2; value: Config.barHazeStrength } } } }

                // Top bar
                Column { visible: win.page === 1; width: parent.width; spacing: 18
                    Section { title: "Size"
                        Row_ { label: "Width"; hint: "Centred on the screen"; key: "barWidth"; Num { key: "barWidth"; from: 1200; to: Math.max(1400, Screen.width - 40); step: 2; value: Config.barWidth; unit: " px" } }
                        Row_ { label: "Height"; key: "barHeight"; Num { key: "barHeight"; from: 30; to: 50; value: Config.barHeight; unit: " px" } }
                        Row_ { label: "Gap to the screen edge"; key: "barGap"; Num { key: "barGap"; from: 0; to: 24; value: Config.barGap; unit: " px" } } }
                    Section { title: "Tray"
                        Row_ { label: "Native tray"; hint: "App icons and their menus drawn by the shell. Off = the hosted Plasma tray"; key: "nativeTray"
                            GlassSwitch { checked: Config.nativeTray; onToggled: on => win.setKey("nativeTray", on, true) } } }
                    Section { title: "Calendar"
                        Row_ { label: "Native calendar"; hint: "The popup behind the clock. Off = the hosted Plasma clock applet"; key: "nativeCalendar"
                            GlassSwitch { checked: Config.nativeCalendar; onToggled: on => win.setKey("nativeCalendar", on, true) } } }
                    Section { title: "Updates"
                        Row_ { label: "Check for updates"; hint: "Once a day the shell asks GitHub whether a newer version than " + Shell.version + " was released. Nothing else is sent. A notification then offers to update"; key: "updateCheck"
                            GlassSwitch { checked: Config.get("updateCheck", false) === true; onToggled: on => win.setKey("updateCheck", on, true) } }
                        Row_ { label: "Check now"; hint: "Asks right away and tells you either way"
                            Rectangle { width: cnt.implicitWidth + 24; height: 28; radius: 14; color: Config.fg(cnh.hovered ? 0.16 : 0.09)
                                Text { id: cnt; anchors.centerIn: parent; text: "Check now"; color: Config.ink; font.pixelSize: 12 }
                                HoverHandler { id: cnh; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: Shell.checkForUpdate(true) } } } }
                    Section { title: "Weather"
                        Row_ { label: "Weather"; hint: "Open-Meteo, every 30 min, no account. Placing the bar widget switches it on too"; key: "weather"
                            GlassSwitch { checked: Config.weatherOn; onToggled: on => win.setKey("weather", on, true) } }
                        Row_ { label: "Location"; hint: Weather.locationName !== "" ? Weather.locationName : "Type a town and pick a hit"; key: "weatherLocation"; height: 58 + (places.count > 0 ? placeCol.implicitHeight + 8 : 0)
                            Column { id: placeCol; spacing: 8
                                Rectangle { width: 260; height: 30; radius: 15; color: Config.fg(0.07); border.width: 1; border.color: Config.fg(placeField.activeFocus ? 0.3 : 0.12)
                                    TextInput { id: placeField; anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter; color: Config.ink; font.pixelSize: 13; clip: true; selectByMouse: true
                                        onTextEdited: placeTimer.restart(); onAccepted: Weather.searchPlace(text)
                                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Town or city"; color: Config.inkDim; font.pixelSize: 13; visible: placeField.text === "" && !placeField.activeFocus } } }
                                Timer { id: placeTimer; interval: 450; onTriggered: Weather.searchPlace(placeField.text) }
                                Connections { target: Weather; function onPlacesFound(list) { places.clear(); for (const p of list) places.append(p) } }
                                ListModel { id: places }
                                Repeater { model: places
                                    Rectangle { id: hit; required property var model; width: 260; height: 30; radius: 15; color: Config.fg(hh.hovered ? 0.14 : 0.05)
                                        Text { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; color: Config.ink; font.pixelSize: 12
                                            text: hit.model.name + (hit.model.region ? ", " + hit.model.region : "") + (hit.model.country ? " · " + hit.model.country : "") }
                                        HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: { Shell.saveConfigKeys({ weatherLocation: { lat: hit.model.lat, lon: hit.model.lon, name: hit.model.name }, weather: true }); places.clear(); placeField.text = "" } } } } } }
                        Row_ { label: "Units"; key: "weatherUnits"
                            Row { spacing: 8
                                Chip { text: "°C"; on: Config.get("weatherUnits", "c") !== "f"; onTapped: win.setKey("weatherUnits", "c", true) }
                                Chip { text: "°F"; on: Config.get("weatherUnits", "c") === "f"; onTapped: win.setKey("weatherUnits", "f", true) } } } }
                    Section { title: "Notifications"
                        Row_ { label: "Native notifications"; hint: "Cards and history drawn by the shell. Off = the hosted Plasma applet"; key: "nativeNotifications"
                            GlassSwitch { checked: Config.nativeNotifications; onToggled: on => win.setKey("nativeNotifications", on, true) } } }
                    Section { title: "Tile widgets"
                        Row_ { label: "Click"; hint: "Quick-settings tiles placed in the bar (edit mode › Add): a click toggles the tile, or opens its page. Middle click always opens; scroll on Volume changes it, middle click on Volume jumps to the next output"; key: "barTileClick"; height: 58 + Math.max(0, clickFlow.implicitHeight - 30)
                            Flow { id: clickFlow; width: 330; spacing: 6
                                readonly property var names: ({ volume: "Volume", network: "Network", bluetooth: "Bluetooth", dnd: "Do Not Disturb", nightlight: "Night Light", power: "Power profile", caffeine: "Caffeine", mic: "Microphone" })
                                readonly property var modes: Config.get("barTileClick", {}) || {}
                                function modeOf(id) { const m = modes[id]; if (m === "page" || m === "toggle") return m; return (id === "volume" || id === "network") ? "page" : "toggle" }
                                Repeater { model: ["volume", "network", "bluetooth", "dnd", "nightlight", "power", "caffeine", "mic"]
                                    Chip { required property string modelData; text: clickFlow.names[modelData] + ": " + (clickFlow.modeOf(modelData) === "page" ? "open" : "toggle"); on: clickFlow.modeOf(modelData) === "page"
                                        onTapped: { const m = Object.assign({}, clickFlow.modes); m[modelData] = clickFlow.modeOf(modelData) === "page" ? "toggle" : "page"; win.setKey("barTileClick", m, true) } } } } } }
                    Section { title: "Quick settings"
                        Row_ { label: "Tiles"; hint: "What the panel shows. Right-click a tile in the panel to drag them into another order"; key: "qsTiles"; height: 58 + Math.max(0, tileFlow.implicitHeight - 30)
                            Flow { id: tileFlow; width: 330; spacing: 6
                                readonly property var names: ({ network: "Network", bluetooth: "Bluetooth", dnd: "Do Not Disturb", nightlight: "Night Light", power: "Power profile", caffeine: "Caffeine", mic: "Microphone", displays: "Displays", settings: "System Settings", sun: "Follow the sun", sliders: "Sliders" })
                                readonly property var all: ["network", "bluetooth", "dnd", "nightlight", "power", "caffeine", "mic", "displays", "settings", "sun", "sliders"]
                                readonly property var shown: { const v = Config.get("qsTiles", null); return v && v.length !== undefined ? Array.prototype.slice.call(v) : all }
                                Repeater { model: tileFlow.all
                                    Chip { required property string modelData; text: tileFlow.names[modelData]; on: tileFlow.shown.indexOf(modelData) >= 0
                                        onTapped: { let l = tileFlow.shown.slice(); if (on) l = l.filter(x => x !== modelData); else l.push(modelData); win.setKey("qsTiles", l, true) } } } } }
                        Row_ { label: "Native quick settings"; hint: "Our own panel. Off = the hosted Plasma applet"; key: "nativeControl"
                            GlassSwitch { checked: Config.nativeControl; onToggled: on => win.setKey("nativeControl", on, true) } } }
                    Section { title: "Content"
                        Row_ { label: "Clock size"; key: "clockSize"; Num { key: "clockSize"; from: 12; to: 22; value: Config.clockSize; unit: " px" } }
                        Row_ { label: "Popup padding"; hint: "Air between a popup's content and the glass"; key: "lobePad"; Num { key: "lobePad"; from: 4; to: 20; value: Config.lobePad; unit: " px" } } } }

                // Dock
                Column { visible: win.page === 2; width: parent.width; spacing: 18
                    Section { title: "Size"
                        Row_ { label: "Icon size"; key: "dockIcon"; Num { key: "dockIcon"; from: 32; to: 64; value: Config.dockIcon; unit: " px" } }
                        Row_ { label: "Cell width"; hint: "Space per icon"; key: "dockCell"; Num { key: "dockCell"; from: 44; to: 84; value: Config.dockCell; unit: " px" } }
                        Row_ { label: "Height"; key: "dockHeight"; Num { key: "dockHeight"; from: 44; to: 84; value: Config.dockHeight; unit: " px" } }
                        Row_ { label: "Corner radius"; key: "dockRadius"; Num { key: "dockRadius"; from: 8; to: 30; value: Config.dockRadius; unit: " px" } }
                        Row_ { label: "Gap to the screen edge"; key: "dockGap"; Num { key: "dockGap"; from: 0; to: 24; value: Config.dockGap; unit: " px" } } }
                    Section { title: "Launcher"
                        Row_ { label: "Native launcher"; hint: "Our own app grid. Off = the hosted Plasma Kickoff"; key: "nativeLauncher"
                            GlassSwitch { checked: Config.nativeLauncher; onToggled: on => win.setKey("nativeLauncher", on, true) } } }
                    Section { title: "Hover"
                        Row_ { label: "Magnification"; hint: "1.00 = none"; key: "dockMagnify"; Num { key: "dockMagnify"; from: 1; to: 1.6; step: 0.01; decimals: 2; value: Config.dockMagnify; unit: "×" } } } }

                // Behaviour
                Column { visible: win.page === 3; width: parent.width; spacing: 18
                    Section { title: "Windows"
                        Row_ { label: "Bar and windows"; hint: "Never touch it reserves space; hide = slide away under a window; below = windows go under the bar. The looks per state (touched, maximised, full-screen) are in edit mode › Bar"; key: "barVisibility"
                            Row { spacing: 6
                                Chip { text: "Never touch"; on: Config.barVisibility === "always"; onTapped: win.setKey("barVisibility", "always", true) }
                                Chip { text: "Hide"; on: Config.barVisibility === "dodge"; onTapped: win.setKey("barVisibility", "dodge", true) }
                                Chip { text: "Below"; on: Config.barVisibility === "below"; onTapped: win.setKey("barVisibility", "below", true) } } }
                        Row_ { label: "Dock and windows"; key: "dockVisibility"
                            Row { spacing: 6
                                Chip { text: "Never touch"; on: Config.dockVisibility === "always"; onTapped: win.setKey("dockVisibility", "always", true) }
                                Chip { text: "Hide"; on: Config.dockVisibility === "dodge"; onTapped: win.setKey("dockVisibility", "dodge", true) }
                                Chip { text: "Below"; on: Config.dockVisibility === "below"; onTapped: win.setKey("dockVisibility", "below", true) } } }
                        Row_ { label: "Snap zones"; hint: "While you drag a window a strip of layouts appears under the bar; drop on one to tile the window there"; key: "snapZones"
                            GlassSwitch { checked: Config.get("snapZones", true) !== false; onToggled: on => win.setKey("snapZones", on, true) } }
                        Row_ { label: "Record sound"; hint: "Screen recordings include what the computer plays. The microphone is never recorded"; key: "recordSound"
                            GlassSwitch { checked: Config.recordSound; onToggled: on => win.setKey("recordSound", on, true) } }
                        Row_ { label: "Live level meter"; hint: "The now-playing bars follow the real sound level. Redraws the bar about 25 times a second while music plays (about 1-2 % GPU here); off = still bars"; key: "levelMeter"
                            GlassSwitch { checked: Config.levelMeter; onToggled: on => win.setKey("levelMeter", on, true) } }
                        Row_ { label: "Frame meter"; hint: "Frames per second and the longest frame gap, on the bar's and the dock's surface. Reads idle when nothing repaints"; key: "showFps"
                            GlassSwitch { checked: Config.showFps; onToggled: on => win.setKey("showFps", on, true) } } }
                    Section { title: "Notifications"
                        Row_ { label: "Quiet during games and full screen"; hint: "No popups then; they wait in the history. Critical ones still show"; key: "quietWhenBusy"
                            GlassSwitch { checked: Config.quietWhenBusy; onToggled: on => win.setKey("quietWhenBusy", on, true) } } }
                    Section { title: "Keys"
                        Row_ { label: "Search"; hint: "Meta + Space"; Text { text: "Meta+Space"; color: Config.inkDim; font.pixelSize: 12 } }
                        Row_ { label: "Launcher"; hint: "Tap Meta"; Text { text: "Meta"; color: Config.inkDim; font.pixelSize: 12 } }
                        Row_ { label: "Switch windows"; Text { text: "Alt+Tab"; color: Config.inkDim; font.pixelSize: 12 } } } }

                // Desktop
                Column { visible: win.page === 4; width: parent.width; spacing: 18
                    Section { title: "Wallpaper"
                        Item { width: parent.width; height: wpGrid.implicitHeight + 24
                            readonly property var files: win.page === 4 ? Shell.wallpaperFiles(Config.wallpaperFolder) : []
                            readonly property string current: Config.wallpaper !== "" ? Config.wallpaper : Shell.plasmaWallpaper()
                            Flow { id: wpGrid; x: 12; y: 12; width: parent.width - 24; spacing: 10
                                Repeater { model: parent.parent.files
                                    Item { id: th; required property string modelData; width: (wpGrid.width - 20) / 3; height: width * 0.30 + 4
                                        readonly property bool current: modelData === parent.parent.current
                                        Rectangle { anchors.fill: parent; radius: 10; color: Config.fg(0.05); border.width: th.current ? 2 : 1; border.color: Config.fg(th.current ? 0.85 : (thh.hovered ? 0.35 : 0.10)) }
                                        Image { anchors.fill: parent; anchors.margins: 3; source: "file://" + th.modelData; sourceSize: Qt.size(360, 110); fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true
                                            opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 200 } } }
                                        HoverHandler { id: thh }
                                        // Plasma's desktop covers our own layer while it runs, so hand the picture to Plasma as well: one pick works in both modes
                                        TapHandler { onTapped: { win.setKey("wallpaper", th.modelData, true); if (Shell.plasmaRunning) Shell.runDetached("plasma-apply-wallpaperimage", [th.modelData]) } } } } } }
                        Row_ { label: "Follow Plasma's wallpaper"; hint: Config.wallpaper === "" ? "On: the shell shows what Plasma shows" : "Off: you picked one above"; key: "wallpaper"
                            Chip { text: "Follow Plasma"; on: Config.wallpaper === ""; onTapped: Shell.removeConfigKey("wallpaper") } }
                        Text { x: 16; bottomPadding: 10; width: parent.width - 32; wrapMode: Text.Wrap; color: Config.inkDim; font.pixelSize: 12
                            text: "Pictures from " + Config.wallpaperFolder + ". A pick is applied to the shell's own background layer and, while Plasma's desktop is running, to Plasma as well." } }
                    Section { title: "Folder colour"; visible: Shell.hasProgram("glass-folder-color")
                        Item { width: parent.width; height: fflow.implicitHeight + 24
                            Flow { id: fflow; x: 14; y: 12; width: parent.width - 28; spacing: 8
                                Repeater { model: [ ["blue", "#5294e2"], ["indigo", "#5c6bc0"], ["bluegrey", "#607d8b"], ["nordic", "#5e81ac"], ["darkcyan", "#45abb7"], ["violet", "#7e57c2"], ["grey", "#8e8e8e"], ["black", "#4f4f4f"] ]   // literal-ok: colour swatches
                                    Chip { required property var modelData; text: modelData[0]; dot: modelData[1]
                                        onTapped: Shell.runDetached("glass-folder-color", [modelData[0]]) } } } }
                        Text { x: 16; bottomPadding: 10; text: "Applies to your Papirus copy. File managers show it after a restart."; color: Config.inkDim; font.pixelSize: 12 } }
                    Section { title: "System"
                        Row_ { label: "Colours, fonts, Plasma's wallpaper"; hint: "Plasma's own settings"; Chip { text: "Open System Settings"; onTapped: Shell.runDetached("systemsettings", []) } } } }

                // About
                Column { visible: win.page === 5; width: parent.width; spacing: 18
                    Section { title: "Sirca Shell"
                        Row_ { label: "Version"; Text { text: Shell.version + (Shell.buildCommit !== "" ? "  ·  build " + Shell.buildCommit.substring(0, 7) : ""); color: Config.inkDim; font.pixelSize: 12; font.features: { "tnum": 1 } } }
                        Row_ { label: "Config file"; Text { text: Shell.configPath(); color: Config.inkDim; font.pixelSize: 12 } }
                        Row_ { label: "Changed settings"; Text { text: Config.user ? Object.keys(Config.user).filter(k => k !== "launchers").length + " keys" : "0 keys"; color: Config.inkDim; font.pixelSize: 12 } }
                        Row_ { label: "Reload the shell"; hint: "Checks the build first; a broken build is refused"; Chip { text: "Reload"; enabled: Shell.toolPath("sirca-shell-reload") !== ""; opacity: enabled ? 1 : 0.4; onTapped: { const p = Shell.toolPath("sirca-shell-reload"); if (p !== "") Shell.runDetached(p, []) } } } } }
            } } }
}
