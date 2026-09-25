// The popup stack: notifications as glass cards in the bar's card lobe. Native: NotificationManager's model directly,
// no Plasma applet. Same rules as Plasma's own popups (urgency, Do Not Disturb with its allow-list, per-app blocking from
// System Settings > Notifications); we run the timeout ourselves so hovering a card pauses it.
import QtQuick
import org.kde.notificationmanager as NotificationManager
import SircaShell

Item {
    id: cards
    // job details for the cards: "12.4 MB of 80 MB  ·  3.1 MB/s"; a running job that reports no percentage has no known size
    function bytes(n) { n = Number(n) || 0; const u = ["B", "KB", "MB", "GB", "TB"]; let i = 0; while (n >= 1000 && i < u.length - 1) { n /= 1000; ++i } return (i === 0 ? n : n.toFixed(n < 10 ? 2 : 1)) + " " + u[i] }
    function jobLine(m) { const d = m.jobDetails; if (!d) return ""; const done = Number(d.processedBytes) || 0, total = Number(d.totalBytes) || 0, speed = Number(d.speed) || 0
        let s = done > 0 ? (total > 0 ? bytes(done) + " of " + bytes(total) : bytes(done)) : ""; if (speed > 0) s += (s ? "  ·  " : "") + bytes(speed) + "/s"; return s }
    function jobUnknown(m) { const d = m.jobDetails; return m.jobState === NotificationManager.Notifications.JobStateRunning && !(m.percentage > 0) && !(d && Number(d.totalBytes) > 0) }
    readonly property int count: rep.count
    // how many cards have their reply field open: only then does the bar need the keyboard (see TopBar.restingKeyboardMode)
    property int replyingCount: 0
    // A game or a full-screen video has focus: no popups (on this machine a popup over a running game can even trigger the
    // GPU driver's hang). Critical ones still come through; everything else goes to the history unseen, the bell shows it.
    property bool muted: false
    readonly property bool dbg: Config.user && Config.user.debugFocus === true
    onMutedChanged: if (dbg) console.log("NOTIF muted", muted)
    onCountChanged: if (dbg) console.log("NOTIF cards", count)
    readonly property bool anyReplying: { for (let i = 0; i < rep.count; ++i) { const c = rep.itemAt(i); if (c && c.replying) return true } return false }
    width: 364 ; height: col.height
    NotificationManager.Settings { id: settings }
    readonly property bool inhibited: settings.notificationsInhibitedByApplication
        || (settings.notificationsInhibitedUntil instanceof Date && !isNaN(settings.notificationsInhibitedUntil.getTime()) && Date.now() < settings.notificationsInhibitedUntil.getTime())
    NotificationManager.Notifications { id: popups
        limit: 5
        showExpired: false; showDismissed: false; showAddedDuringInhibition: false
        blacklistedDesktopEntries: settings.popupBlacklistedApplications
        blacklistedNotifyRcNames: settings.popupBlacklistedServices
        whitelistedDesktopEntries: cards.inhibited ? settings.doNotDisturbPopupWhitelistedApplications : []
        whitelistedNotifyRcNames: cards.inhibited ? settings.doNotDisturbPopupWhitelistedServices : []
        showJobs: settings.jobsInNotifications
        sortMode: NotificationManager.Notifications.SortByTypeAndUrgency; sortOrder: Qt.AscendingOrder
        groupMode: NotificationManager.Notifications.GroupDisabled
        urgencies: { let u = 0;
            if (!cards.inhibited || settings.criticalPopupsInDoNotDisturbMode) u |= NotificationManager.Notifications.CriticalUrgency;
            if (!cards.inhibited && !cards.muted) u |= NotificationManager.Notifications.NormalUrgency;
            if (!cards.inhibited && !cards.muted && settings.lowPriorityPopups) u |= NotificationManager.Notifications.LowUrgency;
            return u } }

    Column { id: col; width: parent.width; spacing: 8
        move: Transition { NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic } }
        Repeater { id: rep; model: popups
            delegate: NotifCard { id: c
                required property int index
                required property var model
                onReplyingChanged: cards.replyingCount += replying ? 1 : -1
                Component.onDestruction: if (replying) cards.replyingCount--
                readonly property var idx: popups.index(index, 0)
                readonly property bool job: model.type === NotificationManager.Notifications.JobType
                appName: model.applicationName || ""; appIcon: model.applicationIconName || ""
                summary: model.summary || ""; body: job ? (model.body || "") : (model.body || "")
                picture: model.image || model.iconName || ""
                actionNames: model.actionNames || []; actionLabels: model.actionLabels || []
                hasDefaultAction: model.hasDefaultAction || false
                critical: model.urgency === NotificationManager.Notifications.CriticalUrgency
                low: model.urgency === NotificationManager.Notifications.LowUrgency
                canReply: model.hasReplyAction || false; replyPlaceholder: model.replyPlaceholderText || ""
                // a job that stopped without an error is done whatever its last percentage said (a download that finished at
                // once never reported 100 and showed "Done" next to an empty bar, 2026-09-24)
                isJob: job; jobPercent: (job && model.jobState === NotificationManager.Notifications.JobStateStopped && !(model.jobDetails && model.jobDetails.error)) ? 100 : (model.percentage || 0)
                jobBusy: job && cards.jobUnknown(model); jobInfo: job ? cards.jobLine(model) : ""
                jobNote: job && model.jobState === NotificationManager.Notifications.JobStateStopped ? "Done" : (job && model.jobState === NotificationManager.Notifications.JobStateSuspended ? "Paused" : "")
                // our own timeout: -1 = the user's default, 0 = stays; jobs stay while they run, and so does a critical one
                // (the spec leaves it to the server: a critical popup that vanished unseen would be the one that mattered)
                readonly property int lifeMs: job || critical ? 0 : (model.timeout === -1 ? settings.popupTimeout : model.timeout)
                property real remain: 1
                timeLeft: lifeMs > 0 ? remain : -1              // (the card rounds the line to whole pixels; see NotifCard)
                NumberAnimation on remain { id: life; from: 1; to: 0; duration: Math.max(1, c.lifeMs); running: c.lifeMs > 0; paused: running && (c.hovered || c.replying)
                    onFinished: { const keep = model.resident || ((c.actionNames.length > 0 || c.hasDefaultAction) && !model.transient);
                        if (keep) model.expired = true; else popups.expire(c.idx) } }        // actionable ones stay usable in the history
                onHoveredChanged: if (hovered) model.read = true
                onCloseClicked: popups.close(c.idx)
                onDefaultInvoked: { popups.invokeDefaultAction(c.idx, NotificationManager.Notifications.Close) }
                onActionInvoked: name => popups.invokeAction(c.idx, name, NotificationManager.Notifications.Close)
                onReplied: text => popups.reply(c.idx, text, NotificationManager.Notifications.Close)
                opacity: 0; scale: 0.96
                Component.onCompleted: { popups.stopTimeout(c.idx); if (popups.playSoundHint) popups.playSoundHint(c.idx); appear.start() }
                ParallelAnimation { id: appear
                    NumberAnimation { target: c; property: "opacity"; to: 1; duration: 180 }
                    NumberAnimation { target: c; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 0.9 } } } } }
}
