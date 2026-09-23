#include "lyrics.h"
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>
#include <algorithm>

Lyrics::Lyrics(QObject *parent) : QObject(parent) {}

void Lyrics::setEnabled(bool on)
{
    if (on == m_enabled) return;
    m_enabled = on;
    if (!on) { if (m_reply) { m_reply->abort(); m_reply = nullptr; } clear(); }
    Q_EMIT enabledChanged();
}

void Lyrics::clear()
{
    m_key.clear(); m_lines.clear(); m_plain.clear(); m_synced = false; m_status = QStringLiteral("idle");
    Q_EMIT changed();
}

QString Lyrics::cachePath(const QString &key) const
{
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/lyrics/") + QString::fromLatin1(QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Sha1).toHex()) + QStringLiteral(".json");
}

// [mm:ss.xx] text, several stamps on one line allowed; sorted by time
QVariantList Lyrics::parseLrc(const QString &lrc)
{
    static const QRegularExpression stamp(QStringLiteral("\\[(\\d+):(\\d+)(?:[.:](\\d+))?\\]"));
    struct L { qint64 t; QString text; };
    QList<L> out;
    const QStringList lines = lrc.split(QRegularExpression(QStringLiteral("\r?\n")));
    for (const QString &line : lines) {
        auto it = stamp.globalMatch(line);
        QList<qint64> times; int end = 0;
        while (it.hasNext()) { const auto m = it.next(); const QString frac = m.captured(3); const qint64 ms = frac.isEmpty() ? 0 : (frac.size() == 2 ? frac.toInt() * 10 : frac.size() == 1 ? frac.toInt() * 100 : frac.left(3).toInt());
            times << (m.captured(1).toLongLong() * 60000 + m.captured(2).toLongLong() * 1000 + ms); end = m.capturedEnd(0); }
        if (times.isEmpty()) continue;
        const QString text = line.mid(end).trimmed();
        for (qint64 t : std::as_const(times)) out.append({t, text});
    }
    std::stable_sort(out.begin(), out.end(), [](const L &a, const L &b) { return a.t < b.t; });
    QVariantList list;
    for (const L &l : std::as_const(out)) list << QVariantMap{{QStringLiteral("t"), l.t}, {QStringLiteral("text"), l.text}};
    return list;
}

int Lyrics::lineAt(qint64 positionMs) const
{
    if (!m_synced) return -1;
    int idx = -1;
    for (int i = 0; i < m_lines.size(); ++i) { if (m_lines.at(i).toMap().value(QStringLiteral("t")).toLongLong() <= positionMs) idx = i; else break; }
    return idx;
}

void Lyrics::apply(const QVariantMap &entry, const QString &key)
{
    m_key = key;
    const QString synced = entry.value(QStringLiteral("syncedLyrics")).toString(), plain = entry.value(QStringLiteral("plainLyrics")).toString();
    m_lines = synced.isEmpty() ? QVariantList() : parseLrc(synced);
    m_synced = !m_lines.isEmpty();
    m_plain = plain.trimmed();
    if (!m_synced && m_plain.isEmpty()) { finish(QStringLiteral("none")); return; }
    if (!m_synced) for (const QString &l : m_plain.split(QLatin1Char('\n'))) m_lines << QVariantMap{{QStringLiteral("t"), -1}, {QStringLiteral("text"), l.trimmed()}};
    finish(QStringLiteral("ready"));
}

void Lyrics::finish(const QString &status)
{
    m_status = status;
    Q_EMIT changed();
}

