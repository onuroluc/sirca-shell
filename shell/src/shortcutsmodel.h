// Every global shortcut the session knows, for the cheat sheet (Meta+/): asked from kglobalaccel over D-Bus
// (allComponents, then each component's allShortcutInfos). C++ because the reply is a list of nested structs
// (a(ssssssaiai)) that QML cannot decode; KGlobalShortcutInfo's own D-Bus operators do it. Rows are sorted with the
// shell's own component first, then by component name, then by shortcut name; `filter` narrows them (name, key or
// component contains every word).
#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <qqml.h>

class ShortcutsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int total READ total NOTIFY countChanged)          // before the filter
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
public:
    enum Roles { ComponentRole = Qt::UserRole + 1, ComponentIdRole, NameRole, KeysRole, KeyListRole };
    explicit ShortcutsModel(QObject *parent = nullptr);
    Q_INVOKABLE void refresh();                                  // asynchronous; loading goes true until every component has answered
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : m_rows.size(); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    QString filter() const { return m_filter; }
    void setFilter(const QString &f);
    int total() const { return m_all.size(); }
    bool loading() const { return m_pending > 0; }
Q_SIGNALS:
    void filterChanged();
    void countChanged();
    void loadingChanged();
private:
    struct Row { QString component, componentId, name, keys; QStringList keyList; };
    void componentAnswered(const QString &path, const QVariant &reply);
    void finish();
    void refilter();
    static bool before(const Row &a, const Row &b);
    QString m_filter;
    QList<Row> m_all, m_rows, m_incoming;
    int m_pending = 0;
};
