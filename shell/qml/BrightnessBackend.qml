// Quick settings' screen brightness backend (org.kde.plasma.private.brightnesscontrolplugin, a PRIVATE Plasma module).
// Behind a Loader (by URL) in QuickSettings.qml: without it the brightness slider and the display's name are simply absent.
import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.brightnesscontrolplugin

QtObject {
    id: bb
    readonly property var control: ScreenBrightnessControl { isSilent: true }     // no OSD per step while dragging our own slider
    property var info: []
    readonly property var _displays: Connections { target: bb.control.displays
        function update() {
            const roles = ["label", "brightness", "maxBrightness", "displayName"].map(r => target.KItemModels.KRoleNames.role(r));
            bb.info = [...Array(target.rowCount()).keys()].map(i => { const x = target.index(i, 0);
                return { label: target.data(x, roles[0]), brightness: target.data(x, roles[1]), maxBrightness: target.data(x, roles[2]), displayName: target.data(x, roles[3]) } }) }
        function onDataChanged() { update() } function onModelReset() { update() } function onRowsInserted() { update() } function onRowsRemoved() { update() }
        Component.onCompleted: update() }
    readonly property var screen0: info.length > 0 ? info[0] : null
    readonly property bool canDim: control.isBrightnessAvailable && screen0 !== null
    readonly property real pct: screen0 ? 100 * screen0.brightness / Math.max(1, screen0.maxBrightness) : 0
    readonly property string label: screen0 ? String(screen0.label || "") : ""
    function setPct(v) { if (screen0) control.setBrightness(screen0.displayName, Math.round(v / 100 * screen0.maxBrightness)) }
}
