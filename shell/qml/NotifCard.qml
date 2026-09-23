// One notification as a glass card. Used by the popup stack (with a time-left line) and by the history list (compact,
// with its age). Everything it shows comes in as properties; what the user does goes out as signals.
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell

Item {
    id: card
    property string appName
    property var appIcon
    property string summary
    property string body
    property var picture                              // image (QImage) or icon name of the notification itself
    property var actionNames: []
    property var actionLabels: []
    property bool hasDefaultAction: false
    property bool critical: false                     // the accent edge on the left; a critical popup also stays until it is dismissed
    property bool low: false                          // low priority: the card is dimmer
    property bool canReply: false
    property string replyPlaceholder: ""
    property string age: ""                           // history only
    property real timeLeft: -1                        // 0..1, popups only; < 0 = no line
    property bool isJob: false
    property int jobPercent: 0
    property string jobNote: ""
    property bool jobBusy: false                  // running, but the total is unknown (a download without a size): a sweeping bar instead of a stuck 0 %
    property string jobInfo: ""                   // "12.4 MB of 80 MB  ·  3.1 MB/s"
    property bool compact: false
    readonly property bool hovered: hh.hovered
    signal closeClicked()
    signal defaultInvoked()
    signal actionInvoked(string name)
    signal replied(string text)
    width: 364
    height: content.implicitHeight + (compact ? 20 : 26)
    property bool replying: false

    opacity: low ? 0.72 : 1
    Rectangle { anchors.fill: parent; radius: 16
        color: Config.fg(hh.hovered ? 0.085 : 0.055); border.width: 1
        border.color: card.critical ? Qt.rgba(Config.accent.r, Config.accent.g, Config.accent.b, 0.55) : Config.fg(hh.hovered ? 0.16 : 0.09)
        Behavior on color { ColorAnimation { duration: Config.quick } } }
    // critical: a bar of the accent along the left edge, inside the rounded corners
    Rectangle { visible: card.critical; x: 6; y: 12; width: 3; height: parent.height - 24; radius: 1.5; color: Config.accent }
    HoverHandler { id: hh }
    // A tap on the close button, an action or "reply" is NOT a tap on the card. Pointer handlers all see the same tap (the
    // inner one does not swallow it), so closing a "screenshot saved" card also ran its default action and opened the folder.
    property int overControls: 0                      // how many of the card's own buttons the pointer is over
    TapHandler { enabled: card.hasDefaultAction && !card.replying && card.overControls === 0; onTapped: card.defaultInvoked() }

    Column { id: content; x: card.critical ? 18 : 14; y: card.compact ? 10 : 13; width: parent.width - (card.critical ? 32 : 28); spacing: 6
        // app line
        Item { width: parent.width; height: 16
            Kirigami.Icon { id: aIcon; width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter; source: card.appIcon || "preferences-desktop-notification"; roundToIconSize: false }
            Text { anchors.left: aIcon.right; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; anchors.right: ageText.left; anchors.rightMargin: 8; elide: Text.ElideRight
                text: card.appName; color: Config.inkDim; font.pixelSize: 11; font.weight: Font.Medium; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.5 }
            Text { id: ageText; anchors.right: closeBtn.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: card.age; color: Config.inkDim; font.pixelSize: 11; opacity: closeBtn.opacity > 0.5 ? 0 : 0.8 }
            Item { id: closeBtn; anchors.right: parent.right; anchors.rightMargin: -4; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; opacity: hh.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Config.quick } }
                Rectangle { anchors.fill: parent; radius: 10; color: Config.fg(ch.hovered ? 0.18 : 0.08) }
                Kirigami.Icon { anchors.centerIn: parent; width: 10; height: 10; source: "window-close-symbolic"; isMask: true; color: Config.fgSolid; roundToIconSize: false }
                HoverHandler { id: ch; onHoveredChanged: card.overControls += hovered ? 1 : -1 } TapHandler { onTapped: card.closeClicked() } } }
        // summary + body, picture on the right
        Item { width: parent.width; height: Math.max(texts.implicitHeight, pic.visible ? pic.height : 0)
            Column { id: texts; width: parent.width - (pic.visible ? pic.width + 12 : 0); spacing: 2
                Text { width: parent.width; text: card.summary; visible: text !== ""; color: Config.ink; font.pixelSize: 14; font.weight: Font.DemiBold; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; textFormat: Text.PlainText }
                Text { width: parent.width; text: card.body; visible: text !== ""; color: Qt.rgba(Config.ink.r, Config.ink.g, Config.ink.b, 0.84); font.pixelSize: 13; wrapMode: Text.Wrap; maximumLineCount: card.compact ? 3 : 6; elide: Text.ElideRight
                    textFormat: Text.StyledText; linkColor: Config.dark ? "#9bb4ff" : Config.tone(0.2); onLinkActivated: l => Qt.openUrlExternally(l) } }   // literal-ok: mode-aware already
            Kirigami.Icon { id: pic; anchors.right: parent.right; width: 44; height: 44; source: card.picture || ""; roundToIconSize: false
                visible: !!card.picture && card.picture !== "" && String(card.picture) !== String(card.appIcon) } }
        // job progress
        Item { visible: card.isJob; width: parent.width; height: 18
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 44; height: 4; radius: 2; color: Config.fg(0.14)
                id: jobTrack; clip: true
                Rectangle { visible: !card.jobBusy; width: parent.width * Math.max(0, Math.min(100, card.jobPercent)) / 100; height: 4; radius: 2; color: Config.fg(0.92)
                    Behavior on width { NumberAnimation { duration: 200 } } }
                Rectangle { id: sweep; visible: card.jobBusy; width: parent.width * 0.3; height: 4; radius: 2; color: Config.fg(0.85)
                    SequentialAnimation on x { running: sweep.visible && card.visible; loops: Animation.Infinite
                        NumberAnimation { from: -sweep.width; to: jobTrack.width; duration: 1300; easing.type: Easing.InOutSine } } } }
            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: card.jobNote !== "" ? card.jobNote : (card.jobBusy ? "" : card.jobPercent + "%"); color: Config.inkDim; font.pixelSize: 11; font.features: { "tnum": 1 } } }
        Text { visible: card.isJob && card.jobInfo !== ""; width: parent.width; text: card.jobInfo; color: Config.inkDim; font.pixelSize: 11; font.features: { "tnum": 1 }; elide: Text.ElideRight }
        // actions as pills; a reply field instead when replying
        Flow { visible: !card.replying && (card.actionNames.length > 0 || card.canReply); width: parent.width; spacing: 6; topPadding: 2
            Repeater { model: card.actionNames.length
                Rectangle { required property int index; height: 28; width: al.implicitWidth + 22; radius: 14
                    color: Config.fg(at.pressed ? 0.22 : (ah.hovered ? 0.15 : 0.09)); border.width: 1; border.color: Config.fg(0.14)
                    Text { id: al; anchors.centerIn: parent; text: card.actionLabels[parent.index] ?? ""; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium }
                    HoverHandler { id: ah; onHoveredChanged: card.overControls += hovered ? 1 : -1 } TapHandler { id: at; onTapped: card.actionInvoked(card.actionNames[parent.index]) } } }
            Rectangle { visible: card.canReply; height: 28; width: rl.implicitWidth + 22; radius: 14; color: Config.fg(rh.hovered ? 0.15 : 0.09); border.width: 1; border.color: Config.fg(0.14)
                Text { id: rl; anchors.centerIn: parent; text: "Reply"; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium }
                HoverHandler { id: rh; onHoveredChanged: card.overControls += hovered ? 1 : -1 } TapHandler { onTapped: { card.replying = true; replyField.forceActiveFocus() } } } }
        Rectangle { visible: card.replying; width: parent.width; height: 34; radius: 17; color: Config.fg(0.08); border.width: 1; border.color: Config.fg(replyField.activeFocus ? 0.24 : 0.12)
            Text { anchors.left: replyField.left; anchors.verticalCenter: parent.verticalCenter; visible: replyField.text === ""; text: card.replyPlaceholder !== "" ? card.replyPlaceholder : "Write a reply"; color: Config.inkDim; font.pixelSize: 13 }
            TextInput { id: replyField; anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; verticalAlignment: TextInput.AlignVCenter; color: Config.ink; font.pixelSize: 13; clip: true; selectByMouse: true
                onAccepted: if (text !== "") { card.replied(text); card.replying = false; text = "" }
                Keys.onEscapePressed: { card.replying = false; text = "" } } }
    }
    // time left, along the bottom. timeLeft moves every frame; the width is on whole pixels so the item is only dirtied (and
    // the bar surface only repainted) when the line visibly changes: once per pixel of its length rather than at 240 Hz.
    Rectangle { visible: card.timeLeft >= 0; x: 16; y: parent.height - 3; height: 2; radius: 1; width: Math.round((parent.width - 32) * Math.max(0, card.timeLeft)); color: Config.fg(0.45) }
}