void Lyrics::lookup(const QString &title, const QString &artist, const QString &album, int durationSec)
{
    if (!m_enabled || title.trimmed().isEmpty()) return;
    const QString key = title.trimmed() + QLatin1Char('|') + artist.trimmed() + QLatin1Char('|') + album.trimmed() + QLatin1Char('|') + QString::number(durationSec);
    if (key == m_key || key == m_pending) return;
    if (m_reply) { m_reply->abort(); m_reply = nullptr; }
    QFile cache(cachePath(key));
    if (cache.open(QIODevice::ReadOnly)) { m_pending.clear(); apply(QJsonDocument::fromJson(cache.readAll()).object().toVariantMap(), key); return; }
    m_pending = key;
    m_lines.clear(); m_plain.clear(); m_synced = false; m_status = QStringLiteral("loading"); m_key.clear();
    Q_EMIT changed();
    QUrl url(QStringLiteral("https://lrclib.net/api/get"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("track_name"), title.trimmed());
    q.addQueryItem(QStringLiteral("artist_name"), artist.trimmed());
    if (!album.trimmed().isEmpty()) q.addQueryItem(QStringLiteral("album_name"), album.trimmed());
    if (durationSec > 0) q.addQueryItem(QStringLiteral("duration"), QString::number(durationSec));
    url.setQuery(q);
    request(url, key, false, title, artist, durationSec);
}

void Lyrics::request(const QUrl &url, const QString &key, bool isSearch, const QString &title, const QString &artist, int durationSec)
{
    if (!m_nam) m_nam = new QNetworkAccessManager(this);
    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", QCoreApplication::applicationName().toUtf8() + " (https://lrclib.net)");
    req.setRawHeader("Lrclib-Client", QCoreApplication::applicationName().toUtf8());
    req.setTransferTimeout(15000);
    QNetworkReply *r = m_nam->get(req);
    m_reply = r;
    connect(r, &QNetworkReply::finished, this, [this, r, key, isSearch, title, artist, durationSec] {
        r->deleteLater();
        if (m_reply == r) m_reply = nullptr;
        if (key != m_pending) return;                                                  // aborted, or a newer lookup superseded this one                                                  // a newer lookup superseded this one
        const int http = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (r->error() != QNetworkReply::NoError && http != 404) { m_pending.clear(); m_key = key; finish(QStringLiteral("error")); qInfo("sirca-shell: lyrics: %s", qPrintable(r->errorString())); return; }
        const QByteArray body = r->readAll();
        QVariantMap entry;
        if (!isSearch && http != 404) entry = QJsonDocument::fromJson(body).object().toVariantMap();
        else if (isSearch) {
            // the search returns candidates: prefer one whose length matches and that carries synced lyrics
            const QJsonArray arr = QJsonDocument::fromJson(body).array();
            QVariantMap best; int bestScore = -1;
            for (const QJsonValue &v : arr) { const QVariantMap e = v.toObject().toVariantMap(); int score = 0;
                if (durationSec > 0 && qAbs(e.value(QStringLiteral("duration")).toDouble() - durationSec) <= 3) score += 2;
                if (!e.value(QStringLiteral("syncedLyrics")).toString().isEmpty()) score += 1;
                if (score > bestScore) { bestScore = score; best = e; } }
            entry = best;
        }
        if (entry.isEmpty() && !isSearch) {
            QUrl s(QStringLiteral("https://lrclib.net/api/search")); QUrlQuery q;
            q.addQueryItem(QStringLiteral("track_name"), title.trimmed()); if (!artist.trimmed().isEmpty()) q.addQueryItem(QStringLiteral("artist_name"), artist.trimmed()); s.setQuery(q);
            request(s, key, true, title, artist, durationSec);
            return;
        }
        m_pending.clear();
        // cache hits and misses alike (a miss is {} and comes back as "none")
        QVariantMap keep{{QStringLiteral("syncedLyrics"), entry.value(QStringLiteral("syncedLyrics"))}, {QStringLiteral("plainLyrics"), entry.value(QStringLiteral("plainLyrics"))}, {QStringLiteral("instrumental"), entry.value(QStringLiteral("instrumental"))}};
        QDir().mkpath(QFileInfo(cachePath(key)).path());
        QSaveFile f(cachePath(key));
        if (f.open(QIODevice::WriteOnly)) { f.write(QJsonDocument(QJsonObject::fromVariantMap(keep)).toJson(QJsonDocument::Compact)); f.commit(); }
        apply(keep, key);
    });
}
