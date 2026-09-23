#include "shortcutsmodel.h"
#include <KGlobalShortcutInfo>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusMetaType>
#include <QKeySequence>
#include <algorithm>

static const QString kOurComponent = QStringLiteral("sirca-shell");

ShortcutsModel::ShortcutsModel(QObject *parent) : QAbstractListModel(parent)
{
    qDBusRegisterMetaType<KGlobalShortcutInfo>();
    qDBusRegisterMetaType<QList<KGlobalShortcutInfo>>();
}

QHash<int, QByteArray> ShortcutsModel::roleNames() const
{
    return {{ComponentRole, "component"}, {ComponentIdRole, "componentId"}, {NameRole, "name"}, {KeysRole, "keys"}, {KeyListRole, "keyList"}};
}

QVariant ShortcutsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size()) return {};
    const Row &r = m_rows.at(index.row());
    switch (role) {
    case ComponentRole: return r.component;
    case ComponentIdRole: return r.componentId;
    case NameRole: return r.name;
    case KeysRole: return r.keys;
    case KeyListRole: return r.keyList;
    }
    return {};
}

void ShortcutsModel::refresh()
{
    if (m_pending > 0) return;                                   // one round trip at a time; the next refresh waits for this one
    m_incoming.clear();
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/kglobalaccel"), QStringLiteral("org.kde.KGlobalAccel"), QStringLiteral("allComponents"));
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(m), this);
    m_pending = 1; Q_EMIT loadingChanged();
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QList<QDBusObjectPath>> reply = *w;
        const QList<QDBusObjectPath> paths = reply.isError() ? QList<QDBusObjectPath>{} : reply.value();
        m_pending += paths.size();
        for (const QDBusObjectPath &p : paths) {
            QDBusMessage c = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), p.path(), QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("allShortcutInfos"));
            auto *cw = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(c), this);
            const QString path = p.path();
            connect(cw, &QDBusPendingCallWatcher::finished, this, [this, path](QDBusPendingCallWatcher *cw) {
                cw->deleteLater();
                QDBusPendingReply<QList<KGlobalShortcutInfo>> r = *cw;
                componentAnswered(path, r.isError() ? QVariant() : QVariant::fromValue(r.value()));
            });
        }
        if (--m_pending == 0) finish();
    });
}

void ShortcutsModel::componentAnswered(const QString &path, const QVariant &reply)
{
    const QList<KGlobalShortcutInfo> infos = reply.value<QList<KGlobalShortcutInfo>>();
    for (const KGlobalShortcutInfo &i : infos) {
        QStringList keys;
        for (const QKeySequence &k : i.keys()) { const QString s = k.toString(QKeySequence::NativeText); if (!s.isEmpty()) keys << s; }
        if (keys.isEmpty()) continue;                            // an action without a key is not a shortcut to learn
        // the component's unique name is the object path's last segment when the info does not carry one
        QString cid = i.componentUniqueName(); if (cid.isEmpty()) cid = path.section(QLatin1Char('/'), -1);
        QString comp = i.componentFriendlyName(); if (comp.isEmpty()) comp = cid;
        QString name = i.friendlyName(); if (name.isEmpty()) name = i.uniqueName();
        m_incoming.append({comp, cid, name, keys.join(QStringLiteral("  /  ")), keys});
    }
    if (--m_pending == 0) finish();
}

bool ShortcutsModel::before(const Row &a, const Row &b)
{
    const bool ao = a.componentId == kOurComponent, bo = b.componentId == kOurComponent;
    if (ao != bo) return ao;                                     // the shell's group first
    const int c = a.component.compare(b.component, Qt::CaseInsensitive);
    if (c != 0) return c < 0;
    return a.name.compare(b.name, Qt::CaseInsensitive) < 0;
}

void ShortcutsModel::finish()
{
    std::sort(m_incoming.begin(), m_incoming.end(), before);
    m_all = m_incoming; m_incoming.clear();
    refilter();
    Q_EMIT loadingChanged();
}

void ShortcutsModel::setFilter(const QString &f)
{
    if (f == m_filter) return;
    m_filter = f; Q_EMIT filterChanged();
    refilter();
}

void ShortcutsModel::refilter()
{
    const QStringList words = m_filter.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    beginResetModel();
    m_rows.clear();
    for (const Row &r : m_all) {
        bool ok = true;
        for (const QString &w : words) if (!r.name.contains(w, Qt::CaseInsensitive) && !r.keys.contains(w, Qt::CaseInsensitive) && !r.component.contains(w, Qt::CaseInsensitive)) { ok = false; break; }
        if (ok) m_rows.append(r);
    }
    endResetModel();
    Q_EMIT countChanged();
}
