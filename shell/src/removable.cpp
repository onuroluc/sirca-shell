#include "removable.h"
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDir>
#include <QMetaType>
#include <QTimer>

static const QString kService = QStringLiteral("org.freedesktop.UDisks2");
static const QString kRoot = QStringLiteral("/org/freedesktop/UDisks2");
static const QString kBlock = QStringLiteral("org.freedesktop.UDisks2.Block");
static const QString kFilesystem = QStringLiteral("org.freedesktop.UDisks2.Filesystem");
static const QString kDrive = QStringLiteral("org.freedesktop.UDisks2.Drive");

// a{sv} values arrive as QDBusArgument inside the QVariantMap; unwrap the ones we read (MountPoints is aay: a list of byte strings)
static QVariant unwrap(const QVariant &v)
{
    if (v.userType() != qMetaTypeId<QDBusArgument>()) return v;
    const QDBusArgument a = v.value<QDBusArgument>();
    if (a.currentType() == QDBusArgument::ArrayType) {
        QList<QByteArray> bytes; QVariantList list;
        a.beginArray();
        while (!a.atEnd()) { const QVariant e = a.asVariant(); if (e.userType() == QMetaType::QByteArray) bytes << e.toByteArray(); else list << e; }
        a.endArray();
        if (!bytes.isEmpty()) { QStringList out; for (const QByteArray &b : std::as_const(bytes)) out << QString::fromUtf8(b.constData()); return out; }   // strings are NUL-terminated
        return list;
    }
    return v;
}

RemovableModel::RemovableModel(QObject *parent) : QAbstractListModel(parent)
{
    qDBusRegisterMetaType<InterfaceMap>();
    qDBusRegisterMetaType<ManagedObjects>();
    QDBusConnection bus = QDBusConnection::systemBus();
    bus.connect(kService, kRoot, QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("InterfacesAdded"), this, SLOT(onInterfacesAdded(QDBusObjectPath, InterfaceMap)));
    bus.connect(kService, kRoot, QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("InterfacesRemoved"), this, SLOT(onInterfacesRemoved(QDBusObjectPath, QStringList)));
    // mount points come and go as PropertiesChanged on the block's Filesystem interface (any object path under UDisks2)
    bus.connect(kService, QString(), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"), this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList, QDBusMessage)));
    refresh();
}

QHash<int, QByteArray> RemovableModel::roleNames() const
{
    return {{LabelRole, "label"}, {DeviceRole, "device"}, {MountedRole, "mounted"}, {MountPointRole, "mountPoint"}, {SizeRole, "size"}, {IconRole, "icon"}, {EjectableRole, "ejectable"}, {BusyRole, "busy"}, {DriveRole, "drive"}, {OpticalRole, "optical"}};
}

QVariant RemovableModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size()) return {};
    const Row &r = m_rows.at(index.row());
    switch (role) {
    case LabelRole: return r.label;
    case DeviceRole: return r.device;
    case MountedRole: return !r.mountPoint.isEmpty();
    case MountPointRole: return r.mountPoint;
    case SizeRole: return r.size;
    case IconRole: return r.icon;
    case EjectableRole: return r.ejectable;
    case BusyRole: return r.busy;
    case DriveRole: return r.drive;
    case OpticalRole: return r.optical;
    }
    return {};
}

QString RemovableModel::mountPoint(int row) const { return row >= 0 && row < m_rows.size() ? m_rows.at(row).mountPoint : QString(); }

void RemovableModel::setError(const QString &e)
{
    if (e == m_lastError) return;
    m_lastError = e;
    Q_EMIT lastErrorChanged();
}

void RemovableModel::refresh()
{
    QDBusMessage m = QDBusMessage::createMethodCall(kService, kRoot, QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("GetManagedObjects"));
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(m), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<ManagedObjects> reply = *w;
        if (reply.isError()) { qInfo("sirca-shell: removable: UDisks2: %s", qPrintable(reply.error().message())); return; }
        const ManagedObjects objects = reply.value();
        beginResetModel();
        m_rows.clear(); m_drives.clear();
        for (auto it = objects.cbegin(); it != objects.cend(); ++it) if (it.value().contains(kDrive)) m_drives.insert(it.key().path(), it.value().value(kDrive));
        for (auto it = objects.cbegin(); it != objects.cend(); ++it) if (it.value().contains(kFilesystem)) readBlock(it.key().path(), it.value().value(kBlock), it.value().value(kFilesystem));
        endResetModel();
        m_available = true;
        Q_EMIT countChanged();
    });
}

