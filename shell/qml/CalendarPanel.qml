// The popup behind the clock, native: a large live clock with the date, and a month calendar. Click the month title to
// zoom out to months, again to years; arrows and the mouse wheel page through; "Today" jumps back. The first day of the
// week and all names come from the system locale. No Plasma applet, no data source: dates are computed here.
import QtQuick
import org.kde.kirigami as Kirigami
import SircaShell

Item {
    id: cal
    property bool open: false
    implicitWidth: 348
    implicitHeight: col.implicitHeight + 12
    readonly property var loc: Qt.locale()
    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: cal.open; triggeredOnStart: true; onTriggered: cal.now = new Date() }
    property int viewYear: now.getFullYear()
    property int viewMonth: now.getMonth()             // 0..11
    property date selected: new Date()
    property string zoom: "days"                        // "days" | "months" | "years"
    onOpenChanged: if (open) { const d = new Date(); now = d; viewYear = d.getFullYear(); viewMonth = d.getMonth(); selected = d; zoom = "days" }
    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }
    function page(step) {
        if (zoom === "days") { const m = viewMonth + step; viewYear += Math.floor(m / 12); viewMonth = ((m % 12) + 12) % 12 }
        else if (zoom === "months") viewYear += step; else viewYear += 12 * step }
    // 42 cells starting at the locale's first weekday on or before the 1st
    readonly property var cells: { const first = new Date(viewYear, viewMonth, 1); const shift = (first.getDay() - loc.firstDayOfWeek + 7) % 7; const out = [];
        for (let i = 0; i < 42; ++i) out.push(new Date(viewYear, viewMonth, 1 - shift + i)); return out }
    function isoWeek(d) { const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())); const n = t.getUTCDay() || 7; t.setUTCDate(t.getUTCDate() + 4 - n);
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1)); return Math.ceil(((t - y0) / 86400000 + 1) / 7) }

    // ---- events, from .ics files on disk (CalendarModel; config calendarDirs, default: our folder plus khal / vdirsyncer
    // stores that exist). Dots on the days of the grid, the picked day's list under it, and the next one up by the clock.
    CalendarModel { id: events; dirs: Config.get("calendarDirs", events.defaultDirs()) }
    function iso(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0") }
    readonly property var gridEvents: { events.revision; return cal.cells.length ? events.occurrences(cal.cells[0], cal.cells[41]) : [] }
    readonly property var dayMarks: { const m = {}                                   // "yyyy-MM-dd" -> [colour, …], a multi-day event marks every day it spans
        for (const o of gridEvents) { const d = new Date(o.firstDay + "T00:00:00"); for (let i = 0; i < 62; ++i) { const k = iso(d); (m[k] = m[k] || []).push(o.color); if (k >= o.lastDay) break; d.setDate(d.getDate() + 1) } } return m }
    readonly property var dayEvents: { events.revision; return events.occurrences(cal.selected, cal.selected) }
    readonly property int minuteTick: Math.floor(now.getTime() / 60000)              // the "next" line moves on the minute, not with the seconds
    readonly property var nextEvent: { events.revision; minuteTick; const t = new Date(); const list = events.occurrences(t, new Date(t.getTime() + 30 * 86400000))
        for (const o of list) if (o.end > t) return o; return null }
    function timeOf(o) { return o.allDay ? "all day" : o.start.toLocaleTimeString(loc, Locale.ShortFormat).replace(/\s?[AP]M$/i, m => m.trim().toLowerCase()) }
    function whenOf(o) {                                                               // "Now · until 15:00", "in 40 min", "14:00", "Tomorrow 09:30", "Fri 18:00", "3 Oct"
        const t = new Date(); if (o.start <= t) return "Now · until " + (o.allDay ? "tomorrow" : o.end.toLocaleTimeString(loc, Locale.ShortFormat))
        const mins = Math.round((o.start - t) / 60000); if (!o.allDay && mins < 90) return "in " + mins + " min"
        const days = Math.round((new Date(o.firstDay + "T00:00:00") - new Date(t.getFullYear(), t.getMonth(), t.getDate())) / 86400000)
        const tm = o.allDay ? "" : " " + timeOf(o)
        return days === 0 ? timeOf(o) : days === 1 ? "Tomorrow" + tm : days < 7 ? loc.dayName(o.start.getDay(), Locale.ShortFormat) + tm : o.start.toLocaleDateString(loc, "d MMM") + tm }

    component RoundBtn: Item { id: rb; property string icon; signal tapped()
        width: 30; height: 30
        Rectangle { anchors.fill: parent; radius: 15; color: Config.fg(rt.pressed ? 0.20 : (rbh.hovered ? 0.12 : 0.055)); border.width: 1; border.color: Config.fg(rbh.hovered ? 0.18 : 0.09)
            Behavior on color { ColorAnimation { duration: Config.quick } } }
        Kirigami.Icon { anchors.centerIn: parent; width: 13; height: 13; source: rb.icon; isMask: true; color: Config.fgSolid; opacity: 0.9; roundToIconSize: false }
        HoverHandler { id: rbh } TapHandler { id: rt; onTapped: rb.tapped() } }

    Column { id: col; x: 6; y: 6; width: parent.width - 12; spacing: 10
        // ---- clock ----
        Column { width: parent.width; spacing: 0
            Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                readonly property string shortTime: cal.now.toLocaleTimeString(cal.loc, Locale.ShortFormat)
                readonly property var ampm: shortTime.match(/[AP]M$/i)
                Text { id: big; color: Config.ink; font.pixelSize: 44; font.weight: Font.Light; font.letterSpacing: -1; font.features: { "tnum": 1 }
                    text: parent.shortTime.replace(/\s?[AP]M$/i, "") + ":" + String(cal.now.getSeconds()).padStart(2, "0") }
                Text { visible: !!parent.ampm; anchors.baseline: big.baseline; color: Config.inkDim; font.pixelSize: 16; font.weight: Font.Medium; text: parent.ampm ? parent.ampm[0] : "" } }
            Text { anchors.horizontalCenter: parent.horizontalCenter; color: Config.inkDim; font.pixelSize: 13; text: cal.now.toLocaleDateString(cal.loc, "dddd, d MMMM yyyy") }
            // the next event (or the one running now): a small pill under the date
            Item { width: parent.width; height: cal.nextEvent ? 30 : 0; visible: !!cal.nextEvent; clip: true
                Rectangle { anchors.centerIn: parent; anchors.verticalCenterOffset: 3; height: 24; width: Math.min(parent.width - 12, nextRow.implicitWidth + 22); radius: 12; color: Config.fg(0.07); border.width: 1; border.color: Config.fg(0.08)
                    Row { id: nextRow; anchors.centerIn: parent; spacing: 7
                        Rectangle { width: 7; height: 7; radius: 3.5; anchors.verticalCenter: parent.verticalCenter; color: cal.nextEvent && cal.nextEvent.color !== "" ? cal.nextEvent.color : Config.accent }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium; elide: Text.ElideRight; width: Math.min(implicitWidth, 190); text: cal.nextEvent ? cal.nextEvent.summary : "" }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: Config.inkDim; font.pixelSize: 12; font.features: { "tnum": 1 }; text: cal.nextEvent ? cal.whenOf(cal.nextEvent) : "" } } } } }
        Rectangle { width: parent.width - 12; x: 6; height: 1; color: Config.fg(0.08) }

        // ---- weather (opt-in, Open-Meteo through the Weather singleton): now, today's range, the next six hours. Without a
        // location the card only says so; with weather off it is not there at all.
        Connections { target: Config; function onUserChanged() { wcard.configure() } }
        Item { id: wcard; width: parent.width; visible: Weather.enabled; height: visible ? (Weather.ready ? 108 : 30) : 0
            function configure() { const c = Object.assign({}, Config.user || {}); c.weather = Config.weatherOn; Weather.configure(c) }   // placing the bar widget is the opt-in too
            Component.onCompleted: configure()
            Text { visible: !Weather.ready; x: 8; height: 30; verticalAlignment: Text.AlignVCenter; color: Config.inkDim; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width - 16
                text: Weather.status === "no-location" ? "Weather: no location yet — Sirca Settings › Behaviour › Weather" : Weather.status === "error" ? "Weather: " + Weather.error : "Weather: fetching…" }
            Item { visible: Weather.ready; anchors.fill: parent
                Kirigami.Icon { id: wIcon; x: 8; y: 4; width: 44; height: 44; source: Weather.iconFor(Weather.code, Weather.isDay); roundToIconSize: false }
                Text { id: wTemp; anchors.left: wIcon.right; anchors.leftMargin: 10; y: 0; color: Config.ink; font.pixelSize: 34; font.weight: Font.Light; font.letterSpacing: -1; font.features: { "tnum": 1 }; text: Math.round(Weather.temperature) + "°" }
                Column { anchors.left: wTemp.right; anchors.leftMargin: 10; y: 8; spacing: 1
                    Text { color: Config.ink; font.pixelSize: 13; font.weight: Font.Medium; text: Weather.describe(Weather.code) }
                    Text { color: Config.inkDim; font.pixelSize: 11; font.features: { "tnum": 1 }; text: "H " + Math.round(Weather.todayMax) + "°  L " + Math.round(Weather.todayMin) + "°" + (Math.abs(Weather.feelsLike - Weather.temperature) >= 2 ? "  ·  feels " + Math.round(Weather.feelsLike) + "°" : "") } }
                Text { anchors.right: parent.right; anchors.rightMargin: 8; y: 8; color: Config.inkDim; font.pixelSize: 11; elide: Text.ElideRight; width: 90; horizontalAlignment: Text.AlignRight; text: Weather.locationName }
                // the next six hours
                Row { x: 8; y: 56; width: parent.width - 16; spacing: 0
                    Repeater { model: Weather.hourly.slice(0, 6)
                        Column { required property var modelData; width: parent.width / 6; spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; color: Config.inkDim; font.pixelSize: 10; font.features: { "tnum": 1 }; text: modelData.time.toLocaleTimeString(cal.loc, "HH") + "h" }
                            Kirigami.Icon { anchors.horizontalCenter: parent.horizontalCenter; width: 18; height: 18; source: Weather.iconFor(modelData.code, modelData.isDay); roundToIconSize: false }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; color: Config.ink; font.pixelSize: 11; font.features: { "tnum": 1 }; text: Math.round(modelData.temp) + "°" } } } } } }
        Rectangle { visible: Weather.enabled; width: parent.width - 12; x: 6; height: visible ? 1 : 0; color: Config.fg(0.08) }

        // ---- header: title (zooms out), today, arrows ----
        Item { width: parent.width; height: 32
            Rectangle { id: titlePill; height: 30; width: title.implicitWidth + 22; radius: 15; anchors.verticalCenter: parent.verticalCenter
                color: Config.fg(th.hovered ? 0.10 : 0); Behavior on color { ColorAnimation { duration: Config.quick } }
                Text { id: title; anchors.centerIn: parent; color: Config.ink; font.pixelSize: 15; font.weight: Font.DemiBold
                    text: cal.zoom === "days" ? cal.loc.standaloneMonthName(cal.viewMonth) + " " + cal.viewYear : cal.zoom === "months" ? String(cal.viewYear) : (cal.viewYear - cal.viewYear % 12) + " – " + (cal.viewYear - cal.viewYear % 12 + 11) }
                HoverHandler { id: th } TapHandler { onTapped: cal.zoom = cal.zoom === "days" ? "months" : "years" } }
            Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                Rectangle { height: 30; width: tl.implicitWidth + 22; radius: 15; anchors.verticalCenter: parent.verticalCenter
                    color: Config.fg(tdh.hovered ? 0.12 : 0.055); border.width: 1; border.color: Config.fg(0.09)
                    Text { id: tl; anchors.centerIn: parent; text: "Today"; color: Config.ink; font.pixelSize: 12; font.weight: Font.Medium }
                    HoverHandler { id: tdh } TapHandler { onTapped: { const d = new Date(); cal.viewYear = d.getFullYear(); cal.viewMonth = d.getMonth(); cal.selected = d; cal.zoom = "days" } } }
                RoundBtn { icon: "go-previous-symbolic"; onTapped: cal.page(-1) }
                RoundBtn { icon: "go-next-symbolic"; onTapped: cal.page(1) } } }

        // ---- the views share one box, so the popup never changes size between them ----
        Item { id: views; width: parent.width; height: 22 + 6 * 40
            WheelHandler { onWheel: e => cal.page(e.angleDelta.y > 0 ? -1 : 1) }
            // days
            Item { anchors.fill: parent; opacity: cal.zoom === "days" ? 1 : 0; visible: opacity > 0.01; scale: cal.zoom === "days" ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: 160 } } Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Row { id: names; width: parent.width; height: 22
                    Repeater { model: 7
                        Text { required property int index; width: names.width / 7; horizontalAlignment: Text.AlignHCenter; color: Config.inkDim; font.pixelSize: 11; font.weight: Font.Medium; font.capitalization: Font.AllUppercase
                            text: cal.loc.standaloneDayName((cal.loc.firstDayOfWeek + index) % 7, Locale.ShortFormat) } } }
                Grid { y: 22; width: parent.width; columns: 7
                    Repeater { model: cal.cells
                        Item { id: cell; required property var modelData
                            readonly property bool inMonth: modelData.getMonth() === cal.viewMonth
                            readonly property bool today: cal.sameDay(modelData, cal.now)
                            readonly property bool picked: cal.sameDay(modelData, cal.selected) && !today
                            width: views.width / 7; height: 40
                            Rectangle { anchors.centerIn: parent; width: 34; height: 34; radius: 17
                                color: cell.today ? Config.onFill : Config.fg(dh.hovered ? 0.10 : 0)
                                border.width: cell.picked ? 1 : 0; border.color: Config.fg(0.45)
                                Behavior on color { ColorAnimation { duration: Config.quick } } }
                            readonly property var marks: cal.dayMarks[cal.iso(modelData)] || []
                            Text { anchors.centerIn: parent; anchors.verticalCenterOffset: cell.marks.length ? -2 : 0; text: cell.modelData.getDate(); font.pixelSize: 13; font.weight: cell.today ? Font.DemiBold : Font.Normal; font.features: { "tnum": 1 }
                                color: cell.today ? Config.onFg : Config.ink
                                opacity: cell.today ? 1 : (!cell.inMonth ? 0.28 : ((cell.modelData.getDay() === 0 || cell.modelData.getDay() === 6) ? 0.62 : 1)) }
                            // up to three dots for the day's events, in their calendar's colour (on today's disc: the disc's text colour)
                            Row { anchors.horizontalCenter: parent.horizontalCenter; y: 29; spacing: 2; opacity: cell.inMonth || cell.today ? 1 : 0.4
                                Repeater { model: Math.min(3, cell.marks.length)
                                    Rectangle { required property int index; width: 4; height: 4; radius: 2; color: cell.today ? Config.onFg : (cell.marks[index] !== "" ? cell.marks[index] : Config.fgSolid) } } }
                            HoverHandler { id: dh }
                            TapHandler { onTapped: { cal.selected = cell.modelData; if (!cell.inMonth) { cal.viewYear = cell.modelData.getFullYear(); cal.viewMonth = cell.modelData.getMonth() } } } } } } }
            // months and years: 4 x 3 pills
            Repeater { model: ["months", "years"]
                Grid { id: big; required property string modelData; anchors.fill: parent; columns: 3
                    opacity: cal.zoom === modelData ? 1 : 0; visible: opacity > 0.01; scale: cal.zoom === modelData ? 1 : 1.06
                    Behavior on opacity { NumberAnimation { duration: 160 } } Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Repeater { model: 12
                        Item { id: bc; required property int index; width: views.width / 3; height: views.height / 4
                            readonly property int year: cal.viewYear - cal.viewYear % 12 + index
                            readonly property bool current: big.modelData === "months" ? (index === cal.now.getMonth() && cal.viewYear === cal.now.getFullYear()) : year === cal.now.getFullYear()
                            Rectangle { anchors.centerIn: parent; width: parent.width - 12; height: 40; radius: 20
                                color: bc.current ? Config.fg(0.16) : Config.fg(bh.hovered ? 0.10 : 0); border.width: 1; border.color: Config.fg(bc.current ? 0.24 : 0)
                                Behavior on color { ColorAnimation { duration: Config.quick } } }
                            Text { anchors.centerIn: parent; color: Config.ink; font.pixelSize: 13; font.weight: bc.current ? Font.DemiBold : Font.Normal
                                text: big.modelData === "months" ? cal.loc.standaloneMonthName(bc.index, Locale.ShortFormat) : String(bc.year) }
                            HoverHandler { id: bh }
                            TapHandler { onTapped: { if (big.modelData === "months") { cal.viewMonth = bc.index; cal.zoom = "days" } else { cal.viewYear = bc.year; cal.zoom = "months" } } } } } } } }

        // ---- the picked day ----
        Rectangle { width: parent.width - 12; x: 6; height: 1; color: Config.fg(0.08) }
        Item { width: parent.width; height: 22
            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; color: Config.ink; font.pixelSize: 13; text: cal.selected.toLocaleDateString(cal.loc, "dddd, d MMMM") }
            Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; color: Config.inkDim; font.pixelSize: 12; text: "Week " + cal.isoWeek(cal.selected) } }
        // the picked day's events: time, title, place; at most five, the rest as a count. Nothing at all while no calendar
        // has any events (most set-ups): the popup stays the plain clock and calendar it was.
        Column { width: parent.width; spacing: 2; visible: events.eventCount > 0
            Text { visible: cal.dayEvents.length === 0; x: 8; height: 22; verticalAlignment: Text.AlignVCenter; color: Config.inkDim; opacity: 0.7; font.pixelSize: 12; text: "No events" }
            Repeater { model: cal.dayEvents.slice(0, 5)
                Item { id: ev; required property var modelData; width: parent.width; height: 24
                    Rectangle { anchors.fill: parent; radius: 8; color: Config.fg(evh.hovered ? 0.07 : 0); Behavior on color { ColorAnimation { duration: Config.quick } } }
                    Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 3.5; color: ev.modelData.color !== "" ? ev.modelData.color : Config.accent }
                    Text { id: evTime; x: 22; width: 58; anchors.verticalCenter: parent.verticalCenter; color: Config.inkDim; font.pixelSize: 12; font.features: { "tnum": 1 }; text: cal.timeOf(ev.modelData) }
                    Text { x: 84; width: parent.width - 92; anchors.verticalCenter: parent.verticalCenter; color: Config.ink; font.pixelSize: 13; elide: Text.ElideRight
                        text: ev.modelData.summary + (ev.modelData.location !== "" ? "  <font color=\"" + Config.hex(Config.inkDim) + "\">" + ev.modelData.location.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font>" : ""); textFormat: Text.StyledText }
                    HoverHandler { id: evh } } }
            Text { visible: cal.dayEvents.length > 5; x: 22; height: 20; verticalAlignment: Text.AlignVCenter; color: Config.inkDim; font.pixelSize: 12; text: "+ " + (cal.dayEvents.length - 5) + " more" } }
    }
}
