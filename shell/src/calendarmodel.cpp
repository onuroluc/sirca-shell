#include "calendarmodel.h"
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QTimeZone>
#include <algorithm>

CalendarModel::CalendarModel(QObject *parent) : QObject(parent)
{
    m_reloadLater.setSingleShot(true);
    m_reloadLater.setInterval(300);                        // a sync writes several files in a burst: one reload for all of them
    connect(&m_reloadLater, &QTimer::timeout, this, &CalendarModel::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &CalendarModel::scheduleReload);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &CalendarModel::scheduleReload);
    // a safety net for what the watcher cannot see (a folder created later, an editor that renames over the file)
    m_rescan.setInterval(10 * 60 * 1000);
    connect(&m_rescan, &QTimer::timeout, this, &CalendarModel::reload);
    m_rescan.start();
}

static QString expandHome(const QString &p)
{
    return p.startsWith(QLatin1String("~/")) || p == QLatin1String("~") ? QDir::homePath() + p.mid(1) : p;
}

QStringList CalendarModel::defaultDirs() const
{
    const QString home = QDir::homePath();
    QStringList out{home + QStringLiteral("/.local/share/sirca-shell/calendars")};
    // khal and vdirsyncer keep one .ics per event in collection folders; these are their usual places
    for (const QString &d : {home + QStringLiteral("/.local/share/khal/calendars"), home + QStringLiteral("/.local/share/vdirsyncer"),
                             home + QStringLiteral("/.calendars"), home + QStringLiteral("/.local/share/calendars")})
        if (QDir(d).exists()) out << d;
    return out;
}

void CalendarModel::setDirs(const QStringList &dirs)
{
    if (dirs == m_dirs) return;
    m_dirs = dirs;
    Q_EMIT dirsChanged();
    reload();
}

void CalendarModel::scheduleReload() { m_reloadLater.start(); }

void CalendarModel::reload()
{
    QList<Event> events;
    QSet<QString> watch;
    int files = 0;
    for (const QString &raw : std::as_const(m_dirs)) {
        const QString dir = expandHome(raw);
        if (!QDir(dir).exists()) continue;
        watch.insert(dir);
        QDirIterator it(dir, {QStringLiteral("*.ics")}, QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories | QDirIterator::FollowSymlinks);
        while (it.hasNext()) {
            const QString p = it.next();
            if (it.fileInfo().isDir()) { watch.insert(p); continue; }
            if (++files > 5000) break;                     // a runaway folder must not stall the shell
            parseFile(p, events, watch);
        }
    }
    // an override instance (RECURRENCE-ID) replaces that one occurrence of its master
    QHash<QString, QList<QDateTime>> overrides;
    for (const Event &e : std::as_const(events)) if (e.recurrenceId.isValid()) overrides[e.uid] << e.recurrenceId;
    for (Event &e : events) if (!e.recurrenceId.isValid() && !e.freq.isEmpty() && overrides.contains(e.uid))
        for (const QDateTime &r : overrides.value(e.uid)) e.exdates << r.toTimeZone(e.start.timeZone()).date();
    m_events = events;
    m_fileCount = files;
    const QStringList old = m_watcher.files() + m_watcher.directories();
    if (!old.isEmpty()) m_watcher.removePaths(old);
    if (!watch.isEmpty()) m_watcher.addPaths(QStringList(watch.begin(), watch.end()));
    ++m_revision;
    Q_EMIT changed();
}

QString CalendarModel::unescape(const QString &s)
{
    QString out; out.reserve(s.size());
    for (int i = 0; i < s.size(); ++i) {
        const QChar c = s.at(i);
        if (c != QLatin1Char('\\') || i + 1 >= s.size()) { out += c; continue; }
        const QChar n = s.at(++i);
        if (n == QLatin1Char('n') || n == QLatin1Char('N')) out += QLatin1Char('\n'); else out += n;
    }
    return out;
}

