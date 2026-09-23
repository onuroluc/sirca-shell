// Weather for the clock popup's card and the bar's "weather" widget. Opt-in: nothing is fetched unless config `weather`
// is true. Provider: Open-Meteo (no key, no account); one small GET every 30 minutes while enabled, the reply cached in
// ~/.cache/<app>/weather.json so a restart shows the last reading at once and does not fetch again before it is stale.
// Location: config `weatherLocation` {lat, lon, name}; without one, GeoClue is asked once over D-Bus (city accuracy) and the
// answer is remembered in the cache; if that fails the status says "no-location" and the settings have to name a place.
#pragma once
#include <QDateTime>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <qqml.h>

class QDBusObjectPath;
class QNetworkAccessManager;
class QNetworkReply;

class Weather : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool enabled READ enabled NOTIFY stateChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)           // "off" | "no-location" | "loading" | "ok" | "error"
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY dataChanged)                  // a current reading is available (maybe from the cache)
    Q_PROPERTY(QString locationName READ locationName NOTIFY stateChanged)
    Q_PROPERTY(QString units READ units NOTIFY stateChanged)              // "c" | "f"
    Q_PROPERTY(double temperature READ temperature NOTIFY dataChanged)
    Q_PROPERTY(double feelsLike READ feelsLike NOTIFY dataChanged)
    Q_PROPERTY(double todayMax READ todayMax NOTIFY dataChanged)
    Q_PROPERTY(double todayMin READ todayMin NOTIFY dataChanged)
    Q_PROPERTY(int code READ code NOTIFY dataChanged)                     // WMO weather code
    Q_PROPERTY(bool isDay READ isDay NOTIFY dataChanged)
    Q_PROPERTY(QVariantList hourly READ hourly NOTIFY dataChanged)        // the next hours: { time, temp, code, isDay }
    Q_PROPERTY(QDateTime updated READ updated NOTIFY dataChanged)
public:
    explicit Weather(QObject *parent = nullptr);
    Q_INVOKABLE void configure(const QVariantMap &config);               // the whole user config; reads weather, weatherLocation, weatherUnits
    Q_INVOKABLE void refresh();                                           // fetch now (while enabled and located)
    Q_INVOKABLE void searchPlace(const QString &name);                    // Open-Meteo geocoding; answers through placesFound
    Q_INVOKABLE QString iconFor(int code, bool day) const;                // a Breeze weather-* icon name
    Q_INVOKABLE QString describe(int code) const;                         // "Partly cloudy"
    Q_INVOKABLE QString unitSuffix() const { return m_units == QLatin1String("f") ? QStringLiteral("°F") : QStringLiteral("°C"); }
    bool enabled() const { return m_enabled; }
    QString status() const { return m_status; }
    QString error() const { return m_error; }
    bool ready() const { return m_updated.isValid(); }
    QString locationName() const { return m_name; }
    QString units() const { return m_units; }
    double temperature() const { return m_temp; }
    double feelsLike() const { return m_feels; }
    double todayMax() const { return m_max; }
    double todayMin() const { return m_min; }
    int code() const { return m_code; }
    bool isDay() const { return m_isDay; }
    QVariantList hourly() const { return m_hourly; }
    QDateTime updated() const { return m_updated; }
Q_SIGNALS:
    void stateChanged();
    void placesFound(const QVariantList &places);                         // { name, region, country, lat, lon } per hit
    void dataChanged();
private Q_SLOTS:
    void geoLocation(const QDBusObjectPath &oldPath, const QDBusObjectPath &newPath);
private:
    void setStatus(const QString &s, const QString &error = QString());
    void fetch();
    void apply(const QVariantMap &body, const QDateTime &fetched);
    bool loadCache();
    void saveCache(const QVariantMap &body, const QDateTime &fetched) const;
    QString cachePath() const;
    void askGeoClue();
    void onReply(QNetworkReply *r);
    bool m_enabled = false, m_hasLocation = false, m_geoTried = false, m_isDay = true;
    double m_lat = 0, m_lon = 0, m_temp = 0, m_feels = 0, m_max = 0, m_min = 0;
    int m_code = -1;
    QString m_name, m_units = QStringLiteral("c"), m_status = QStringLiteral("off"), m_error;
    QVariantList m_hourly;
    QDateTime m_updated;
    QVariantMap m_body;                                                    // the last reply, kept so a unit switch re-derives the hourly strip
    QTimer m_timer;
    QNetworkAccessManager *m_nam = nullptr;
    QNetworkReply *m_reply = nullptr;
    QObject *m_geoClient = nullptr;
    static constexpr int kRefreshMs = 30 * 60 * 1000;
};
