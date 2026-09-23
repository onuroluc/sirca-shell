// Lyrics for the now-playing lobe, opt-in (config `lyrics: true`; nothing is looked up while it is off). Source: LRCLIB
// (lrclib.net, no key): one GET per track by title / artist / album / length, a search as the fallback, the answer cached
// under ~/.cache/<app>/lyrics/ (misses too, so a track without lyrics is asked about once). Synced lyrics (LRC) come back
// as timed lines the panel scrolls with the player's position; plain lyrics as one text.
#pragma once
#include <QObject>
#include <QString>
#include <QVariantList>
#include <qqml.h>

class QNetworkAccessManager;
class QNetworkReply;

class Lyrics : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(QString status READ status NOTIFY changed)                 // "idle" | "loading" | "ready" | "none" | "error"
    Q_PROPERTY(bool synced READ synced NOTIFY changed)                    // lines carry times
    Q_PROPERTY(QVariantList lines READ lines NOTIFY changed)              // [{ t: ms (-1 when plain), text }]
    Q_PROPERTY(QString plain READ plain NOTIFY changed)
    Q_PROPERTY(QString key READ key NOTIFY changed)                       // the track these lyrics are for
public:
    explicit Lyrics(QObject *parent = nullptr);
    bool enabled() const { return m_enabled; }
    void setEnabled(bool on);
    QString status() const { return m_status; }
    bool synced() const { return m_synced; }
    QVariantList lines() const { return m_lines; }
    QString plain() const { return m_plain; }
    QString key() const { return m_key; }
    Q_INVOKABLE void lookup(const QString &title, const QString &artist, const QString &album, int durationSec);
    Q_INVOKABLE int lineAt(qint64 positionMs) const;                     // the synced line for a position (-1 before the first)
    Q_INVOKABLE void clear();
Q_SIGNALS:
    void enabledChanged();
    void changed();
private:
    void apply(const QVariantMap &entry, const QString &key);
    void finish(const QString &status);
    QString cachePath(const QString &key) const;
    void request(const QUrl &url, const QString &key, bool isSearch, const QString &title, const QString &artist, int durationSec);
    static QVariantList parseLrc(const QString &lrc);
    bool m_enabled = false, m_synced = false;
    QString m_status = QStringLiteral("idle"), m_key, m_plain, m_pending;
    QVariantList m_lines;
    QNetworkAccessManager *m_nam = nullptr;
    QNetworkReply *m_reply = nullptr;
};
