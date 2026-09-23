// The bar's "weather" widget: the current temperature and a small icon, from the Weather singleton (Open-Meteo, opt-in:
// config `weather: true`). Takes no room while weather is off or nothing has been fetched yet; a click opens the clock
// popup, which holds the card with the hours. TopBar places it like the date widget (see the hook in the README's notes).
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell

Item {
    id: ww
    signal clicked()
    signal setupRequested()                                       // no location yet: the settings page with the place search
    property bool allowed: true                                   // placed in the bar and not in edit mode
    readonly property bool hasData: Weather.enabled && Weather.ready
    // placed and switched on but nothing to show: say why instead of vanishing (a placed widget that shows nothing reads as broken)
    readonly property bool pending: Weather.enabled && !Weather.ready
    readonly property bool hovered: wh.hovered
    visible: opacity > 0.01
    opacity: (hasData || pending) && allowed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Config.normal } }
    height: 29
    width: hasData ? row.implicitWidth + 16 : pending ? prow.implicitWidth + 16 : 0
    // the singleton reads its keys from the user config (placing the widget counts as the opt-in, see Config.weatherOn);
    // every placement of the widget or the card may do this, it is idempotent
    function configure() { const c = Object.assign({}, Config.user || {}); c.weather = Config.weatherOn; Weather.configure(c) }
    Connections { target: Config; function onUserChanged() { ww.configure() } }
    Component.onCompleted: configure()
    Rectangle { visible: Config.barHoverPills; anchors.centerIn: parent; width: parent.width; height: 27; radius: 13.5; color: Config.fg(ww.hovered ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
    Row { id: row; x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
        Kirigami.Icon { width: Math.round(18 * Config.barIconScale); height: width; anchors.verticalCenter: parent.verticalCenter; source: Weather.iconFor(Weather.code, Weather.isDay); roundToIconSize: false }
        Text { anchors.verticalCenter: parent.verticalCenter; color: Config.ink; font.pixelSize: 13; font.weight: Font.Medium; font.features: { "tnum": 1 }; text: Math.round(Weather.temperature) + "°" } }
    Row { id: prow; visible: ww.pending; x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
        Kirigami.Icon { width: Math.round(16 * Config.barIconScale); height: width; anchors.verticalCenter: parent.verticalCenter; isMask: true; color: Config.inkDim; roundToIconSize: false
            source: Weather.status === "no-location" ? "mark-location-symbolic" : Weather.status === "error" ? "dialog-warning-symbolic" : "view-refresh-symbolic" }
        Text { anchors.verticalCenter: parent.verticalCenter; color: Config.inkDim; font.pixelSize: 12
            text: Weather.status === "no-location" ? "Set location" : Weather.status === "error" ? "Weather: no data" : "Weather…" } }
    HoverHandler { id: wh }
    TapHandler { onTapped: ww.pending && Weather.status !== "loading" ? ww.setupRequested() : ww.clicked() }
}