QVariantMap RemovableModel::driveProps(const QString &drivePath) const
{
    if (m_drives.contains(drivePath)) return m_drives.value(drivePath);
    // a drive announced after its block (order in InterfacesAdded is not guaranteed): one synchronous read of its properties
    QDBusMessage m = QDBusMessage::createMethodCall(kService, drivePath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
    m.setArguments({kDrive});
    const QDBusMessage r = QDBusConnection::systemBus().call(m, QDBus::Block, 500);
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty()) return {};
    const QVariant a = r.arguments().first();
    if (a.userType() == qMetaTypeId<QDBusArgument>()) { QVariantMap props; a.value<QDBusArgument>() >> props; return props; }
    return a.toMap();
}

static QString humanSize(qulonglong b)
{
    const char *u[] = {"B", "kB", "MB", "GB", "TB"}; double v = double(b); int i = 0;
    while (v >= 1000 && i < 4) { v /= 1000; ++i; }
    return QString::number(v, 'f', v < 10 && i > 0 ? 1 : 0) + QLatin1Char(' ') + QLatin1String(u[i]);
}

// a file system on a block device counts when its drive is removable (USB stick, card, external disc) or the block is
// flagged for the desktop (HintAuto); never system drives, hidden ones, loop devices or the root file system
void RemovableModel::readBlock(const QString &path, const QVariantMap &block, const QVariantMap &fs)
{
    if (block.value(QStringLiteral("HintIgnore")).toBool() || block.value(QStringLiteral("HintSystem")).toBool()) return;
    const QString drivePath = block.value(QStringLiteral("Drive")).value<QDBusObjectPath>().path();
    if (drivePath.isEmpty() || drivePath == QLatin1String("/")) return;
    const QVariantMap drive = driveProps(drivePath);
    const bool removable = drive.value(QStringLiteral("Removable")).toBool() || drive.value(QStringLiteral("MediaRemovable")).toBool() || drive.value(QStringLiteral("Ejectable")).toBool();
    const QString bus = drive.value(QStringLiteral("ConnectionBus")).toString();
    if (!removable && bus != QLatin1String("usb") && bus != QLatin1String("sdio") && !block.value(QStringLiteral("HintAuto")).toBool()) return;
    const QStringList mounts = unwrap(fs.value(QStringLiteral("MountPoints"))).toStringList();
    if (mounts.contains(QStringLiteral("/")) || mounts.contains(QStringLiteral("/boot")) || mounts.contains(QStringLiteral("/home"))) return;
    Row r;
    r.path = path; r.drive = drivePath;
    r.device = QString::fromUtf8(unwrap(block.value(QStringLiteral("PreferredDevice"))).toByteArray().constData());
    if (r.device.isEmpty()) r.device = QString::fromUtf8(unwrap(block.value(QStringLiteral("Device"))).toByteArray().constData());
    r.size = block.value(QStringLiteral("Size")).toULongLong();
    r.mountPoint = mounts.value(0);
    r.ejectable = drive.value(QStringLiteral("Ejectable")).toBool() || drive.value(QStringLiteral("CanPowerOff")).toBool();
    const QString media = drive.value(QStringLiteral("Media")).toString();
    r.optical = media.startsWith(QLatin1String("optical"));
    r.label = block.value(QStringLiteral("IdLabel")).toString();
    if (r.label.isEmpty()) { const QString v = drive.value(QStringLiteral("Vendor")).toString().simplified(), m = drive.value(QStringLiteral("Model")).toString().simplified(); r.label = (v + QLatin1Char(' ') + m).simplified(); }
    if (r.label.isEmpty()) r.label = humanSize(r.size) + QStringLiteral(" volume");
    r.icon = r.optical ? QStringLiteral("media-optical") : media.startsWith(QLatin1String("flash_sd")) || media.startsWith(QLatin1String("flash_mmc")) ? QStringLiteral("media-flash-sd-mmc")
           : media.startsWith(QLatin1String("flash")) || bus == QLatin1String("usb") && r.size < 256ull * 1024 * 1024 * 1024 ? QStringLiteral("media-removable") : QStringLiteral("drive-harddisk-usb");
    m_rows << r;
}

void RemovableModel::onInterfacesAdded(const QDBusObjectPath &path, const InterfaceMap &ifaces)
{
    if (ifaces.contains(kDrive)) m_drives.insert(path.path(), ifaces.value(kDrive));
    if (!ifaces.contains(kFilesystem)) return;
    for (const Row &r : std::as_const(m_rows)) if (r.path == path.path()) return;
    const int before = m_rows.size();
    readBlock(path.path(), ifaces.value(kBlock), ifaces.value(kFilesystem));
    if (m_rows.size() == before) return;
    // readBlock appended; announce it as an insert at the end
    Row r = m_rows.takeLast();
    beginInsertRows({}, m_rows.size(), m_rows.size()); m_rows << r; endInsertRows();
    Q_EMIT countChanged();
}

