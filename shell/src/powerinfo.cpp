#include "powerinfo.h"
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>

namespace {
// GetAll on the system bus, blocking for at most half a second: a stuck daemon must not hold the shell (the shell reads
// these once at start and after that only on signals)
QVariantMap getAll(const QString &service, const QString &path, const QString &iface)
{
    QDBusMessage m = QDBusMessage::createMethodCall(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
    m.setArguments({iface});
    const QDBusMessage reply = QDBusConnection::systemBus().call(m, QDBus::Block, 500);
    if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) return {};
    const QVariant first = reply.arguments().first();
    if (first.userType() == qMetaTypeId<QDBusArgument>()) { QVariantMap out; first.value<QDBusArgument>() >> out; return out; }
    return first.toMap();
}
bool serviceUp(const QString &service)
{
    const QDBusConnectionInterface *bus = QDBusConnection::systemBus().interface();
    return bus && bus->isServiceRegistered(service);
}
const QString kUPower = QStringLiteral("org.freedesktop.UPower");
const QString kDisplayDevice = QStringLiteral("/org/freedesktop/UPower/devices/DisplayDevice");
const QString kDeviceIface = QStringLiteral("org.freedesktop.UPower.Device");
const QString kProps = QStringLiteral("org.freedesktop.DBus.Properties");
const QString kPropsChanged = QStringLiteral("PropertiesChanged");
}

// ---------------------------------------------------------------- battery
BatteryInfo::BatteryInfo(QObject *parent) : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::systemBus();
    bus.connect(kUPower, kDisplayDevice, kProps, kPropsChanged, this, SLOT(onPropertiesChanged(QString,QVariantMap,QStringList)));
    bus.connect(kUPower, QStringLiteral("/org/freedesktop/UPower"), kProps, kPropsChanged, this, SLOT(onUPowerChanged(QString,QVariantMap,QStringList)));
    // UPower comes and goes (a restart, a late start at boot): re-read on both
    auto *w = new QDBusServiceWatcher(kUPower, bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(w, &QDBusServiceWatcher::serviceOwnerChanged, this, [this] { refresh(); });
    refresh();
}

void BatteryInfo::refresh()
{
    if (!serviceUp(kUPower)) { m_present = false; Q_EMIT changed(); return; }
    apply(getAll(kUPower, kDisplayDevice, kDeviceIface));
    const QVariantMap up = getAll(kUPower, QStringLiteral("/org/freedesktop/UPower"), kUPower);
    m_onBattery = up.value(QStringLiteral("OnBattery")).toBool();
    Q_EMIT changed();
}

void BatteryInfo::apply(const QVariantMap &p)
{
    // DisplayDevice type 2 = Battery; laptops without one (or desktops) show type 0 / IsPresent false
    if (p.contains(QStringLiteral("IsPresent")) || p.contains(QStringLiteral("Type"))) {
        const bool isPresent = p.value(QStringLiteral("IsPresent"), m_present).toBool();
        const uint type = p.value(QStringLiteral("Type"), 2u).toUInt();
        m_present = isPresent && type == 2;
    }
    if (p.contains(QStringLiteral("Percentage"))) m_percent = qRound(p.value(QStringLiteral("Percentage")).toDouble());
    if (p.contains(QStringLiteral("State"))) m_state = p.value(QStringLiteral("State")).toUInt();
    if (p.contains(QStringLiteral("TimeToEmpty"))) m_timeToEmpty = p.value(QStringLiteral("TimeToEmpty")).toLongLong();
    if (p.contains(QStringLiteral("TimeToFull"))) m_timeToFull = p.value(QStringLiteral("TimeToFull")).toLongLong();
    if (p.contains(QStringLiteral("IconName"))) m_icon = p.value(QStringLiteral("IconName")).toString();
}

void BatteryInfo::onPropertiesChanged(const QString &iface, const QVariantMap &props, const QStringList &invalidated)
{
    if (iface != kDeviceIface) return;
    if (!invalidated.isEmpty()) { refresh(); return; }
    apply(props); Q_EMIT changed();
}

void BatteryInfo::onUPowerChanged(const QString &iface, const QVariantMap &props, const QStringList &)
{
    if (iface != kUPower || !props.contains(QStringLiteral("OnBattery"))) return;
    m_onBattery = props.value(QStringLiteral("OnBattery")).toBool(); Q_EMIT changed();
}

// ---------------------------------------------------------------- power profiles
PowerProfiles::PowerProfiles(QObject *parent) : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::systemBus();
    // the daemon's newer name first (power-profiles-daemon >= 0.20 serves both), the old one as the fallback
    auto *w = new QDBusServiceWatcher(this);
    w->setConnection(bus); w->setWatchMode(QDBusServiceWatcher::WatchForOwnerChange);
    w->setWatchedServices({QStringLiteral("org.freedesktop.UPower.PowerProfiles"), QStringLiteral("net.hadess.PowerProfiles")});
    connect(w, &QDBusServiceWatcher::serviceOwnerChanged, this, &PowerProfiles::onOwnerChanged);
    refresh();
}

