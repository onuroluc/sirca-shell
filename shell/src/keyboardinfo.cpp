#include "keyboardinfo.h"
#include <KModifierKeyInfo>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusServiceWatcher>

namespace {
const QString kService = QStringLiteral("org.kde.keyboard");
const QString kPath = QStringLiteral("/Layouts");
const QString kIface = QStringLiteral("org.kde.KeyboardLayouts");
}

KeyboardInfo::KeyboardInfo(QObject *parent) : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.connect(kService, kPath, kIface, QStringLiteral("layoutChanged"), this, SLOT(onLayoutChanged(uint)));
    bus.connect(kService, kPath, kIface, QStringLiteral("layoutListChanged"), this, SLOT(onLayoutListChanged()));
    // KWin owns org.kde.keyboard; after a compositor restart the list is read again
    auto *w = new QDBusServiceWatcher(kService, bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(w, &QDBusServiceWatcher::serviceOwnerChanged, this, [this] { refreshLayouts(); });
    refreshLayouts();
    m_keys = new KModifierKeyInfo(this);
    connect(m_keys, &KModifierKeyInfo::keyLocked, this, [this](Qt::Key, bool) { refreshLocks(); });
    connect(m_keys, &KModifierKeyInfo::keyAdded, this, [this](Qt::Key) { refreshLocks(); });
    connect(m_keys, &KModifierKeyInfo::keyRemoved, this, [this](Qt::Key) { refreshLocks(); });
    refreshLocks();
}

void KeyboardInfo::refreshLayouts()
{
    m_layouts.clear();
    QDBusMessage m = QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("getLayoutsList"));
    const QDBusMessage reply = QDBusConnection::sessionBus().call(m, QDBus::Block, 500);   // KWin answers at once; a hung compositor is not our problem to wait for
    if (reply.type() != QDBusMessage::ErrorMessage && !reply.arguments().isEmpty() && reply.arguments().first().userType() == qMetaTypeId<QDBusArgument>()) {
        const QDBusArgument a = reply.arguments().first().value<QDBusArgument>();
        a.beginArray();
        while (!a.atEnd()) { Layout l; a.beginStructure(); a >> l.shortName >> l.displayName >> l.longName; a.endStructure(); m_layouts << l; }
        a.endArray();
    }
    QDBusMessage g = QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("getLayout"));
    const QDBusMessage r2 = QDBusConnection::sessionBus().call(g, QDBus::Block, 500);
    m_index = (r2.type() != QDBusMessage::ErrorMessage && !r2.arguments().isEmpty()) ? int(r2.arguments().first().toUInt()) : 0;
    Q_EMIT layoutsChanged();
}

void KeyboardInfo::refreshLocks()
{
    // the compositor announces the keys it knows through keyAdded; before that (or without org_kde_kwin_keystate) nothing is shown
    m_locksKnown = m_keys->knowsKey(Qt::Key_CapsLock) || m_keys->knowsKey(Qt::Key_NumLock);
    m_caps = m_keys->isKeyLocked(Qt::Key_CapsLock);
    m_num = m_keys->isKeyLocked(Qt::Key_NumLock);
    Q_EMIT locksChanged();
}

void KeyboardInfo::onLayoutChanged(uint index) { m_index = int(index); Q_EMIT layoutsChanged(); }
void KeyboardInfo::onLayoutListChanged() { refreshLayouts(); }

QString KeyboardInfo::layoutShort() const
{
    if (m_index < 0 || m_index >= m_layouts.size()) return {};
    // KWin's display name is what the user chose to show ("us", or a custom label); the short name is the xkb layout
    const Layout &l = m_layouts.at(m_index);
    return l.displayName.isEmpty() ? l.shortName : l.displayName;
}

QString KeyboardInfo::layoutName() const
{
    if (m_index < 0 || m_index >= m_layouts.size()) return {};
    return m_layouts.at(m_index).longName;
}

QVariantList KeyboardInfo::layouts() const
{
    QVariantList out;
    for (const Layout &l : m_layouts) out << QVariantMap{{QStringLiteral("short"), l.shortName}, {QStringLiteral("display"), l.displayName}, {QStringLiteral("name"), l.longName}};
    return out;
}

void KeyboardInfo::nextLayout()
{
    QDBusConnection::sessionBus().call(QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("switchToNextLayout")), QDBus::NoBlock);
}

void KeyboardInfo::setLayout(int index)
{
    QDBusMessage m = QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("setLayout"));
    m.setArguments({uint(index)});
    QDBusConnection::sessionBus().call(m, QDBus::NoBlock);
}
