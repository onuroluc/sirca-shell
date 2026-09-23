// Quick settings' network backend (NetworkManager through Plasma's org.kde.plasma.networkmanagement). Behind a Loader
// (by URL) in QuickSettings.qml: it is a private Plasma module, so when it is missing or has changed only the network
// tile and page degrade ("Unavailable"), not the whole popup.
import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.networkmanagement as PlasmaNM
import "control/components" as NetParts

Item {
    id: nb
    NetParts.Network { id: net }
    readonly property bool wifiThere: net.availableDevices.wirelessDeviceAvailable
    readonly property bool wifiOn: wifiThere && net.enabledConnections.wirelessHwEnabled && net.enabledConnections.wirelessEnabled
    readonly property string name: { const t = net.netStatusText; if (!t) return "";
        return String(t).split("\n").map(l => { const m = l.match(/Connected to (.*)$/); return m ? m[1] : l }).filter(x => x !== "").join(" · ") }
    readonly property string icon: net.activeConnectionIcon || "network-wired-symbolic"
    readonly property var connections: net.appletProxyModel
    readonly property int stateActivated: PlasmaNM.Enums.Activated
    readonly property int stateActivating: PlasmaNM.Enums.Activating
    // VPNs (NetworkManager VPN plugins and WireGuard) are their own list on the Network page, apart from the networks.
    // Type is NetworkManagerQt's ConnectionType: WireGuard (19) is missing from plasma-nm's mirror enum, hence the number.
    function isVpn(model, row) { const t = model.data(model.index(row, 0), model.KItemModels.KRoleNames.role("Type"))
        return t === PlasmaNM.Enums.Vpn || t === 19 || String(model.data(model.index(row, 0), model.KItemModels.KRoleNames.role("VpnType")) || "") !== "" }
    readonly property var vpns: KItemModels.KSortFilterProxyModel { sourceModel: net.appletProxyModel; filterRowCallback: (row, parent) => nb.isVpn(sourceModel, row) }
    readonly property var networks: KItemModels.KSortFilterProxyModel { sourceModel: net.appletProxyModel; filterRowCallback: (row, parent) => !nb.isVpn(sourceModel, row) }
    readonly property int vpnCount: vpns.count
    // the VPN page section shows a hint when NetworkManager knows none; the tile's status names the active one
    property int vpnTick: 0                       // model data is not a binding dependency: the Connections below bumps this
    readonly property var _vt: Connections { target: nb.vpns; function onDataChanged() { nb.vpnTick++ } function onRowsInserted() { nb.vpnTick++ } function onRowsRemoved() { nb.vpnTick++ } function onModelReset() { nb.vpnTick++ } }
    readonly property string activeVpn: { nb.vpnTick; let s = ""; const m = vpns, r = m.KItemModels.KRoleNames.role("ItemUniqueName"), st = m.KItemModels.KRoleNames.role("ConnectionState")
        for (let i = 0; i < m.count; ++i) { const x = m.index(i, 0); if (m.data(x, st) === stateActivated) { s = String(m.data(x, r) || ""); break } } return s }
    function enableWireless(on) { net.handler.enableWireless(on) }
    function activate(path, device, specific) { net.handler.activateConnection(path, device, specific) }
    function deactivate(path, device) { net.handler.deactivateConnection(path, device) }
}
