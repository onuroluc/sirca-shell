#include "userwidgets.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

// ---- the list ---------------------------------------------------------------------------------------------------------
UserWidgets::UserWidgets(QObject *parent) : QAbstractListModel(parent)
{
    // ConfigLocation + the application name, not a literal "sirca-shell": the public build is named differently
    m_folder = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QLatin1Char('/') + QCoreApplication::applicationName() + QStringLiteral("/widgets");
    m_entries = scan();
    // a burst of file events (an editor's save, a folder copied in) becomes one rescan
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(300);
    connect(&m_debounce, &QTimer::timeout, this, &UserWidgets::rescan);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_debounce, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_debounce, qOverload<>(&QTimer::start));
    watch();
}

void UserWidgets::watch()
{
    // the widgets folder may not exist yet: watch its parent (the config folder) for it to appear, then the folder and
    // every widget in it (a Widget.qml edit or a new widget.json is a change too)
    const QStringList old = m_watcher.directories() + m_watcher.files();
    if (!old.isEmpty()) m_watcher.removePaths(old);
    QStringList paths;
    const QString parent = QFileInfo(m_folder).path();
    if (QDir(parent).exists()) paths << parent;
    if (QDir(m_folder).exists()) paths << m_folder;
    for (const Entry &e : std::as_const(m_entries)) { paths << e.dir; for (const QString &f : {e.qml, e.dir + QStringLiteral("/widget.json")}) if (!f.isEmpty() && QFileInfo::exists(f)) paths << f; }
    paths.removeDuplicates();
    if (!paths.isEmpty()) m_watcher.addPaths(paths);
}

QList<UserWidgets::Entry> UserWidgets::scan() const
{
    QList<Entry> out;
    const QDir root(m_folder);
    if (!root.exists()) return out;
    const QStringList dirs = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &name : dirs) {
        Entry e;
        e.name = name; e.label = name; e.dir = root.filePath(name);
        QString qmlName = QStringLiteral("Widget.qml");
        QFile meta(e.dir + QStringLiteral("/widget.json"));
        if (meta.open(QIODevice::ReadOnly)) {
            const QJsonObject o = QJsonDocument::fromJson(meta.readAll()).object();
            if (o.contains(QStringLiteral("label"))) e.label = o.value(QStringLiteral("label")).toString(name);
            e.exec = o.value(QStringLiteral("exec")).toString();
            e.icon = o.value(QStringLiteral("icon")).toString();
            e.click = o.value(QStringLiteral("click")).toString();
            e.interval = std::max(0, o.value(QStringLiteral("interval")).toInt(5));
            qmlName = o.value(QStringLiteral("qml")).toString(qmlName);
        }
        if (QFileInfo::exists(e.dir + QLatin1Char('/') + qmlName)) e.qml = e.dir + QLatin1Char('/') + qmlName;
        if (e.qml.isEmpty() && e.exec.isEmpty()) continue;     // a folder with neither is not a widget (a README, a data folder)
        out << e;
    }
    return out;
}

void UserWidgets::rescan()
{
    const QList<Entry> fresh = scan();
    bool same = fresh.size() == m_entries.size();
    for (int i = 0; same && i < fresh.size(); ++i) {
        const Entry &a = fresh[i], &b = m_entries[i];
        same = a.name == b.name && a.label == b.label && a.qml == b.qml && a.exec == b.exec && a.icon == b.icon && a.click == b.click && a.interval == b.interval;
    }
    if (!same) {
        beginResetModel();
        m_entries = fresh;
        endResetModel();
        Q_EMIT changed();
    }
    watch();   // even when nothing changed: an editor that saves by rename drops the file from the watcher
}

int UserWidgets::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : m_entries.size(); }

QVariant UserWidgets::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_entries.size()) return {};
    const Entry &e = m_entries.at(index.row());
    switch (role) {
    case NameRole: case Qt::DisplayRole: return e.name;
    case LabelRole: return e.label;
    case DirRole: return e.dir;
    case QmlRole: return e.qml;
    case ExecRole: return e.exec;
    case IntervalRole: return e.interval;
    case IconRole: return e.icon;
    case ClickRole: return e.click;
    }
    return {};
}

