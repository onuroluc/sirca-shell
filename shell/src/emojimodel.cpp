#include "emojimodel.h"
#include <KSystemClipboard>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeData>
#include <QRegularExpression>

EmojiModel::EmojiModel(QObject *parent) : QAbstractListModel(parent) {}

QHash<int, QByteArray> EmojiModel::roleNames() const
{
    return {{EmojiRole, "emoji"}, {NameRole, "name"}, {GroupRole, "group"}, {KeywordsRole, "keywords"}};
}

QVariant EmojiModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size()) return {};
    const Entry &e = m_all.at(m_rows.at(index.row()));
    switch (role) {
    case EmojiRole: return e.emoji;
    case NameRole: return e.name;
    case GroupRole: return e.group;
    case KeywordsRole: return e.keywords;
    }
    return {};
}

void EmojiModel::load()
{
    if (m_loaded) return;
    m_loaded = true;                                             // even when the file is missing: no point retrying per keystroke
    QFile f(QStringLiteral(":/qt/qml/SircaShell/qml/data/emoji.json"));
    if (!f.open(QIODevice::ReadOnly)) { qWarning("emoji: qml/data/emoji.json missing from the build"); Q_EMIT loadedChanged(); return; }
    const QJsonArray list = QJsonDocument::fromJson(f.readAll()).object().value(QLatin1String("emoji")).toArray();
    m_all.reserve(list.size());
    for (const QJsonValue &v : list) {
        const QJsonArray a = v.toArray(); if (a.size() < 3) continue;
        Entry e; e.emoji = a.at(0).toString(); e.name = a.at(1).toString(); e.group = a.at(2).toInt(); e.keywords = a.size() > 3 ? a.at(3).toString() : QString();
        e.words = (e.name + QLatin1Char(' ') + e.keywords).toLower().split(QRegularExpression(QStringLiteral("[\\s:,-]+")), Qt::SkipEmptyParts);
        m_all.append(e);
    }
    Q_EMIT loadedChanged();
    refilter();
}

void EmojiModel::setQuery(const QString &q)
{
    if (q == m_query) return;
    m_query = q; Q_EMIT queryChanged();
    if (m_loaded) refilter();
}

void EmojiModel::setActive(bool on)
{
    if (on == m_active) return;
    m_active = on; Q_EMIT activeChanged();
    if (on && !m_loaded) load();
}

void EmojiModel::setLimit(int n)
{
    if (n == m_limit) return;
    m_limit = n; Q_EMIT limitChanged();
    if (m_loaded) refilter();
}

void EmojiModel::refilter()
{
    const QStringList words = m_query.toLower().simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    QList<int> exact, prefix;                                    // "smile" lists "smiling face" behind an entry whose word IS smile
    for (int i = 0; i < m_all.size() && exact.size() < m_limit; ++i) {
        const Entry &e = m_all.at(i);
        bool ok = true, all = true;
        for (const QString &w : words) {
            bool hit = false, whole = false;
            for (const QString &ew : e.words) { if (ew.startsWith(w)) { hit = true; if (ew == w) whole = true; } }
            if (!hit) { ok = false; break; }
            if (!whole) all = false;
        }
        if (!ok) continue;
        if (all) exact.append(i); else if (prefix.size() < m_limit) prefix.append(i);
    }
    beginResetModel();
    m_rows = exact; for (int i : prefix) { if (m_rows.size() >= m_limit) break; m_rows.append(i); }
    endResetModel();
    Q_EMIT countChanged();
}

void EmojiModel::copy(const QString &text)
{
    if (auto *c = KSystemClipboard::instance()) { auto *mime = new QMimeData; mime->setText(text); c->setMimeData(mime, QClipboard::Clipboard); }
}

// ---- ColorPick
void ColorPick::copy(const QString &text)
{
    if (auto *c = KSystemClipboard::instance()) { auto *mime = new QMimeData; mime->setText(text); c->setMimeData(mime, QClipboard::Clipboard); }
}

void ColorPick::pick()
{
    if (m_busy) return;
    m_busy = true; Q_EMIT busyChanged();
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/ColorPicker"), QStringLiteral("org.kde.kwin.ColorPicker"), QStringLiteral("pick"));
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(m, 10 * 60 * 1000), this);   // the user may take a while to click
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        m_busy = false; Q_EMIT busyChanged();
        QDBusPendingReply<uint> r = *w;
        if (r.isError()) { Q_EMIT failed(r.error().message()); return; }   // Escape in the picker answers with an error, as does a missing KWin
        Q_EMIT picked(QColor::fromRgba(r.value()));               // KWin replies with QColor::rgba(): 0xAARRGGBB
    });
}