void PowerProfiles::refresh()
{
    struct Candidate { QString service, path, iface; };
    const Candidate candidates[] = {
        { QStringLiteral("org.freedesktop.UPower.PowerProfiles"), QStringLiteral("/org/freedesktop/UPower/PowerProfiles"), QStringLiteral("org.freedesktop.UPower.PowerProfiles") },
        { QStringLiteral("net.hadess.PowerProfiles"), QStringLiteral("/net/hadess/PowerProfiles"), QStringLiteral("net.hadess.PowerProfiles") } };
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!m_service.isEmpty()) bus.disconnect(m_service, m_path, kProps, kPropsChanged, this, SLOT(onPropertiesChanged(QString,QVariantMap,QStringList)));
    m_available = false; m_service.clear();
    for (const Candidate &c : candidates) {
        if (!serviceUp(c.service)) continue;
        const QVariantMap all = getAll(c.service, c.path, c.iface);
        if (all.isEmpty()) continue;
        m_service = c.service; m_path = c.path; m_iface = c.iface; m_available = true;
        apply(all);
        bus.connect(m_service, m_path, kProps, kPropsChanged, this, SLOT(onPropertiesChanged(QString,QVariantMap,QStringList)));
        break;
    }
    Q_EMIT changed();
}

void PowerProfiles::apply(const QVariantMap &p)
{
    if (p.contains(QStringLiteral("ActiveProfile"))) m_active = p.value(QStringLiteral("ActiveProfile")).toString();
    if (p.contains(QStringLiteral("PerformanceDegraded"))) m_degraded = p.value(QStringLiteral("PerformanceDegraded")).toString();
    if (p.contains(QStringLiteral("Profiles"))) {
        // aa{sv}: one dict per profile, "Profile" = its name; the daemon lists them from saver to performance
        QStringList names;
        const QVariant v = p.value(QStringLiteral("Profiles"));
        if (v.userType() == qMetaTypeId<QDBusArgument>()) {
            const QDBusArgument a = v.value<QDBusArgument>();
            a.beginArray();
            while (!a.atEnd()) { QVariantMap d; a >> d; const QString n = d.value(QStringLiteral("Profile")).toString(); if (!n.isEmpty()) names << n; }
            a.endArray();
        }
        if (!names.isEmpty()) m_profiles = names;
    }
}

void PowerProfiles::onPropertiesChanged(const QString &iface, const QVariantMap &props, const QStringList &invalidated)
{
    if (iface != m_iface) return;
    if (!invalidated.isEmpty()) { refresh(); return; }
    apply(props); Q_EMIT changed();
}

void PowerProfiles::onOwnerChanged(const QString &, const QString &, const QString &) { refresh(); }

void PowerProfiles::setActive(const QString &profile)
{
    if (!m_available || profile.isEmpty()) return;
    QDBusMessage m = QDBusMessage::createMethodCall(m_service, m_path, kProps, QStringLiteral("Set"));
    m.setArguments({m_iface, QStringLiteral("ActiveProfile"), QVariant::fromValue(QDBusVariant(profile))});
    QDBusConnection::systemBus().call(m, QDBus::NoBlock);   // the daemon answers with PropertiesChanged, which is what the tile follows
}

void PowerProfiles::cycle()
{
    if (m_profiles.isEmpty()) return;
    const int i = m_profiles.indexOf(m_active);
    setActive(m_profiles.at((i + 1) % m_profiles.size()));
}

QString PowerProfiles::label(const QString &profile) const
{
    if (profile == QLatin1String("power-saver")) return QStringLiteral("Power save");
    if (profile == QLatin1String("balanced")) return QStringLiteral("Balanced");
    if (profile == QLatin1String("performance")) return QStringLiteral("Performance");
    return profile;
}

QString PowerProfiles::icon(const QString &profile) const
{
    if (profile == QLatin1String("power-saver")) return QStringLiteral("battery-profile-powersave-symbolic");
    if (profile == QLatin1String("performance")) return QStringLiteral("battery-profile-performance-symbolic");
    return QStringLiteral("speedometer-symbolic");
}

// ---------------------------------------------------------------- idle inhibitor
IdleInhibitor::IdleInhibitor(QObject *parent) : QObject(parent) {}
IdleInhibitor::~IdleInhibitor() { release(); }

void IdleInhibitor::setInhibited(bool on)
{
    if (on == m_inhibited) return;
    m_inhibited = on;
    if (!on) { release(); Q_EMIT inhibitedChanged(); return; }
    // both blocking with a short cap: the cookie is needed to release later, and both services are local and quick
    auto take = [this](const QString &service, const QString &path, const QString &iface) -> uint {
        QDBusMessage m = QDBusMessage::createMethodCall(service, path, iface, QStringLiteral("Inhibit"));
        m.setArguments({QStringLiteral("Sirca Shell"), m_reason});
        const QDBusMessage reply = QDBusConnection::sessionBus().call(m, QDBus::Block, 500);
        if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) { qWarning("sirca-shell: caffeine: %s did not answer Inhibit", qPrintable(service)); return 0; }
        return reply.arguments().first().toUInt(); };
    m_screenCookie = take(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"), QStringLiteral("org.freedesktop.ScreenSaver"));
    m_powerCookie = take(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"), QStringLiteral("org.freedesktop.PowerManagement.Inhibit"));
    Q_EMIT inhibitedChanged();
}

void IdleInhibitor::release()
{
    auto give = [](const QString &service, const QString &path, const QString &iface, uint cookie) {
        if (!cookie) return;
        QDBusMessage m = QDBusMessage::createMethodCall(service, path, iface, QStringLiteral("UnInhibit"));
        m.setArguments({cookie});
        QDBusConnection::sessionBus().call(m, QDBus::NoBlock); };
    give(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"), QStringLiteral("org.freedesktop.ScreenSaver"), m_screenCookie);
    give(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"), QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), m_powerCookie);
    m_screenCookie = 0; m_powerCookie = 0;
}
