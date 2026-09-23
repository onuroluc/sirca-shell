// Notification history: the popup behind the bell. Everything that arrived, newest first, with Do Not Disturb and
// Clear all. Opening it marks everything as read (the bell's dot goes away). A filter field narrows the list by app,
// title or body (the grouping stays: an app's matching entries are still one stack); critical entries carry the accent
// edge, low-priority ones are dimmer. clearAll() is also behind the Meta+Shift+N shortcut ("notif-clear").
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as NotificationManager
import SircaShell

Item {
    id: center
    // job details for the cards: "12.4 MB of 80 MB  ·  3.1 MB/s"; a running job that reports no percentage has no known size
    function bytes(n) { n = Number(n) || 0; const u = ["B", "KB", "MB", "GB", "TB"]; let i = 0; while (n >= 1000 && i < u.length - 1) { n /= 1000; ++i } return (i === 0 ? n : n.toFixed(n < 10 ? 2 : 1)) + " " + u[i] }
    function jobLine(m) { const d = m.jobDetails; if (!d) return ""; const done = Number(d.processedBytes) || 0, total = Number(d.totalBytes) || 0, speed = Number(d.speed) || 0
        let s = done > 0 ? (total > 0 ? bytes(done) + " of " + bytes(total) : bytes(done)) : ""; if (speed > 0) s += (s ? "  ·  " : "") + bytes(speed) + "/s"; return s }
    function jobUnknown(m) { const d = m.jobDetails; return m.jobState === NotificationManager.Notifications.JobStateRunning && !(m.percentage > 0) && !(d && Number(d.totalBytes) > 0) }
    property bool open: false
    property alias filterText: filter.text                  // (tests drive the filter through it)
    readonly property int unread: history.unreadNotificationsCount
    readonly property int total: list.count
    readonly property bool dnd: settings.notificationsInhibitedByApplication
        || (settings.notificationsInhibitedUntil instanceof Date && !isNaN(settings.notificationsInhibitedUntil.getTime()) && Date.now() < settings.notificationsInhibitedUntil.getTime())
    implicitWidth: 380
    readonly property int listY: filterRow.visible ? 90 : 52
    implicitHeight: listY + (list.count > 0 ? Math.max(shownCount === 0 ? 40 : 0, Math.min(list.contentHeight, 520)) + 6 : 84)
    onOpenChanged: if (open) { history.lastRead = undefined; list.positionViewAtBeginning(); if (filter.text !== "") filter.text = ""; if (filterRow.visible) filter.forceActiveFocus() }
    // everything goes: entries still on screen as popups are expired first (clear() only takes expired ones), running jobs stay
    function clearAll() {
        for (let i = history.count - 1; i >= 0; --i) { const idx = history.index(i, 0)
            if (history.data(idx, NotificationManager.Notifications.TypeRole) === NotificationManager.Notifications.JobType) continue
            if (!history.data(idx, NotificationManager.Notifications.ExpiredRole)) history.expire(idx) }
        history.clear(NotificationManager.Notifications.ClearExpired) }
    function toggleDnd() {
        if (dnd) { settings.notificationsInhibitedUntil = undefined; settings.revokeApplicationInhibitions() }
        else { const d = new Date(); d.setFullYear(d.getFullYear() + 1); settings.notificationsInhibitedUntil = d }
        settings.save() }
    function ago(date) { if (!date) return ""; const s = Math.max(0, (Date.now() - new Date(date).getTime()) / 1000);
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + " min" : s < 86400 ? Math.floor(s / 3600) + " h" : Math.floor(s / 86400) + " d" }
    property int tick: 0
    // ---- grouping: entries per app, which row starts an app's run, which apps are opened up. With a filter, only the
    // matching rows take part (`shown`), so a stack's count and its first card are those of the matches
    property var counts: ({})
    property var firstRow: ({})
    property var expanded: ({})
    property var shown: ({})
    readonly property int shownCount: Object.keys(shown).length
    function appOf(row) { return history.data(history.index(row, 0), NotificationManager.Notifications.ApplicationNameRole) || "" }
    function matches(row) { const words = filter.text.toLowerCase().split(/\s+/).filter(w => w !== ""); if (words.length === 0) return true
        const idx = history.index(row, 0); const R = NotificationManager.Notifications
        const hay = ((history.data(idx, R.ApplicationNameRole) || "") + " " + (history.data(idx, R.SummaryRole) || "") + " " + String(history.data(idx, R.BodyRole) || "").replace(/<[^>]*>/g, "")).toLowerCase()
        return words.every(w => hay.indexOf(w) >= 0) }
    function recount() { const c = {}, f = {}, s = {}; for (let i = 0; i < history.count; ++i) { if (!matches(i)) continue; s[i] = true; const a = appOf(i); if (c[a] === undefined) { c[a] = 0; f[a] = i } c[a]++ } counts = c; firstRow = f; shown = s }
    function toggleGroup(app) { const e = Object.assign({}, expanded); e[app] = !e[app]; expanded = e }
    Component.onCompleted: recount()
    Timer { interval: 30000; repeat: true; running: center.open; onTriggered: center.tick++ }

    NotificationManager.Settings { id: settings }
    NotificationManager.Notifications { id: history
        showExpired: true; showDismissed: true; showJobs: settings.jobsInNotifications
        blacklistedDesktopEntries: settings.historyBlacklistedApplications; blacklistedNotifyRcNames: settings.historyBlacklistedServices
        sortMode: NotificationManager.Notifications.SortByDate; sortOrder: Qt.DescendingOrder
        // flat, but one app's notifications next to each other (groups ordered by their newest entry): the list below turns
        // every app with more than one entry into a stack that opens on a click
        groupMode: NotificationManager.Notifications.GroupApplicationsFlat
        onCountChanged: center.recount(); onRowsInserted: center.recount(); onRowsRemoved: center.recount(); onModelReset: center.recount(); onLayoutChanged: center.recount()
        urgencies: NotificationManager.Notifications.CriticalUrgency | NotificationManager.Notifications.NormalUrgency | (settings.lowPriorityHistory ? NotificationManager.Notifications.LowUrgency : 0) }

    component HeadBtn: Rectangle { id: hb; property string label; property string icon; property bool on: false; signal tapped()
        height: 30; width: hbr.implicitWidth + 22; radius: 15
        color: Config.fg(on ? 0.18 : (hbh.hovered ? 0.11 : 0.055)); border.width: 1; border.color: Config.fg(on ? 0.26 : 0.10)
        Behavior on color { ColorAnimation { duration: Config.quick } }
        Row { id: hbr; anchors.centerIn: parent; spacing: 6
            Kirigami.Icon { width: 13; height: 13; anchors.verticalCenter: parent.verticalCenter; source: hb.icon; isMask: true; color: Config.fgSolid; opacity: 0.9; roundToIconSize: false }
            Text { anchors.verticalCenter: parent.verticalCenter; text: hb.label; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium } }
        HoverHandler { id: hbh } TapHandler { onTapped: hb.tapped() } }

    Item { x: 8; y: 6; width: parent.width - 16; height: 40
        Text { anchors.verticalCenter: parent.verticalCenter; x: 4; text: "Notifications"; color: Config.ink; font.pixelSize: 16; font.weight: Font.DemiBold }
        Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            HeadBtn { label: "Do Not Disturb"; icon: center.dnd ? "notifications-disabled-symbolic" : "notifications-symbolic"; on: center.dnd; onTapped: center.toggleDnd() }
            HeadBtn { label: "Clear all"; icon: "edit-clear-history-symbolic"; visible: list.count > 0; onTapped: center.clearAll() } } }
    // ---- filter: app, title or body; only there when there is something to filter
    Rectangle { id: filterRow; visible: list.count > 0; x: 12; y: 50; width: parent.width - 24; height: 32; radius: 16
        color: Config.fg(filter.activeFocus ? 0.10 : 0.055); border.width: 1; border.color: Config.fg(filter.activeFocus ? 0.20 : 0.10)
        Behavior on color { ColorAnimation { duration: Config.quick } }
        Kirigami.Icon { id: filterIcon; x: 11; anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; source: "search-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.7; roundToIconSize: false }
        Text { anchors.left: filter.left; anchors.verticalCenter: parent.verticalCenter; visible: filter.text === ""; text: "Filter by app, title or text"; color: Config.inkDim; font.pixelSize: 12 }
        TextInput { id: filter; anchors.left: filterIcon.right; anchors.leftMargin: 8; anchors.right: clearFilter.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
            color: Config.ink; font.pixelSize: 12; clip: true; selectByMouse: true; selectionColor: Config.fg(0.25); selectedTextColor: Config.fgSolid
            onTextChanged: { center.recount(); list.positionViewAtBeginning() }
            Keys.onEscapePressed: e => { if (text !== "") text = ""; else e.accepted = false } }
        Item { id: clearFilter; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; visible: filter.text !== ""
            Rectangle { anchors.fill: parent; radius: 10; color: Config.fg(cfh.hovered ? 0.18 : 0.08) }
            Kirigami.Icon { anchors.centerIn: parent; width: 10; height: 10; source: "window-close-symbolic"; isMask: true; color: Config.fgSolid; roundToIconSize: false }
            HoverHandler { id: cfh } TapHandler { onTapped: filter.text = "" } }
        TapHandler { onTapped: filter.forceActiveFocus() } }

    ListView { id: list; x: 8; y: center.listY; width: parent.width - 16; height: Math.min(contentHeight, 520); clip: true; spacing: 0; model: history
        boundsBehavior: Flickable.StopAtBounds; interactive: contentHeight > height
        delegate: Item { id: row
            required property int index
            required property var model
            readonly property string app: model.applicationName || ""
            readonly property bool match: center.shown[index] === true
            readonly property int groupSize: center.counts[app] || 1
            readonly property bool first: center.firstRow[app] === index
            readonly property bool open: groupSize < 2 || !!center.expanded[app]
            readonly property bool stacked: groupSize > 1 && !open && first                 // the one visible card of a closed group
            readonly property bool hiddenRow: !match || (groupSize > 1 && !open && !first)
            width: list.width; clip: true
            height: hiddenRow ? 0 : (groupHead.visible ? 28 : 0) + h.height + (stacked ? 12 : 0) + 8
            opacity: hiddenRow ? 0 : 1; visible: height > 0.5
            Behavior on height { NumberAnimation { duration: Config.normal; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Config.normal } }
            // group header: app, how many, open/close
            Item { id: groupHead; visible: row.groupSize > 1 && row.first; width: parent.width; height: 28
                Text { x: 6; anchors.verticalCenter: parent.verticalCenter; text: row.app; color: Config.inkDim; font.pixelSize: 12; font.weight: Font.DemiBold }
                Rectangle { anchors.right: parent.right; anchors.rightMargin: 2; anchors.verticalCenter: parent.verticalCenter; height: 22; width: ght.implicitWidth + 20; radius: 11
                    color: Config.fg(ghh.hovered ? 0.11 : 0.055); Behavior on color { ColorAnimation { duration: Config.quick } }
                    Text { id: ght; anchors.centerIn: parent; text: row.open ? "Show less" : row.groupSize + " notifications"; color: Config.ink; font.pixelSize: 11; font.weight: Font.Medium }
                    HoverHandler { id: ghh; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: center.toggleGroup(row.app) } } }
            // the cards underneath a closed group, peeking out below the top one
            // (clipped to the strip below the top card: the cards are translucent, anything under them would show through)
            Item { visible: row.stacked; x: 0; y: h.y + h.height; width: row.width; height: 12; clip: true
                Repeater { model: row.stacked ? Math.min(2, row.groupSize - 1) : 0
                    Rectangle { required property int index; x: 12 * (index + 1); width: row.width - 24 * (index + 1); height: 30; radius: 14
                        y: -height + 6 * (index + 1); z: -index
                        color: Config.fg(0.07 - 0.025 * index); border.width: 1; border.color: Config.fg(0.12 - 0.04 * index) } } }
            NotifCard { id: h
                y: groupHead.visible ? 28 : 0
                readonly property var idx: history.index(row.index, 0)
                readonly property bool job: row.model.type === NotificationManager.Notifications.JobType
                width: row.width; compact: true
                appName: row.model.applicationName || ""; appIcon: row.model.applicationIconName || ""
                summary: row.model.summary || ""; body: row.model.body || ""; picture: row.model.image || row.model.iconName || ""
                actionNames: row.model.actionNames || []; actionLabels: row.model.actionLabels || []
                hasDefaultAction: !row.stacked && (row.model.hasDefaultAction || false)
                critical: row.model.urgency === NotificationManager.Notifications.CriticalUrgency
                low: row.model.urgency === NotificationManager.Notifications.LowUrgency
                isJob: job; jobPercent: row.model.percentage || 0
                jobBusy: job && center.jobUnknown(row.model); jobInfo: job ? center.jobLine(row.model) : ""
                age: { center.tick; return center.ago(row.model.updated || row.model.created) }
                onCloseClicked: history.close(h.idx)
                onDefaultInvoked: history.invokeDefaultAction(h.idx, NotificationManager.Notifications.Close)
                onActionInvoked: name => history.invokeAction(h.idx, name, NotificationManager.Notifications.Close) }
            // a closed stack opens on a click anywhere on it (its own default action would be a surprise here)
            TapHandler { enabled: row.stacked; onTapped: center.toggleGroup(row.app) } } }
    Column { visible: list.count === 0; anchors.horizontalCenter: parent.horizontalCenter; y: 64; spacing: 8
        Kirigami.Icon { anchors.horizontalCenter: parent.horizontalCenter; width: 26; height: 26; source: "notifications-symbolic"; isMask: true; color: Config.fgSolid; opacity: 0.35; roundToIconSize: false }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No notifications"; color: Config.inkDim; font.pixelSize: 13 } }
    Text { visible: list.count > 0 && center.shownCount === 0; x: 20; y: center.listY + 12; text: "Nothing matches"; color: Config.inkDim; font.pixelSize: 13 }
}
