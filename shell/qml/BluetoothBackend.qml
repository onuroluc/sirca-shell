// Quick settings' Bluetooth backend (BlueZ through org.kde.bluezqt). Behind a Loader (by URL) in QuickSettings.qml so a
// missing module only leaves the Bluetooth tile "Unavailable".
import QtQuick
import org.kde.bluezqt 1.0 as BluezQt

QtObject {
    readonly property QtObject bt: BluezQt.Manager
    readonly property bool on: bt.bluetoothOperational
    readonly property string name: { for (let i = 0; i < bt.devices.length; ++i) if (bt.devices[i].connected) return bt.devices[i].name; return "" }
    function toggle() { const want = !bt.bluetoothOperational; bt.bluetoothBlocked = !want; for (let i = 0; i < bt.adapters.length; ++i) bt.adapters[i].powered = want }
}
