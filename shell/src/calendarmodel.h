// Calendar events for the clock popup, read from .ics files on disk (no network, no PIM daemon): a folder of our own
// (~/.local/share/sirca-shell/calendars) plus khal / vdirsyncer collections when they exist. Every VEVENT's DTSTART, DTEND
// (or DURATION), SUMMARY, LOCATION and RRULE are read; recurrence covers the everyday cases (DAILY, WEEKLY with BYDAY,
// MONTHLY on the same day, YEARLY, with INTERVAL / COUNT / UNTIL, EXDATE and RECURRENCE-ID overrides). Anything else
// counts as a single event. The files are watched: an edit or a sync shows up in the popup without a restart.
#pragma once
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <qqml.h>

class CalendarModel : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QStringList dirs READ dirs WRITE setDirs NOTIFY dirsChanged)      // "~" allowed; folders are read recursively
    Q_PROPERTY(int revision READ revision NOTIFY changed)                        // bumps on every reload: bindings that call occurrences() depend on it
    Q_PROPERTY(int eventCount READ eventCount NOTIFY changed)
    Q_PROPERTY(int fileCount READ fileCount NOTIFY changed)
public:
    explicit CalendarModel(QObject *parent = nullptr);
    QStringList dirs() const { return m_dirs; }
    void setDirs(const QStringList &dirs);
    int revision() const { return m_revision; }
    int eventCount() const { return m_events.size(); }
    int fileCount() const { return m_fileCount; }
    Q_INVOKABLE QStringList defaultDirs() const;        // our folder, and every known calendar store that exists on this machine
    // every occurrence that touches [from, to] (dates inclusive), sorted by start:
    // { summary, location, start, end, allDay, firstDay "yyyy-MM-dd", lastDay "yyyy-MM-dd", color "#rrggbb" | "" }
    Q_INVOKABLE QVariantList occurrences(const QDate &from, const QDate &to) const;
    Q_INVOKABLE void reload();
Q_SIGNALS:
    void dirsChanged();
    void changed();
private:
    struct Event {
        QString uid, summary, location, color;
        QDateTime start, end;
        bool allDay = false;
        QString freq;                 // "" = single, else DAILY | WEEKLY | MONTHLY | YEARLY
        int interval = 1, count = 0;  // count 0 = unlimited
        QDateTime until;
        QList<int> byDay;             // Qt day numbers (1 = Monday … 7 = Sunday), WEEKLY only
        QList<QDate> exdates;
        QDateTime recurrenceId;       // set on an override instance of a recurring event
    };
    void scheduleReload();
    void parseFile(const QString &path, QList<Event> &out, QSet<QString> &watch) const;
    static QDateTime parseStamp(const QString &value, const QString &tzid, bool &allDay);
    static QString unescape(const QString &s);
    QStringList m_dirs;
    QList<Event> m_events;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadLater, m_rescan;
    int m_revision = 0, m_fileCount = 0;
};
