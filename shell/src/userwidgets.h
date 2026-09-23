// User widgets: every folder under ~/.config/<app>/widgets/<name>/ that holds a Widget.qml and / or a widget.json is a
// widget the bar can show as "user:<name>" (see qml/UserWidget.qml for what the QML side gets). `UserWidgets` is the
// list (a singleton, watches the folder: dropping a widget in shows it in the edit-mode shelf without a restart);
// `ExecRunner` is the engine of the built-in "Exec" widget type: a command every N seconds, its first stdout line as
// text, another command on click. widget.json keys: label, icon, exec, interval (s), click, qml (a file name other
// than Widget.qml).
#pragma once
#include <QAbstractListModel>
#include <QFileSystemWatcher>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>
#include <qqml.h>

class UserWidgets : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QStringList names READ names NOTIFY changed)       // sorted; "user:" + name is the bar widget kind
    Q_PROPERTY(QString folder READ folder CONSTANT)
public:
    enum Roles { NameRole = Qt::UserRole + 1, LabelRole, DirRole, QmlRole, ExecRole, IntervalRole, IconRole, ClickRole };
    explicit UserWidgets(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    QStringList names() const;
    QString folder() const { return m_folder; }
    // {name, label, dir, qml (absolute path or ""), exec, interval, icon, click}; empty when there is no such widget
    Q_INVOKABLE QVariantMap info(const QString &name) const;
    Q_INVOKABLE QString label(const QString &name) const;      // the widget.json label, else the folder name
    Q_INVOKABLE void rescan();
Q_SIGNALS:
    void changed();
private:
    struct Entry { QString name, label, dir, qml, exec, icon, click; int interval = 5; };
    QList<Entry> scan() const;
    void watch();
    QString m_folder;
    QList<Entry> m_entries;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};

class ExecRunner : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString command READ command WRITE setCommand NOTIFY commandChanged)
    Q_PROPERTY(QString workingDirectory READ workingDirectory WRITE setWorkingDirectory NOTIFY workingDirectoryChanged)   // also put first on PATH: "script.sh" finds the widget's own file
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)          // seconds; 0 = once
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)             // the host switches it off while the widget is hidden
    Q_PROPERTY(QString text READ text NOTIFY textChanged)                                    // first line of the last stdout, trimmed
    Q_PROPERTY(QString output READ output NOTIFY textChanged)                                // the whole stdout
    Q_PROPERTY(bool failed READ failed NOTIFY textChanged)                                   // non-zero exit or could not start
public:
    explicit ExecRunner(QObject *parent = nullptr);
    QString command() const { return m_command; }
    void setCommand(const QString &c);
    QString workingDirectory() const { return m_dir; }
    void setWorkingDirectory(const QString &d);
    int interval() const { return m_interval; }
    void setInterval(int s);
    bool running() const { return m_running; }
    void setRunning(bool on);
    QString text() const { return m_text; }
    QString output() const { return m_output; }
    bool failed() const { return m_failed; }
    Q_INVOKABLE void refresh();                          // run the command now
    Q_INVOKABLE void run(const QString &command);        // fire and forget (the click command), same directory and PATH
Q_SIGNALS:
    void commandChanged();
    void workingDirectoryChanged();
    void intervalChanged();
    void runningChanged();
    void textChanged();
private:
    QProcessEnvironment environment() const;
    void schedule();
    QString m_command, m_dir, m_text, m_output;
    int m_interval = 5;
    bool m_running = false, m_failed = false;
    QProcess *m_process = nullptr;
    QTimer m_timer;
};
