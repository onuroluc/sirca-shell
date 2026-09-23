#include "kwinsnap.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QFile>
#include <QStandardPaths>
#include <functional>

namespace {
const QString kName = QStringLiteral("sirca-shell-snap-zones");
const QString kSvc = QStringLiteral("org.kde.KWin"), kPath = QStringLiteral("/Scripting"), kIface = QStringLiteral("org.kde.kwin.Scripting");
QDBusMessage scripting(const QString &method, const QVariantList &args = {})
{
    QDBusMessage m = QDBusMessage::createMethodCall(kSvc, kPath, kIface, method);
    m.setArguments(args);
    return m;
}
}

KwinSnap::KwinSnap(QObject *parent) : QObject(parent)
{
    // the shell's service name is registered by the Shell singleton; this object rides on the same connection
    QDBusConnection::sessionBus().registerObject(QStringLiteral("/SnapZones"), this, QDBusConnection::ExportScriptableSlots);
}

void KwinSnap::setEnabled(bool on)
{
    if (on == m_enabled) return;
    m_enabled = on;
    Q_EMIT enabledChanged();
    if (on) reload(); else unload([this] { setLoaded(false); });
}

void KwinSnap::setLoaded(bool on) { if (on == m_loaded) return; m_loaded = on; Q_EMIT loadedChanged(); }

// Everything is asynchronous (like Shell::raiseWallpaper): KWin answers scripting calls slowly while it is busy, and a
// blocking call here would stall the shell for the whole wait.
void KwinSnap::unload(std::function<void()> then)
{
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(scripting(QStringLiteral("unloadScript"), {kName}), 1000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [w, then = std::move(then)](QDBusPendingCallWatcher *) { w->deleteLater(); if (then) then(); });
}

void KwinSnap::reload()
{
    // always unload first: KWin keeps a loaded script until it is unloaded by name, and a fresh build carries a fresh one
    unload([this] { if (m_enabled) load(); });
}

void KwinSnap::load()
{
    // KWin loads scripts from files: the resource is copied to the runtime folder first
    const QString path = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/sirca-shell-snap-zones.js");
    QFile src(QStringLiteral(":/qt/qml/SircaShell/scripts/kwin-snap-zones.js"));
    QFile dst(path);
    if (!src.open(QIODevice::ReadOnly) || !dst.open(QIODevice::WriteOnly | QIODevice::Truncate)) { qWarning("sirca-shell: snap zones: cannot write %s", qPrintable(path)); return; }
    dst.write(src.readAll());
    dst.close();
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(scripting(QStringLiteral("loadScript"), {path, kName}), 1000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w](QDBusPendingCallWatcher *) {
        w->deleteLater();
        const QDBusPendingReply<int> id = *w;
        if (!id.isValid() || id.value() < 0) { qWarning("sirca-shell: snap zones: KWin did not load the script"); setLoaded(false); return; }
        QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(kSvc, QStringLiteral("/Scripting/Script") + QString::number(id.value()), QStringLiteral("org.kde.kwin.Script"), QStringLiteral("run")), 1000);
        setLoaded(true);
    });
}