void RemovableModel::onInterfacesRemoved(const QDBusObjectPath &path, const QStringList &interfaces)
{
    if (interfaces.contains(kDrive)) m_drives.remove(path.path());
    if (!interfaces.contains(kFilesystem) && !interfaces.contains(kBlock)) return;
    for (int i = 0; i < m_rows.size(); ++i) if (m_rows.at(i).path == path.path()) { beginRemoveRows({}, i, i); m_rows.removeAt(i); endRemoveRows(); Q_EMIT countChanged(); return; }
}

void RemovableModel::onPropertiesChanged(const QString &iface, const QVariantMap &changed, const QStringList &, const QDBusMessage &msg)
{
    if (iface != kFilesystem || !changed.contains(QStringLiteral("MountPoints"))) return;
    for (int i = 0; i < m_rows.size(); ++i) if (m_rows.at(i).path == msg.path()) {
        const QString mp = unwrap(changed.value(QStringLiteral("MountPoints"))).toStringList().value(0);
        if (mp == m_rows.at(i).mountPoint) return;
        m_rows[i].mountPoint = mp;
        this->changed(i, {MountedRole, MountPointRole});
        return;
    }
}

void RemovableModel::changed(int row, const QList<int> &roles) { Q_EMIT dataChanged(index(row), index(row), roles); }

void RemovableModel::call(int row, const QString &iface, const QString &method, const QVariantList &args, std::function<void(bool)> done)
{
    if (row < 0 || row >= m_rows.size() || m_rows.at(row).busy) return;
    const QString path = m_rows.at(row).path;
    m_rows[row].busy = true; changed(row, {BusyRole});
    QDBusMessage m = QDBusMessage::createMethodCall(kService, iface == kDrive ? m_rows.at(row).drive : path, iface, method);
    m.setArguments(args);
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(m, 60000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, path, done] {
        w->deleteLater();
        const QDBusMessage r = w->reply();
        const bool ok = r.type() != QDBusMessage::ErrorMessage;
        if (!ok) { qInfo("sirca-shell: removable: %s", qPrintable(r.errorMessage())); setError(r.errorMessage()); } else setError(QString());
        for (int i = 0; i < m_rows.size(); ++i) if (m_rows.at(i).path == path) { m_rows[i].busy = false; changed(i, {BusyRole}); break; }
        if (done) done(ok);
    });
}

void RemovableModel::mount(int row)
{
    if (row < 0 || row >= m_rows.size() || !m_rows.at(row).mountPoint.isEmpty()) return;
    const QString path = m_rows.at(row).path;
    call(row, kFilesystem, QStringLiteral("Mount"), {QVariantMap{}}, [this, path](bool ok) {
        if (!ok) return;
        for (const Row &r : std::as_const(m_rows)) if (r.path == path && !r.mountPoint.isEmpty()) { Q_EMIT mounted(r.label, r.mountPoint); return; }
        // the PropertiesChanged with the mount point may still be on its way
        QTimer::singleShot(150, this, [this, path] { for (const Row &r : std::as_const(m_rows)) if (r.path == path && !r.mountPoint.isEmpty()) { Q_EMIT mounted(r.label, r.mountPoint); return; } });
    });
}

void RemovableModel::unmount(int row)
{
    if (row < 0 || row >= m_rows.size() || m_rows.at(row).mountPoint.isEmpty()) return;
    call(row, kFilesystem, QStringLiteral("Unmount"), {QVariantMap{}}, nullptr);
}

// eject = unmount what is mounted of that drive, then Eject (discs, card readers) or PowerOff (USB drives): the same steps
// Plasma's device notifier takes for "safely remove"
void RemovableModel::eject(int row)
{
    if (row < 0 || row >= m_rows.size()) return;
    const QString drive = m_rows.at(row).drive;
    QList<int> mountedRows;
    for (int i = 0; i < m_rows.size(); ++i) if (m_rows.at(i).drive == drive && !m_rows.at(i).mountPoint.isEmpty()) mountedRows << i;
    auto finish = [this, drive, row] {
        const QVariantMap d = driveProps(drive);
        const QString method = d.value(QStringLiteral("Ejectable")).toBool() ? QStringLiteral("Eject") : d.value(QStringLiteral("CanPowerOff")).toBool() ? QStringLiteral("PowerOff") : QString();
        if (method.isEmpty()) return;
        for (int i = 0; i < m_rows.size(); ++i) if (m_rows.at(i).drive == drive) { call(i, kDrive, method, {QVariantMap{}}, nullptr); return; }
        Q_UNUSED(row);
    };
    if (mountedRows.isEmpty()) { finish(); return; }
    auto pending = std::make_shared<int>(mountedRows.size());
    auto failed = std::make_shared<bool>(false);
    for (int i : std::as_const(mountedRows)) call(i, kFilesystem, QStringLiteral("Unmount"), {QVariantMap{}}, [pending, failed, finish](bool ok) { if (!ok) *failed = true; if (--*pending == 0 && !*failed) finish(); });
}
