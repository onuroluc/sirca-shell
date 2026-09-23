// Removable drives for the bar's "disks" lobe: USB sticks, SD cards, external discs and their file systems, with mount /
// unmount / eject. Straight from UDisks2 over the system bus (the same source Solid's StorageAccess reads on Linux; the
// Solid development files are not a build dependency of the shell), so no daemon of ours and no polling: UDisks announces
// devices and mount changes, the model follows. Rows are file systems on removable (or hot-pluggable, non-system) drives.
#pragma once
#include <QAbstractListModel>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QHash>
#include <QMap>
#include <QVariantMap>
#include <functional>
#include <qqml.h>

using InterfaceMap = QMap<QString, QVariantMap>;                 // a{sa{sv}}
using ManagedObjects = QMap<QDBusObjectPath, InterfaceMap>;      // a{oa{sa{sv}}}
Q_DECLARE_METATYPE(InterfaceMap)
Q_DECLARE_METATYPE(ManagedObjects)



class RemovableModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool available READ available NOTIFY countChanged)      // UDisks2 answered at all
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
public:
    enum Roles { LabelRole = Qt::UserRole + 1, DeviceRole, MountedRole, MountPointRole, SizeRole, IconRole, EjectableRole, BusyRole, DriveRole, OpticalRole };
    explicit RemovableModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : m_rows.size(); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_rows.size(); }
    bool available() const { return m_available; }
    QString lastError() const { return m_lastError; }
    Q_INVOKABLE void mount(int row);
    Q_INVOKABLE void unmount(int row);
    Q_INVOKABLE void eject(int row);                                    // unmount every file system of the drive, then eject / power it off
    Q_INVOKABLE QString mountPoint(int row) const;
    Q_INVOKABLE void refresh();
Q_SIGNALS:
    void countChanged();
    void lastErrorChanged();
    void mounted(const QString &label, const QString &mountPoint);       // after a mount asked for here (the lobe then opens the folder)
private Q_SLOTS:
    void onInterfacesAdded(const QDBusObjectPath &path, const InterfaceMap &interfaces);
    void onInterfacesRemoved(const QDBusObjectPath &path, const QStringList &interfaces);
    void onPropertiesChanged(const QString &iface, const QVariantMap &changed, const QStringList &invalidated, const QDBusMessage &msg);
private:
    struct Row { QString path, drive, label, device, mountPoint, icon; qulonglong size = 0; bool ejectable = false, optical = false, busy = false; };
    void rebuild();
    void readBlock(const QString &path, const QVariantMap &block, const QVariantMap &fs);
    void changed(int row, const QList<int> &roles = {});
    void setError(const QString &e);
    void call(int row, const QString &iface, const QString &method, const QVariantList &args, std::function<void(bool)> done);
    QVariantMap driveProps(const QString &drivePath) const;
    QList<Row> m_rows;
    QHash<QString, QVariantMap> m_drives;                                // drive object path -> its properties
    bool m_available = false;
    QString m_lastError;
};