QHash<int, QByteArray> UserWidgets::roleNames() const
{
    return { {NameRole, "name"}, {LabelRole, "label"}, {DirRole, "dir"}, {QmlRole, "qml"}, {ExecRole, "exec"}, {IntervalRole, "interval"}, {IconRole, "icon"}, {ClickRole, "click"} };
}

QStringList UserWidgets::names() const
{
    QStringList n;
    for (const Entry &e : m_entries) n << e.name;
    return n;
}

QVariantMap UserWidgets::info(const QString &name) const
{
    for (const Entry &e : m_entries) {
        if (e.name != name) continue;
        return { {QStringLiteral("name"), e.name}, {QStringLiteral("label"), e.label}, {QStringLiteral("dir"), e.dir}, {QStringLiteral("qml"), e.qml},
                 {QStringLiteral("exec"), e.exec}, {QStringLiteral("interval"), e.interval}, {QStringLiteral("icon"), e.icon}, {QStringLiteral("click"), e.click} };
    }
    return {};
}

QString UserWidgets::label(const QString &name) const
{
    for (const Entry &e : m_entries) if (e.name == name) return e.label;
    return name;
}

// ---- the Exec widget's engine -----------------------------------------------------------------------------------------
ExecRunner::ExecRunner(QObject *parent) : QObject(parent)
{
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, &ExecRunner::refresh);
}

QProcessEnvironment ExecRunner::environment() const
{
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    if (!m_dir.isEmpty()) env.insert(QStringLiteral("PATH"), m_dir + QLatin1Char(':') + env.value(QStringLiteral("PATH")));
    return env;
}

void ExecRunner::setCommand(const QString &c) { if (c == m_command) return; m_command = c; Q_EMIT commandChanged(); if (m_running) refresh(); }
void ExecRunner::setWorkingDirectory(const QString &d) { if (d == m_dir) return; m_dir = d; Q_EMIT workingDirectoryChanged(); }
void ExecRunner::setInterval(int s) { s = std::max(0, s); if (s == m_interval) return; m_interval = s; Q_EMIT intervalChanged(); if (m_running) schedule(); }

void ExecRunner::setRunning(bool on)
{
    if (on == m_running) return;
    m_running = on;
    Q_EMIT runningChanged();
    if (on) refresh(); else m_timer.stop();
}

void ExecRunner::schedule()
{
    m_timer.stop();
    if (m_running && m_interval > 0) m_timer.start(m_interval * 1000);   // the next run is timed from the END of this one: a slow script never piles up
}

void ExecRunner::refresh()
{
    if (m_command.trimmed().isEmpty() || m_process) return;   // still running: this tick is skipped, the finish schedules the next
    m_process = new QProcess(this);
    m_process->setProcessEnvironment(environment());
    if (!m_dir.isEmpty()) m_process->setWorkingDirectory(m_dir);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    connect(m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus st) {
        m_output = QString::fromUtf8(m_process->readAllStandardOutput());
        m_text = m_output.section(QLatin1Char('\n'), 0, 0).trimmed();
        m_failed = st != QProcess::NormalExit || code != 0;
        m_process->deleteLater(); m_process = nullptr;
        Q_EMIT textChanged();
        schedule();
    });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        m_text.clear(); m_output.clear(); m_failed = true;
        m_process->deleteLater(); m_process = nullptr;
        Q_EMIT textChanged();
        schedule();
    });
    m_process->start(QStringLiteral("/bin/sh"), { QStringLiteral("-c"), m_command });
}

void ExecRunner::run(const QString &command)
{
    if (command.trimmed().isEmpty()) return;
    QProcess p;
    p.setProgram(QStringLiteral("/bin/sh"));
    p.setArguments({ QStringLiteral("-c"), command });
    p.setProcessEnvironment(environment());
    if (!m_dir.isEmpty()) p.setWorkingDirectory(m_dir);
    p.startDetached();
}