// 20260923 (a date), 20260923T140000 (floating = local), 20260923T120000Z (UTC), or with a TZID parameter
QDateTime CalendarModel::parseStamp(const QString &value, const QString &tzid, bool &allDay)
{
    const QString v = value.trimmed();
    if (v.size() == 8) {
        allDay = true;
        return QDateTime(QDate::fromString(v, QStringLiteral("yyyyMMdd")), QTime(0, 0));
    }
    allDay = false;
    const bool utc = v.endsWith(QLatin1Char('Z'));
    const QString core = utc ? v.chopped(1) : v;
    const QDate d = QDate::fromString(core.left(8), QStringLiteral("yyyyMMdd"));
    const QTime t = QTime::fromString(core.mid(9, 6).leftJustified(6, QLatin1Char('0')), QStringLiteral("HHmmss"));
    if (!d.isValid()) return {};
    // kept in its own zone: a rule repeats at the same wall-clock time THERE, across DST changes; occurrences() converts
    if (utc) return QDateTime(d, t, QTimeZone::UTC);
    if (!tzid.isEmpty()) {
        const QTimeZone tz(tzid.toUtf8());
        if (tz.isValid()) return QDateTime(d, t, tz);
    }
    return QDateTime(d, t);
}

// PnDTnHnMnS (weeks as PnW)
static qint64 durationSeconds(const QString &s)
{
    static const QRegularExpression re(QStringLiteral("^([+-])?P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?$"));
    const auto m = re.match(s.trimmed());
    if (!m.hasMatch()) return 0;
    const qint64 secs = m.captured(2).toLongLong() * 7 * 86400 + m.captured(3).toLongLong() * 86400 + m.captured(4).toLongLong() * 3600 + m.captured(5).toLongLong() * 60 + m.captured(6).toLongLong();
    return m.captured(1) == QLatin1String("-") ? -secs : secs;
}

