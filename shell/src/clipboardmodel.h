#pragma once
// Clipboard manager + history. Plasma's (Klipper) lives inside plasmashell; without it the Wayland clipboard empties
// when the app you copied from closes. This one runs in the shell: it watches the clipboard through KSystemClipboard
// (the compositor's data-control interface, works without focus), keeps the last entries (text, images, file lists),
// puts the newest one back when the clipboard goes empty, and lets QML pick an older entry. Entries that a password
// manager marks as secret are never stored. History is saved under ~/.local/share/sirca-shell/clipboard/.
#include <QAbstractListModel>
#include <QDateTime>
#include <QHash>
#include <QTimer>
#include <qqml.h>

class QMimeData;

class ClipboardModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
public:
    enum Roles { KindRole = Qt::UserRole + 1, TextRole, PreviewRole, ImageRole, TimeRole, SizeRole, PinnedRole };
    explicit ClipboardModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : m_rows.size(); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_rows.size(); }
    QString filter() const { return m_filter; }
    void setFilter(const QString &f);
    Q_INVOKABLE void select(int row);              // put that entry on the clipboard (it moves to the top)
    Q_INVOKABLE void remove(int row);
    Q_INVOKABLE void togglePin(int row);           // a pinned entry stays at the top, survives "Clear history" and is never pushed out by new copies
    Q_INVOKABLE void clear();                      // everything that is not pinned
Q_SIGNALS:
    void countChanged();
    void filterChanged();
private:
    struct Entry { QString kind, text, imagePath; QDateTime time; QString note; bool pinned = false; quint64 id = 0; };   // id: stable row identity (see refilter)
    void onClipboardChanged();
    void restoreIfEmpty();
    void push(const Entry &e);
    void refilter();                               // brings m_rows to the current order with removes / inserts / moves
    void changed(quint64 id);                      // dataChanged for that entry's row, if shown
    void load();
    void save();
    QMimeData *toMime(const Entry &e) const;
    static QString dir();
    QList<Entry> m_entries;
    QList<quint64> m_rows;                         // shown rows, as entry ids
    QHash<quint64, int> m_index;                   // id -> position in m_entries (rebuilt by refilter)
    quint64 m_lastId = 0;
    QString m_filter;
    QTimer m_saveLater, m_restoreLater;
    bool m_settingOurselves = false;
    static constexpr int kMax = 40;
};
