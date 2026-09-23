// The search panel's emoji picker (":smile") and its two clipboard-side helpers. EmojiModel: the bundled list
// (qml/data/emoji.json, built by scripts/gen-emoji.py from Unicode's emoji-test.txt), loaded on first use, filtered by
// `query` (every word must start a word of the name or a keyword; an empty query shows the list in CLDR order).
// copy() puts text on the clipboard through KSystemClipboard, so it works from a layer-shell surface on Wayland and
// lands in the shell's clipboard history like any other copy.
// ColorPick: KWin's screen colour picker (org.kde.kwin.ColorPicker.pick) called asynchronously: the reply only comes
// when the user clicks, and a blocking call would freeze the whole shell until then.
#pragma once
#include <QAbstractListModel>
#include <QColor>
#include <QStringList>
#include <qqml.h>

class EmojiModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int limit READ limit WRITE setLimit NOTIFY limitChanged)   // at most this many rows (the grid shows a page, not 1900 cells)
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)   // the JSON is parsed the first time this goes true, not at start-up
public:
    enum Roles { EmojiRole = Qt::UserRole + 1, NameRole, GroupRole, KeywordsRole };
    explicit EmojiModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : m_rows.size(); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    QString query() const { return m_query; }
    void setQuery(const QString &q);
    int limit() const { return m_limit; }
    void setLimit(int n);
    bool loaded() const { return m_loaded; }
    bool active() const { return m_active; }
    void setActive(bool on);
    Q_INVOKABLE void load();                                     // reads the JSON (once); `active` going true does it by itself
    Q_INVOKABLE void copy(const QString &text);                  // plain text to the clipboard
Q_SIGNALS:
    void queryChanged();
    void countChanged();
    void limitChanged();
    void loadedChanged();
    void activeChanged();
private:
    struct Entry { QString emoji, name, keywords; int group = 0; QStringList words; };
    void refilter();
    QString m_query;
    int m_limit = 80;
    bool m_loaded = false, m_active = false;
    QList<Entry> m_all;
    QList<int> m_rows;                                           // indexes into m_all
};

class ColorPick : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
public:
    explicit ColorPick(QObject *parent = nullptr) : QObject(parent) {}
    bool busy() const { return m_busy; }
    Q_INVOKABLE void pick();                                     // picked(color) when the user clicks, failed() on cancel / no KWin
    Q_INVOKABLE void copy(const QString &text);
Q_SIGNALS:
    void busyChanged();
    void picked(const QColor &color);
    void failed(const QString &why);
private:
    bool m_busy = false;
};