void CalendarModel::parseFile(const QString &path, QList<Event> &out, QSet<QString> &watch) const
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return;
    watch.insert(path);
    // unfold: a line that starts with a space or a tab continues the previous one
    const QStringList raw = QString::fromUtf8(f.readAll()).split(QRegularExpression(QStringLiteral("\r?\n")));
    QStringList lines;
    for (const QString &l : raw) {
        if (l.isEmpty()) continue;
        if ((l.at(0) == QLatin1Char(' ') || l.at(0) == QLatin1Char('\t')) && !lines.isEmpty()) lines.last() += l.mid(1); else lines << l;
    }
    // a colour for the whole file: RFC 7986 COLOR / Apple's X- property on the VCALENDAR, or vdirsyncer's `color` file beside it
    QString fileColor;
    { QFile c(QFileInfo(path).dir().filePath(QStringLiteral("color"))); if (c.open(QIODevice::ReadOnly)) fileColor = QString::fromUtf8(c.readAll()).trimmed(); }
    static const QRegularExpression hexColor(QStringLiteral("^#[0-9a-fA-F]{6}"));
    bool inEvent = false;
    Event ev;
    for (const QString &line : std::as_const(lines)) {
        // NAME;PARAM=VALUE;…:value — the first ':' outside quotes separates the two
        int colon = -1; bool quoted = false;
        for (int i = 0; i < line.size(); ++i) { const QChar c = line.at(i); if (c == QLatin1Char('"')) quoted = !quoted; else if (c == QLatin1Char(':') && !quoted) { colon = i; break; } }
        if (colon < 0) continue;
        const QString head = line.left(colon), value = line.mid(colon + 1);
        const QStringList parts = head.split(QLatin1Char(';'));
        const QString name = parts.first().toUpper();
        QString tzid, valueType;
        for (int i = 1; i < parts.size(); ++i) {
            const QString p = parts.at(i);
            if (p.startsWith(QLatin1String("TZID="), Qt::CaseInsensitive)) tzid = p.mid(5).remove(QLatin1Char('"'));
            else if (p.startsWith(QLatin1String("VALUE="), Qt::CaseInsensitive)) valueType = p.mid(6).toUpper();
        }
        if (!inEvent) {
            if (name == QLatin1String("BEGIN") && value.trimmed().toUpper() == QLatin1String("VEVENT")) { inEvent = true; ev = Event(); ev.color = fileColor; }
            else if ((name == QLatin1String("COLOR") || name == QLatin1String("X-APPLE-CALENDAR-COLOR")) && hexColor.match(value.trimmed()).hasMatch()) fileColor = value.trimmed().left(7);
            continue;
        }
        if (name == QLatin1String("END") && value.trimmed().toUpper() == QLatin1String("VEVENT")) {
            inEvent = false;
            if (!ev.start.isValid()) continue;
            if (!ev.end.isValid()) ev.end = ev.allDay ? ev.start.addDays(1) : ev.start;
            if (ev.end < ev.start) ev.end = ev.start;
            out << ev;
            continue;
        }
        bool allDay = false;
        if (name == QLatin1String("SUMMARY")) ev.summary = unescape(value).simplified();
        else if (name == QLatin1String("LOCATION")) ev.location = unescape(value).simplified();
        else if (name == QLatin1String("UID")) ev.uid = value.trimmed();
        else if (name == QLatin1String("DTSTART")) { ev.start = parseStamp(value, tzid, allDay); ev.allDay = allDay || valueType == QLatin1String("DATE"); }
        else if (name == QLatin1String("DTEND")) ev.end = parseStamp(value, tzid, allDay);
        else if (name == QLatin1String("DURATION") && !ev.end.isValid() && ev.start.isValid()) ev.end = ev.start.addSecs(durationSeconds(value));
        else if (name == QLatin1String("RECURRENCE-ID")) ev.recurrenceId = parseStamp(value, tzid, allDay);
        else if (name == QLatin1String("EXDATE")) { for (const QString &d : value.split(QLatin1Char(','))) { const QDateTime x = parseStamp(d, tzid, allDay); if (x.isValid()) ev.exdates << x.date(); } }
        else if (name == QLatin1String("COLOR") && hexColor.match(value.trimmed()).hasMatch()) ev.color = value.trimmed().left(7);
        else if (name == QLatin1String("RRULE")) {
            static const QHash<QString, int> days{{QStringLiteral("MO"), 1}, {QStringLiteral("TU"), 2}, {QStringLiteral("WE"), 3}, {QStringLiteral("TH"), 4}, {QStringLiteral("FR"), 5}, {QStringLiteral("SA"), 6}, {QStringLiteral("SU"), 7}};
            bool simple = true;
            for (const QString &kv : value.split(QLatin1Char(';'))) {
                const QString k = kv.section(QLatin1Char('='), 0, 0).toUpper(), v = kv.section(QLatin1Char('='), 1);
                if (k == QLatin1String("FREQ")) ev.freq = v.toUpper();
                else if (k == QLatin1String("INTERVAL")) ev.interval = qMax(1, v.toInt());
                else if (k == QLatin1String("COUNT")) ev.count = v.toInt();
                else if (k == QLatin1String("UNTIL")) ev.until = parseStamp(v, tzid, allDay);
                else if (k == QLatin1String("BYDAY")) { for (const QString &d : v.split(QLatin1Char(','))) { const int n = days.value(d.right(2).toUpper(), 0); if (n && d.size() == 2) ev.byDay << n; else simple = false; } }   // "1MO" (the first Monday) is beyond us
                else if (k == QLatin1String("WKST")) {}
                else simple = false;                                                                        // BYMONTHDAY, BYSETPOS, … : shown once, on its start
            }
            if (ev.freq != QLatin1String("DAILY") && ev.freq != QLatin1String("WEEKLY") && ev.freq != QLatin1String("MONTHLY") && ev.freq != QLatin1String("YEARLY")) simple = false;
            if (!ev.byDay.isEmpty() && ev.freq != QLatin1String("WEEKLY")) simple = false;
            if (!simple) { ev.freq.clear(); ev.byDay.clear(); }
        }
    }
}

