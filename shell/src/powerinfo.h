// Power, from the SYSTEM bus (Shell.dbusCall only speaks to the session bus): the battery through UPower's composite
// DisplayDevice, and the power profile through power-profiles-daemon. Both are plain QML types of the shell's own module,
// so a missing daemon degrades to `present` / `available` = false instead of a QML module failing to load.
#pragma once
#include <QObject>
#include <QStringList>
#include <QVariantMap>
#include <qqml.h>

class BatteryInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool present READ present NOTIFY changed)          // a real battery (UPower type Battery) that IsPresent
    Q_PROPERTY(int percent READ percent NOTIFY changed)
    Q_PROPERTY(bool charging READ charging NOTIFY changed)        // Charging, PendingCharge or FullyCharged (= on mains)
    Q_PROPERTY(bool full READ full NOTIFY changed)
    Q_PROPERTY(bool onBattery READ onBattery NOTIFY changed)      // UPower.OnBattery: the machine runs on the battery right now
    Q_PROPERTY(qint64 timeToEmpty READ timeToEmpty NOTIFY changed)   // seconds, 0 = unknown
    Q_PROPERTY(qint64 timeToFull READ timeToFull NOTIFY changed)
    Q_PROPERTY(QString iconName READ iconName NOTIFY changed)     // UPower's own battery-level-…-symbolic name
public:
    explicit BatteryInfo(QObject *parent = nullptr);
    bool present() const { return m_present; }
    int percent() const { return m_percent; }
    bool charging() const { return m_state == 1 || m_state == 4 || m_state == 5; }
    bool full() const { return m_state == 4; }
    bool onBattery() const { return m_onBattery; }
    qint64 timeToEmpty() const { return m_timeToEmpty; }
    qint64 timeToFull() const { return m_timeToFull; }
    QString iconName() const { return m_icon; }
Q_SIGNALS:
    void changed();
private Q_SLOTS:
    void onPropertiesChanged(const QString &iface, const QVariantMap &props, const QStringList &invalidated);
    void onUPowerChanged(const QString &iface, const QVariantMap &props, const QStringList &invalidated);
private:
    void refresh();
    void apply(const QVariantMap &props);
    bool m_present = false, m_onBattery = false;
    int m_percent = 0;
    uint m_state = 0;   // UPower: 1 charging, 2 discharging, 3 empty, 4 fully charged, 5 pending charge, 6 pending discharge
    qint64 m_timeToEmpty = 0, m_timeToFull = 0;
    QString m_icon;
};

class PowerProfiles : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool available READ available NOTIFY changed)      // a daemon answered (org.freedesktop.UPower.PowerProfiles, else net.hadess.PowerProfiles)
    Q_PROPERTY(QString active READ active NOTIFY changed)         // "power-saver" | "balanced" | "performance"
    Q_PROPERTY(QStringList profiles READ profiles NOTIFY changed) // what the daemon offers, in its order (saver … performance)
    Q_PROPERTY(QString degraded READ degraded NOTIFY changed)     // PerformanceDegraded reason, "" when fine
public:
    explicit PowerProfiles(QObject *parent = nullptr);
    bool available() const { return m_available; }
    QString active() const { return m_active; }
    QStringList profiles() const { return m_profiles; }
    QString degraded() const { return m_degraded; }
    Q_INVOKABLE void setActive(const QString &profile);
    Q_INVOKABLE void cycle();                                      // saver -> balanced -> performance -> saver
    Q_INVOKABLE QString label(const QString &profile) const;      // "Power save", "Balanced", "Performance"
    Q_INVOKABLE QString icon(const QString &profile) const;
Q_SIGNALS:
    void changed();
private Q_SLOTS:
    void onPropertiesChanged(const QString &iface, const QVariantMap &props, const QStringList &invalidated);
    void onOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
private:
    void refresh();
    void apply(const QVariantMap &props);
    bool m_available = false;
    QString m_service, m_path, m_iface;
    QString m_active, m_degraded;
    QStringList m_profiles;
};

// One "keep awake" hold: a cookie each on org.freedesktop.ScreenSaver (KWin: no locking, no screen off) and
// org.freedesktop.PowerManagement.Inhibit (PowerDevil: no sleep). The cookies are unsigned on the wire, which is why this
// is not done from QML with Shell.dbusCall (a number through JS comes back as a double and UnInhibit rejects it).
class IdleInhibitor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool inhibited READ inhibited WRITE setInhibited NOTIFY inhibitedChanged)
    Q_PROPERTY(QString reason READ reason WRITE setReason NOTIFY reasonChanged)
public:
    explicit IdleInhibitor(QObject *parent = nullptr);
    ~IdleInhibitor() override;
    bool inhibited() const { return m_inhibited; }
    void setInhibited(bool on);
    QString reason() const { return m_reason; }
    void setReason(const QString &r) { if (r == m_reason) return; m_reason = r; Q_EMIT reasonChanged(); }
Q_SIGNALS:
    void inhibitedChanged();
    void reasonChanged();
private:
    void release();
    bool m_inhibited = false;
    QString m_reason = QStringLiteral("Kept awake from the bar");
    uint m_screenCookie = 0, m_powerCookie = 0;
};
