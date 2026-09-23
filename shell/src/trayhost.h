#pragma once
// Native system tray ("Status and Notifications"): a StatusNotifierItem host. The watcher service lives in kded6, so no
// plasmashell is involved: we register as a host, mirror every item, and import each item's com.canonical.dbusmenu menu as
// plain data that QML draws as a glass popup. Icons come in three flavours (theme name, file path with an own theme folder,
// raw ARGB pixmaps); TrayItem::icon is always something an Image / Kirigami.Icon can take.
#include <QAbstractListModel>
#include <QDBusArgument>
#include <QDBusServiceWatcher>
#include <QImage>
#include <QQuickImageProvider>
#include <QVariantList>
#include <qqml.h>

class TrayItem : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("made by TrayHost")
    Q_PROPERTY(QString itemId READ itemId NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)              // Passive | Active | NeedsAttention
    Q_PROPERTY(QString icon READ icon NOTIFY changed)                  // theme name, absolute file, or image://tray/…
    Q_PROPERTY(bool iconIsFile READ iconIsFile NOTIFY changed)
    Q_PROPERTY(bool hasMenu READ hasMenu NOTIFY changed)
    Q_PROPERTY(bool itemIsMenu READ itemIsMenu NOTIFY changed)
public:
    TrayItem(const QString &service, const QString &path, QObject *parent);
    QString itemId() const { return m_id; }
    QString title() const { return m_title; }
    QString status() const { return m_status; }
    QString icon() const { return m_icon; }
    bool iconIsFile() const { return m_iconIsFile; }
    bool hasMenu() const { return !m_menuPath.isEmpty() && m_menuPath != QLatin1String("/"); }
    bool itemIsMenu() const { return m_itemIsMenu; }
    QString service() const { return m_service; }
    QString key() const { return m_service + m_path; }
    Q_INVOKABLE void activate(int x, int y);
    Q_INVOKABLE void secondaryActivate(int x, int y);
    Q_INVOKABLE void scroll(int delta, bool horizontal);
    Q_INVOKABLE void fetchMenu();                                      // answers with menuReady()
    Q_INVOKABLE void menuEvent(int id);                                // "clicked"
public Q_SLOTS:
    void refresh();                                                    // everything (GetAll): on creation
private Q_SLOTS:
    void onNewIcon(); void onNewAttentionIcon(); void onNewTitle(); void onNewToolTip(); void onNewStatus(); void onNewMenu();
Q_SIGNALS:
    void changed();
    void menuReady(const QVariantList &entries);
private:
    void fetch(const QStringList &names);                              // only these properties, then apply()
    void apply();                                                      // derive title / status / icon from m_props
    QVariantMap m_props;                                               // the item's properties as last read
    QString m_service, m_path, m_id, m_title, m_status = QStringLiteral("Active"), m_icon, m_menuPath;
    bool m_iconIsFile = false, m_itemIsMenu = false;
    int m_rev = 0;
};

class TrayHost : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
public:
    explicit TrayHost(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : m_items.size(); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override { return {{Qt::UserRole + 1, "item"}}; }
    int count() const { return m_items.size(); }
Q_SIGNALS:
    void countChanged();
private Q_SLOTS:
    void onRegistered(const QString &serviceAndPath);
    void onUnregistered(const QString &serviceAndPath);
private:
    void connectToWatcher();
    void add(const QString &serviceAndPath);
    void removeWhere(const std::function<bool(TrayItem *)> &match);
    QList<TrayItem *> m_items;
    QDBusServiceWatcher m_gone;
    QString m_hostName;
};

class TrayImageProvider : public QQuickImageProvider
{
public:
    TrayImageProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
    static void store(const QString &key, const QImage &image);
    static void drop(const QString &key);
};