QVariantList CalendarModel::occurrences(const QDate &from, const QDate &to) const
{
    struct Occ { QDateTime start, end; const Event *e; };
    QList<Occ> found;
    const QDateTime winStart(from, QTime(0, 0)), winEnd(to.addDays(1), QTime(0, 0));
    const auto touches = [&](const QDateTime &s, const QDateTime &e) { return s < winEnd && (e > winStart || (e == s && s >= winStart)); };
    for (const Event &e : m_events) {
        const qint64 len = e.start.secsTo(e.end);
        if (e.freq.isEmpty()) { if (touches(e.start, e.end)) found.append({e.start, e.end, &e}); continue; }
        // walk the rule from its start; DAILY / plain WEEKLY jump straight to the window, the others are cheap enough to step
        QDateTime cur = e.start;
        int emitted = 0, steps = 0;
        const bool byDay = e.freq == QLatin1String("WEEKLY") && !e.byDay.isEmpty();
        if ((e.freq == QLatin1String("DAILY") || (e.freq == QLatin1String("WEEKLY") && !byDay)) && cur < winStart) {
            const qint64 stepDays = e.freq == QLatin1String("DAILY") ? e.interval : 7 * e.interval;
            const qint64 n = qMax<qint64>(0, (cur.date().daysTo(from) - qMax<qint64>(0, len / 86400) - 1) / stepDays);
            cur = cur.addDays(n * stepDays); emitted = int(n);
        }
        const QDate weekBase = e.start.date().addDays(-(e.start.date().dayOfWeek() - 1));   // the Monday of the first week, for INTERVAL on BYDAY rules
        while (++steps < 20000) {
            if (e.count > 0 && emitted >= e.count) break;
            if (e.until.isValid() && cur > e.until) break;
            if (cur >= winEnd) break;
            bool ok = true;
            if (byDay) { const QDate d = cur.date(); ok = e.byDay.contains(d.dayOfWeek()) && ((weekBase.daysTo(d) / 7) % e.interval == 0) && d >= e.start.date(); }
            if (ok) {
                ++emitted;                                              // COUNT counts the rule's instances, exceptions included
                const QDateTime end = cur.addSecs(len);
                if (!e.exdates.contains(cur.date()) && touches(cur, end)) found.append({cur, end, &e});
            }
            if (byDay) cur = cur.addDays(1);
            else if (e.freq == QLatin1String("DAILY")) cur = cur.addDays(e.interval);
            else if (e.freq == QLatin1String("WEEKLY")) cur = cur.addDays(7 * e.interval);
            else if (e.freq == QLatin1String("MONTHLY")) cur = cur.addMonths(e.interval);
            else cur = cur.addYears(e.interval);
        }
    }
    std::sort(found.begin(), found.end(), [](const Occ &a, const Occ &b) { return a.start != b.start ? a.start < b.start : a.e->summary < b.e->summary; });
    QVariantList out;
    for (const Occ &o : std::as_const(found)) {
        // a timed event that ends on the stroke of midnight belongs to the day before
        const QDateTime start = o.e->allDay ? o.start : o.start.toLocalTime(), end = o.e->allDay ? o.end : o.end.toLocalTime();
        QDate last = end.date();
        if (end > start && end.time() == QTime(0, 0)) last = last.addDays(-1);
        if (last < start.date()) last = start.date();
        out << QVariantMap{{QStringLiteral("summary"), o.e->summary.isEmpty() ? QStringLiteral("(untitled)") : o.e->summary}, {QStringLiteral("location"), o.e->location},
                           {QStringLiteral("start"), start}, {QStringLiteral("end"), end}, {QStringLiteral("allDay"), o.e->allDay},
                           {QStringLiteral("firstDay"), start.date().toString(Qt::ISODate)}, {QStringLiteral("lastDay"), last.toString(Qt::ISODate)},
                           {QStringLiteral("color"), o.e->color}};
    }
    return out;
}
