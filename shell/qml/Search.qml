// Search (Meta+Space): one field for everything. Apps, settings, files, maths, unit conversion, windows, shell commands …
// The results come from KRunner's engine (Milou.ResultsModel), so every runner the system has works; the panel is ours.
// Two modes of its own: ":smile" (or the Emoji chip) is the emoji picker, Enter copies the emoji; "pick" (or the Colour
// chip) calls KWin's screen colour picker and shows what was clicked as a swatch, hex and rgb already on the clipboard.
// An overlay surface that takes the keyboard while it is up. Only the panel takes input (the rest of the surface is
// click-through), and the search closes when it loses keyboard focus, i.e. as soon as anything else is clicked: that
// click, or a window drag, goes to its window untouched.
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell
import "Glass"

Window {
    id: sw
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false
    width: Screen.width; height: Screen.height
    signal opened()

    readonly property int panelW: 700
    readonly property int fieldH: 62
    readonly property int rowH: 46
    readonly property int maxListH: 9 * rowH + 40
    // ---- modes: chips (empty field) | emoji (":…") | pick ("pick") | swatch (a colour was picked) | krunner (anything else)
    readonly property bool emojiMode: field.text.startsWith(":")
    readonly property bool pickMode: !emojiMode && /^pick( colou?r)?$/i.test(field.text.trim())
    property bool swatchShown: false
    property color swatch: "transparent"
    readonly property string mode: swatchShown ? "swatch" : emojiMode ? "emoji" : pickMode ? "pick" : field.text === "" ? "chips" : "krunner"
    readonly property int emojiCols: 12
    readonly property int emojiCell: Math.floor((panelW - 32) / emojiCols)
    readonly property int emojiRows: Math.min(5, Math.ceil(emojis.count / emojiCols))
    readonly property real emojiH: emojis.count > 0 ? emojiRows * emojiCell + 40 : 54
    readonly property real listH: mode === "krunner" ? (list.count > 0 ? Math.min(list.contentHeight + 14, maxListH) : (!querying ? 54 : 0))
                                : mode === "chips" ? 52 : mode === "emoji" ? emojiH : mode === "pick" ? rowH + 14 : 104
    property real panelH: fieldH + listH
    Behavior on panelH { Spring {} }
    readonly property rect panel: Qt.rect(Math.round((width - panelW) / 2), Math.round(height * 0.20), panelW, Math.round(panelH))
    property bool setupDone: false
    property real show: 0                                     // content fade / rise
    Behavior on show { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    property string toast: ""                                 // "😀 copied" for a moment, then the panel closes
    property alias field: field                               // (offscreen previews and tests drive the panel through it)
    Timer { id: toastEnd; interval: 900; onTriggered: sw.close_() }
    EmojiModel { id: emojis; limit: sw.emojiCols * 5; active: sw.visible && sw.emojiMode; query: active ? field.text.substring(1) : "" }
    ColorPick { id: picker
        onPicked: c => { picker.copy(sw.hex(c)); sw.swatch = c; sw.open(); sw.swatchShown = true }
        onFailed: why => console.log("colour pick:", why) }
    function hex(c) { const h = n => ("0" + Math.round(n * 255).toString(16)).slice(-2); return "#" + h(c.r) + h(c.g) + h(c.b) }
    function rgb(c) { return "rgb(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ")" }

    function toggle() { visible ? close_() : open() }
    function open() {
        if (!setupDone) { Shell.setupSearch(sw); setupDone = true }
        field.text = ""; list.currentIndex = 0; grid.currentIndex = 0; swatchShown = false; toast = ""; toastEnd.stop()
        visible = true; show = 1; field.forceActiveFocus(); shapeLater.restart(); sw.opened()
        armed = false; Shell.setKeyboardMode(sw, "exclusive"); relax.restart()
    }
    // same focus hand-over as the bar's popups (Surface.popupFocus): grab, relax, then close on loss
    property bool armed: false
    Timer { id: relax; interval: 160; onTriggered: { Shell.setKeyboardMode(sw, "ondemand"); arm.restart() } }
    Timer { id: arm; interval: 220; onTriggered: sw.armed = true }
    onActiveChanged: if (visible && armed && !previewing && !active) lost.restart(); else lost.stop()
    Timer { id: lost; interval: 80; onTriggered: if (sw.visible && !sw.active) sw.close_() }
    // for looking at it (screenshots, tests): opens with a query, WITHOUT taking the keyboard, and closes by itself
    function preview(q) {
        if (!setupDone) { Shell.setupSearch(sw); setupDone = true }
        Shell.setKeyboardMode(sw, "none"); previewing = true
        field.text = q; list.currentIndex = 0; grid.currentIndex = 0; visible = true; show = 1; shapeLater.restart(); previewEnd.restart()
    }
    property bool previewing: false
    Timer { id: previewEnd; interval: 3500; onTriggered: sw.close_() }
    function close_() {
        if (previewing) { previewing = false; Shell.setKeyboardMode(sw, "exclusive") }
        if (!visible) return;
        visible = false; show = 0; field.text = ""; swatchShown = false; toast = ""; toastEnd.stop(); armed = false; relax.stop(); arm.stop()
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "clearLobes", "sii", ["sirca-shell", sw.width, sw.height])
    }
    function runCurrent() {
        if (toast !== "") return;
        if (mode === "emoji") { copyEmoji(grid.currentIndex); return }
        if (mode === "pick") { startPick(); return }
        if (mode === "swatch") { close_(); return }
        if (mode !== "krunner" || list.count < 1) return;
        const i = Math.max(0, Math.min(list.currentIndex, list.count - 1));
        if (results && results.run(results.index(i, 0))) close_();
    }
    function copyEmoji(i) {
        if (i < 0 || i >= emojis.count) return;
        const e = emojis.data(emojis.index(i, 0), Qt.UserRole + 1); if (!e) return;
        emojis.copy(e); toast = e + "  copied"; toastEnd.restart() }
    // the panel goes away while KWin's picker is up (it would sit in the way); picked() brings it back with the swatch
    function startPick() { close_(); picker.pick() }
    Timer { id: shapeLater; interval: 16; onTriggered: sw.pushShape() }
    function pushShape() {
        if (!visible) return;
        Shell.setShape(sw, [{ x: panel.x, y: panel.y, w: panel.width, h: panel.height, r: Config.cornerRadius }]);   // blur AND input: only the panel
        Shell.dbusSendTyped("org.kde.KWin", "/Glass", "org.kde.KWin.Glass", "setLobes", "siivdd", ["sirca-shell", sw.width, sw.height, [panel.x, panel.y, panel.width, panel.height], Config.cornerRadius, 1]);
        sw.requestUpdate();
    }
    onPanelChanged: if (visible) shapeLater.restart()
    onWidthChanged: if (visible) shapeLater.restart()
    onHeightChanged: if (visible) shapeLater.restart()

    // the results model comes from SearchResults.qml by URL (Milou is Plasma-internal; see there). It only sees queries
    // meant for it: ":smile" and "pick" are ours
    Loader { id: resultsLoader; source: "SearchResults.qml"; onLoaded: item.queryString = Qt.binding(() => sw.visible && sw.mode === "krunner" ? field.text : "")
        onStatusChanged: if (status === Loader.Error) console.warn("search: KRunner results unavailable (org.kde.milou)") }
    readonly property var results: resultsLoader.item
    readonly property bool querying: results ? results.querying : false

    LobeShape { anchors.fill: parent; bar: sw.panel; reach: Qt.rect(sw.panel.x, sw.panel.y, sw.panelW, sw.fieldH + sw.maxListH) }   // reach: the tallest the panel gets, so its spring does not resize the shadow layers per frame

    Item { x: sw.panel.x; y: sw.panel.y; width: sw.panel.width; height: sw.panel.height; clip: true
        opacity: sw.show; transform: Translate { y: (1 - sw.show) * 10 }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }                                  // clicks on the panel stay here

        // ---- the field ----
        Item { id: fieldRow; width: parent.width; height: sw.fieldH
            Kirigami.Icon { id: glass; x: 22; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; isMask: true; color: Config.fgSolid; opacity: 0.75; roundToIconSize: false
                source: sw.mode === "emoji" ? "smiley-symbolic" : sw.mode === "pick" || sw.mode === "swatch" ? "color-picker" : "search-symbolic" }
            Text { anchors.left: field.left; anchors.verticalCenter: parent.verticalCenter; visible: field.text === "" && !sw.swatchShown; color: Config.inkDim; font.pixelSize: 20
                text: "Search apps, files, settings, or type a sum" }
            TextInput { id: field
                anchors.left: glass.right; anchors.leftMargin: 14; anchors.right: parent.right; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter
                color: Config.ink; font.pixelSize: 20; clip: true; focus: true; selectByMouse: true
                selectionColor: Config.fg(0.25); selectedTextColor: Config.fgSolid
                cursorDelegate: Rectangle { width: 1.5; color: Config.fgSolid; visible: field.activeFocus
                    SequentialAnimation on opacity { running: field.activeFocus; loops: Animation.Infinite
                        PauseAnimation { duration: 500 } NumberAnimation { to: 0; duration: 120 } PauseAnimation { duration: 380 } NumberAnimation { to: 1; duration: 120 } } }
                onTextChanged: { list.currentIndex = 0; grid.currentIndex = 0; if (sw.swatchShown && text !== "") sw.swatchShown = false }
                Keys.onPressed: e => {
                    const emoji = sw.mode === "emoji", cols = sw.emojiCols, n = emoji ? grid.count : list.count
                    const cur = emoji ? grid.currentIndex : list.currentIndex
                    const set = i => { i = Math.max(0, Math.min(n - 1, i)); if (emoji) grid.currentIndex = i; else list.currentIndex = i }
                    if (e.key === Qt.Key_Escape) { if (sw.swatchShown) sw.swatchShown = false; else if (text !== "") text = ""; else sw.close_(); e.accepted = true }
                    else if (e.key === Qt.Key_Down || (e.key === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier))) { set(cur + (emoji && e.key === Qt.Key_Down ? cols : 1)); e.accepted = true }
                    else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) { set(cur - (emoji && e.key === Qt.Key_Up ? cols : 1)); e.accepted = true }
                    // in the emoji grid Left / Right walk the cells while the cursor sits at the end of the text; earlier in the text they still move the cursor
                    else if (emoji && e.key === Qt.Key_Right && cursorPosition === text.length) { set(cur + 1); e.accepted = true }
                    else if (emoji && e.key === Qt.Key_Left && cursorPosition === text.length) { set(cur - 1); e.accepted = true }
                    else if (e.key === Qt.Key_PageDown) { set(cur + (emoji ? cols * 3 : 6)); e.accepted = true }
                    else if (e.key === Qt.Key_PageUp) { set(cur - (emoji ? cols * 3 : 6)); e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { sw.runCurrent(); e.accepted = true }
                }
            }
        }
        Rectangle { y: sw.fieldH - 1; x: 16; width: parent.width - 32; height: 1; color: Config.fg(0.08); visible: sw.listH > 1 }

        // ---- chips: the two modes of our own, for whoever does not know the prefixes ----
        Row { x: 16; y: sw.fieldH + 10; spacing: 8; visible: sw.mode === "chips"; opacity: sw.mode === "chips" ? 1 : 0
            Repeater { model: [ { label: "Emoji", icon: "smiley-symbolic", hint: ":", text: ":" }, { label: "Pick a colour", icon: "color-picker", hint: "pick", text: "pick" } ]
                Rectangle { id: chip; required property var modelData; height: 32; width: cr.implicitWidth + 24; radius: 16
                    color: Config.fg(ch.hovered ? 0.12 : 0.06); border.width: 1; border.color: Config.fg(0.12); Behavior on color { ColorAnimation { duration: Config.quick } }
                    Row { id: cr; anchors.centerIn: parent; spacing: 7
                        Kirigami.Icon { width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter; source: chip.modelData.icon; isMask: true; color: Config.fgSolid; opacity: 0.85; roundToIconSize: false }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.label; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.hint; color: Config.inkDim; font.pixelSize: 11; font.family: "monospace" } }
                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { if (chip.modelData.text === "pick") sw.startPick(); else { field.text = chip.modelData.text; field.cursorPosition = field.text.length } } } } } }

        // ---- results ----
        ListView { id: list
            x: 8; y: sw.fieldH + 6; width: parent.width - 16; height: Math.max(0, sw.maxListH - 14); visible: sw.mode === "krunner"
            model: sw.results; clip: true; interactive: contentHeight > height; boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0; keyNavigationEnabled: false
            section.property: "category"; section.criteria: ViewSection.FullString
            section.delegate: Item { required property string section; width: list.width; height: 26
                Text { x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 4; text: parent.section; color: Config.inkDim; opacity: 0.8
                    font.pixelSize: 11; font.weight: Font.Medium; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 } }
            delegate: Item { id: row
                required property int index
                required property var model
                width: list.width; height: sw.rowH
                readonly property bool sel: index === list.currentIndex
                // the same glass tile as menu rows: faint fill + rim when selected
                Rectangle { anchors.fill: parent; anchors.topMargin: 1; anchors.bottomMargin: 1; radius: 12
                    color: Config.fg(row.sel ? 0.13 : (rh.hovered ? 0.06 : 0)); border.width: 1; border.color: Config.fg(row.sel ? 0.16 : 0)
                    Behavior on color { ColorAnimation { duration: Config.quick } } }
                Kirigami.Icon { id: ic; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; source: row.model.decoration; roundToIconSize: false }
                Column { anchors.left: ic.right; anchors.leftMargin: 12; anchors.right: hint.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                    Text { width: parent.width; text: row.model.display ?? ""; color: Config.ink; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight; maximumLineCount: 1; textFormat: Text.PlainText }
                    Text { width: parent.width; text: row.model.subtext ?? ""; visible: text !== ""; color: Config.inkDim; font.pixelSize: 12; elide: Text.ElideMiddle; maximumLineCount: 1; textFormat: Text.PlainText } }
                Text { id: hint; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: "↵"; color: Config.inkDim; font.pixelSize: 15; opacity: row.sel ? 0.9 : 0 }
                HoverHandler { id: rh }
                TapHandler { onTapped: { list.currentIndex = row.index; sw.runCurrent() } } }
        }
        Text { x: 24; y: sw.fieldH + 18; visible: sw.mode === "krunner" && list.count === 0 && field.text !== "" && !sw.querying; text: "Nothing found"; color: Config.inkDim; font.pixelSize: 14 }

        // ---- emoji grid (":smile") ----
        GridView { id: grid; x: 16; y: sw.fieldH + 8; width: sw.emojiCols * sw.emojiCell; height: sw.emojiRows * sw.emojiCell; visible: sw.mode === "emoji"
            model: emojis; cellWidth: sw.emojiCell; cellHeight: sw.emojiCell; clip: true; interactive: false; keyNavigationEnabled: false
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
            delegate: Item { id: cell; required property int index; required property var model; width: sw.emojiCell; height: sw.emojiCell
                readonly property bool sel: index === grid.currentIndex
                Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 12; color: Config.fg(cell.sel ? 0.14 : (eh.hovered ? 0.07 : 0)); border.width: 1; border.color: Config.fg(cell.sel ? 0.18 : 0)
                    Behavior on color { ColorAnimation { duration: Config.quick } } }
                Text { anchors.centerIn: parent; text: cell.model.emoji; font.pixelSize: Math.round(sw.emojiCell * 0.52); renderType: Text.NativeRendering }
                HoverHandler { id: eh; onHoveredChanged: if (hovered) grid.currentIndex = cell.index }
                TapHandler { onTapped: { grid.currentIndex = cell.index; sw.copyEmoji(cell.index) } } } }
        Text { x: 24; y: sw.fieldH + 18; visible: sw.mode === "emoji" && emojis.count === 0; text: "No emoji for that"; color: Config.inkDim; font.pixelSize: 14 }
        Item { x: 16; y: sw.fieldH + 8 + grid.height + 6; width: parent.width - 32; height: 26; visible: sw.mode === "emoji" && emojis.count > 0
            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; color: Config.ink; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width - 120
                text: grid.currentItem ? grid.currentItem.model.name : "" }
            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "↵ copies"; color: Config.inkDim; font.pixelSize: 12 } }

        // ---- colour: the one row that starts the picker, and the swatch afterwards ----
        Item { x: 8; y: sw.fieldH + 6; width: parent.width - 16; height: sw.rowH; visible: sw.mode === "pick"
            Rectangle { anchors.fill: parent; anchors.topMargin: 1; anchors.bottomMargin: 1; radius: 12; color: Config.fg(0.13); border.width: 1; border.color: Config.fg(0.16) }
            Kirigami.Icon { id: pickIc; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; source: "color-picker"; isMask: true; color: Config.fgSolid; roundToIconSize: false }
            Column { anchors.left: pickIc.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                Text { text: "Pick a colour from the screen"; color: Config.ink; font.pixelSize: 14; font.weight: Font.Medium }
                Text { text: "Click anywhere; the hex value is copied"; color: Config.inkDim; font.pixelSize: 12 } }
            Text { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: "↵"; color: Config.inkDim; font.pixelSize: 15 }
            TapHandler { onTapped: sw.startPick() } }
        Item { x: 16; y: sw.fieldH + 12; width: parent.width - 32; height: 80; visible: sw.mode === "swatch"
            Rectangle { id: swatchBox; width: 80; height: 80; radius: 16; color: sw.swatch; border.width: 1; border.color: Config.fg(0.25) }   // literal-ok: the picked colour itself
            Column { anchors.left: swatchBox.right; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Text { text: sw.hex(sw.swatch); color: Config.ink; font.pixelSize: 22; font.weight: Font.DemiBold; font.family: "monospace" }
                Text { text: sw.rgb(sw.swatch); color: Config.inkDim; font.pixelSize: 13; font.family: "monospace" }
                Text { text: "Hex copied to the clipboard  ·  Esc closes"; color: Config.inkDim; font.pixelSize: 11 } }
            Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 30; width: rgbBtnT.implicitWidth + 22; radius: 15
                color: Config.fg(rbh.hovered ? 0.14 : 0.07); border.width: 1; border.color: Config.fg(0.12)
                Text { id: rgbBtnT; anchors.centerIn: parent; text: "Copy rgb()"; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium }
                HoverHandler { id: rbh } TapHandler { onTapped: { picker.copy(sw.rgb(sw.swatch)); sw.toast = sw.rgb(sw.swatch) + "  copied"; toastEnd.restart() } } } }

        // ---- toast: what was just copied, over the content, then the panel closes ----
        Rectangle { visible: sw.toast !== ""; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - height - 10; height: 40; width: toastT.implicitWidth + 36; radius: 20
            color: Config.popSurface; border.width: 1; border.color: Config.fg(0.16)
            Text { id: toastT; anchors.centerIn: parent; text: sw.toast; color: Config.ink; font.pixelSize: 15; font.weight: Font.Medium } }
    }
}
