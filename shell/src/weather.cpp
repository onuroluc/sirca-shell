#include "weather.h"
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrlQuery>

Weather::Weather(QObject *parent) : QObject(parent)
{
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, &Weather::fetch);
}

void Weather::setStatus(const QString &s, const QString &error)
{
    if (s == m_status && error == m_error) return;
    m_status = s; m_error = error;
    Q_EMIT stateChanged();
}

QString Weather::cachePath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/weather.json");
}

void Weather::configure(const QVariantMap &config)
{
    const bool enabled = config.value(QStringLiteral("weather"), false).toBool();
    const QVariantMap loc = config.value(QStringLiteral("weatherLocation")).toMap();
    const QString units = config.value(QStringLiteral("weatherUnits"), QStringLiteral("c")).toString().toLower() == QLatin1String("f") ? QStringLiteral("f") : QStringLiteral("c");
    const bool hasLoc = loc.contains(QStringLiteral("lat")) && loc.contains(QStringLiteral("lon"));
    const double lat = loc.value(QStringLiteral("lat")).toDouble(), lon = loc.value(QStringLiteral("lon")).toDouble();
    const QString name = loc.value(QStringLiteral("name")).toString();
    const bool sameLoc = hasLoc == m_hasLocation && (!hasLoc || (qFuzzyCompare(lat, m_lat) && qFuzzyCompare(lon, m_lon)));
    if (enabled == m_enabled && sameLoc && units == m_units && name == m_name && m_status != QLatin1String("off")) return;
    const bool wasEnabled = m_enabled, unitsChanged = units != m_units, locChanged = !sameLoc;
    m_enabled = enabled; m_units = units; m_name = name;
    if (hasLoc) { m_hasLocation = true; m_lat = lat; m_lon = lon; }
    else if (locChanged) m_hasLocation = false;            // the config's location went away; GeoClue's (if any) is asked for again below
    if (!m_enabled) {
        m_timer.stop();
        if (m_reply) { m_reply->abort(); m_reply = nullptr; }
        setStatus(QStringLiteral("off"));
        Q_EMIT stateChanged();
        return;
    }
    if (!m_hasLocation && !hasLoc) loadCache();            // may carry GeoClue's coordinates from an earlier run
    if (!m_hasLocation) { setStatus(QStringLiteral("no-location")); if (!m_geoTried) askGeoClue(); Q_EMIT stateChanged(); return; }
    // fresh in the cache (same place, same units, < 30 min old): show it, fetch when it turns stale
    if ((!wasEnabled || locChanged || unitsChanged) && loadCache() && m_updated.isValid()) {
        const qint64 age = m_updated.msecsTo(QDateTime::currentDateTime());
        setStatus(QStringLiteral("ok"));
        m_timer.start(qMax<qint64>(1000, kRefreshMs - age));
        Q_EMIT stateChanged();
        return;
    }
    Q_EMIT stateChanged();
    fetch();
}

void Weather::refresh() { if (m_enabled && m_hasLocation) fetch(); }

void Weather::fetch()
{
    if (!m_enabled || !m_hasLocation) return;
    if (m_reply) return;                                   // one in flight is enough
    if (!m_nam) m_nam = new QNetworkAccessManager(this);
    QUrl url(QStringLiteral("https://api.open-meteo.com/v1/forecast"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("latitude"), QString::number(m_lat, 'f', 4));
    q.addQueryItem(QStringLiteral("longitude"), QString::number(m_lon, 'f', 4));
    q.addQueryItem(QStringLiteral("current"), QStringLiteral("temperature_2m,apparent_temperature,weather_code,is_day"));
    q.addQueryItem(QStringLiteral("hourly"), QStringLiteral("temperature_2m,weather_code,is_day"));
    q.addQueryItem(QStringLiteral("daily"), QStringLiteral("temperature_2m_max,temperature_2m_min"));
    q.addQueryItem(QStringLiteral("forecast_days"), QStringLiteral("2"));
    q.addQueryItem(QStringLiteral("timezone"), QStringLiteral("auto"));
    if (m_units == QLatin1String("f")) q.addQueryItem(QStringLiteral("temperature_unit"), QStringLiteral("fahrenheit"));
    url.setQuery(q);
    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", QCoreApplication::applicationName().toUtf8());
    req.setTransferTimeout(15000);
    setStatus(m_updated.isValid() ? QStringLiteral("ok") : QStringLiteral("loading"));
    m_reply = m_nam->get(req);
    connect(m_reply, &QNetworkReply::finished, this, [this] { QNetworkReply *r = m_reply; m_reply = nullptr; onReply(r); });
}

void Weather::onReply(QNetworkReply *r)
{
    r->deleteLater();
    if (r->error() != QNetworkReply::NoError) {
        qInfo("sirca-shell: weather: %s", qPrintable(r->errorString()));
        setStatus(m_updated.isValid() ? QStringLiteral("ok") : QStringLiteral("error"), r->errorString());
        m_timer.start(5 * 60 * 1000);                      // try again in five minutes, not thirty
        return;
    }
    const QVariantMap body = QJsonDocument::fromJson(r->readAll()).object().toVariantMap();
    if (!body.contains(QStringLiteral("current"))) { setStatus(m_updated.isValid() ? QStringLiteral("ok") : QStringLiteral("error"), QStringLiteral("unexpected reply")); m_timer.start(5 * 60 * 1000); return; }
    const QDateTime now = QDateTime::currentDateTime();
    apply(body, now);
    saveCache(body, now);
    setStatus(QStringLiteral("ok"));
    m_timer.start(kRefreshMs);
}

void Weather::apply(const QVariantMap &body, const QDateTime &fetched)
{
    m_body = body;
    const QVariantMap cur = body.value(QStringLiteral("current")).toMap();
    m_temp = cur.value(QStringLiteral("temperature_2m")).toDouble();
    m_feels = cur.value(QStringLiteral("apparent_temperature"), m_temp).toDouble();
    m_code = cur.value(QStringLiteral("weather_code"), -1).toInt();
    m_isDay = cur.value(QStringLiteral("is_day"), 1).toInt() != 0;
    const QVariantMap daily = body.value(QStringLiteral("daily")).toMap();
    m_max = daily.value(QStringLiteral("temperature_2m_max")).toList().value(0).toDouble();
    m_min = daily.value(QStringLiteral("temperature_2m_min")).toList().value(0).toDouble();
    // the next hours, from the hour we are in (the reply's times are the place's local time; the place is where the machine is)
    const QVariantMap hourly = body.value(QStringLiteral("hourly")).toMap();
    const QVariantList times = hourly.value(QStringLiteral("time")).toList(), temps = hourly.value(QStringLiteral("temperature_2m")).toList(),
                       codes = hourly.value(QStringLiteral("weather_code")).toList(), days = hourly.value(QStringLiteral("is_day")).toList();
    const QDateTime floorNow(QDateTime::currentDateTime().date(), QTime(QDateTime::currentDateTime().time().hour(), 0));
    m_hourly.clear();
    for (int i = 0; i < times.size() && m_hourly.size() < 8; ++i) {
        const QDateTime t = QDateTime::fromString(times.at(i).toString(), Qt::ISODate);
        if (!t.isValid() || t < floorNow.addSecs(3600)) continue;                    // the current hour is the big reading; the strip starts after it
        m_hourly << QVariantMap{{QStringLiteral("time"), t}, {QStringLiteral("temp"), temps.value(i).toDouble()}, {QStringLiteral("code"), codes.value(i).toInt()}, {QStringLiteral("isDay"), days.value(i, 1).toInt() != 0}};
    }
    m_updated = fetched;
    Q_EMIT dataChanged();
}

bool Weather::loadCache()
{
    QFile f(cachePath());
    if (!f.open(QIODevice::ReadOnly)) return false;
    const QVariantMap c = QJsonDocument::fromJson(f.readAll()).object().toVariantMap();
    // GeoClue's answer from an earlier run stands in for a missing config location
    if (!m_hasLocation && c.contains(QStringLiteral("geoLat"))) { m_hasLocation = true; m_lat = c.value(QStringLiteral("geoLat")).toDouble(); m_lon = c.value(QStringLiteral("geoLon")).toDouble(); if (m_name.isEmpty()) m_name = QStringLiteral("Current location"); }
    if (!m_hasLocation) return false;
    const bool same = qAbs(c.value(QStringLiteral("lat")).toDouble() - m_lat) < 0.001 && qAbs(c.value(QStringLiteral("lon")).toDouble() - m_lon) < 0.001 && c.value(QStringLiteral("units")).toString() == m_units;
    const QDateTime fetched = QDateTime::fromSecsSinceEpoch(c.value(QStringLiteral("fetched")).toLongLong());
    if (!same || !fetched.isValid() || fetched.msecsTo(QDateTime::currentDateTime()) > kRefreshMs || fetched > QDateTime::currentDateTime()) return false;
    const QVariantMap body = c.value(QStringLiteral("body")).toMap();
    if (!body.contains(QStringLiteral("current"))) return false;
    apply(body, fetched);
    return true;
}

void Weather::saveCache(const QVariantMap &body, const QDateTime &fetched) const
{
    QDir().mkpath(QFileInfo(cachePath()).path());
    QVariantMap c{{QStringLiteral("lat"), m_lat}, {QStringLiteral("lon"), m_lon}, {QStringLiteral("units"), m_units}, {QStringLiteral("fetched"), fetched.toSecsSinceEpoch()}, {QStringLiteral("body"), body}};
    // keep GeoClue's coordinates (they are not in the config) so the next start does not have to ask again
    QFile old(cachePath());
    if (old.open(QIODevice::ReadOnly)) { const QVariantMap o = QJsonDocument::fromJson(old.readAll()).object().toVariantMap(); if (o.contains(QStringLiteral("geoLat"))) { c.insert(QStringLiteral("geoLat"), o.value(QStringLiteral("geoLat"))); c.insert(QStringLiteral("geoLon"), o.value(QStringLiteral("geoLon"))); } }
    QSaveFile f(cachePath());
    if (!f.open(QIODevice::WriteOnly)) return;
    f.write(QJsonDocument(QJsonObject::fromVariantMap(c)).toJson(QJsonDocument::Compact));
    f.commit();
}

// GeoClue over the system bus, once per run: a client, city accuracy, the first LocationUpdated is the answer
void Weather::askGeoClue()
{
    m_geoTried = true;
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) return;
    const QString svc = QStringLiteral("org.freedesktop.GeoClue2");
    auto *w = new QDBusPendingCallWatcher(bus.asyncCall(QDBusMessage::createMethodCall(svc, QStringLiteral("/org/freedesktop/GeoClue2/Manager"), QStringLiteral("org.freedesktop.GeoClue2.Manager"), QStringLiteral("GetClient"))), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, svc](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusConnection bus = QDBusConnection::systemBus();
        const QDBusPendingReply<QDBusObjectPath> reply = *w;
        if (reply.isError()) { qInfo("sirca-shell: weather: GeoClue: %s", qPrintable(reply.error().message())); return; }
        const QString client = reply.value().path();
        auto *props = new QDBusInterface(svc, client, QStringLiteral("org.freedesktop.DBus.Properties"), bus, this);
        props->call(QStringLiteral("Set"), QStringLiteral("org.freedesktop.GeoClue2.Client"), QStringLiteral("DesktopId"), QVariant::fromValue(QDBusVariant(QStringLiteral("sirca-shell"))));
        props->call(QStringLiteral("Set"), QStringLiteral("org.freedesktop.GeoClue2.Client"), QStringLiteral("RequestedAccuracyLevel"), QVariant::fromValue(QDBusVariant(uint(4))));   // 4 = city
        props->deleteLater();
        auto *iface = new QDBusInterface(svc, client, QStringLiteral("org.freedesktop.GeoClue2.Client"), bus, this);
        m_geoClient = iface;
        bus.connect(svc, client, QStringLiteral("org.freedesktop.GeoClue2.Client"), QStringLiteral("LocationUpdated"), this, SLOT(geoLocation(QDBusObjectPath, QDBusObjectPath)));
        iface->asyncCall(QStringLiteral("Start"));
        QTimer::singleShot(25000, this, [this, iface] { if (m_geoClient == iface) { iface->asyncCall(QStringLiteral("Stop")); iface->deleteLater(); m_geoClient = nullptr; qInfo("sirca-shell: weather: GeoClue gave no location"); } });
    });
}

void Weather::geoLocation(const QDBusObjectPath &, const QDBusObjectPath &location)
{
    QDBusInterface loc(QStringLiteral("org.freedesktop.GeoClue2"), location.path(), QStringLiteral("org.freedesktop.GeoClue2.Location"), QDBusConnection::systemBus());
    const double lat = loc.property("Latitude").toDouble(), lon = loc.property("Longitude").toDouble();
    if (auto *iface = qobject_cast<QDBusInterface *>(m_geoClient)) { iface->asyncCall(QStringLiteral("Stop")); iface->deleteLater(); m_geoClient = nullptr; }
    if (qFuzzyIsNull(lat) && qFuzzyIsNull(lon)) return;
    m_hasLocation = true; m_lat = lat; m_lon = lon;
    if (m_name.isEmpty()) m_name = QStringLiteral("Current location");
    QDir().mkpath(QFileInfo(cachePath()).path());
    QVariantMap c; { QFile f(cachePath()); if (f.open(QIODevice::ReadOnly)) c = QJsonDocument::fromJson(f.readAll()).object().toVariantMap(); }
    c.insert(QStringLiteral("geoLat"), lat); c.insert(QStringLiteral("geoLon"), lon);
    QSaveFile f(cachePath()); if (f.open(QIODevice::WriteOnly)) { f.write(QJsonDocument(QJsonObject::fromVariantMap(c)).toJson(QJsonDocument::Compact)); f.commit(); }
    Q_EMIT stateChanged();
    if (m_enabled) fetch();
}

// WMO weather interpretation codes -> Breeze icon names / words
QString Weather::iconFor(int code, bool day) const
{
    const QString n = day ? QString() : QStringLiteral("-night");
    switch (code) {
    case 0: return day ? QStringLiteral("weather-clear") : QStringLiteral("weather-clear-night");
    case 1: return QStringLiteral("weather-few-clouds") + n;
    case 2: return QStringLiteral("weather-clouds") + n;
    case 3: return QStringLiteral("weather-overcast");
    case 45: case 48: return QStringLiteral("weather-fog");
    case 51: case 53: case 55: return QStringLiteral("weather-showers-scattered") + (day ? QStringLiteral("-day") : n);
    case 56: case 57: return QStringLiteral("weather-freezing-scattered-rain");
    case 61: case 63: return QStringLiteral("weather-showers") + (day ? QStringLiteral("-day") : n);
    case 65: return QStringLiteral("weather-showers");
    case 66: case 67: return QStringLiteral("weather-freezing-rain");
    case 71: case 73: return QStringLiteral("weather-snow-scattered") + (day ? QStringLiteral("-day") : n);
    case 75: case 77: return QStringLiteral("weather-snow");
    case 80: case 81: return QStringLiteral("weather-showers-scattered") + (day ? QStringLiteral("-day") : n);
    case 82: return QStringLiteral("weather-showers");
    case 85: case 86: return QStringLiteral("weather-snow-scattered") + (day ? QStringLiteral("-day") : n);
    case 95: return QStringLiteral("weather-storm") + (day ? QStringLiteral("-day") : n);
    case 96: case 99: return QStringLiteral("weather-hail");
    default: return QStringLiteral("weather-none-available");
    }
}

QString Weather::describe(int code) const
{
    switch (code) {
    case 0: return QStringLiteral("Clear");
    case 1: return QStringLiteral("Mostly clear");
    case 2: return QStringLiteral("Partly cloudy");
    case 3: return QStringLiteral("Overcast");
    case 45: case 48: return QStringLiteral("Fog");
    case 51: case 53: case 55: return QStringLiteral("Drizzle");
    case 56: case 57: return QStringLiteral("Freezing drizzle");
    case 61: return QStringLiteral("Light rain");
    case 63: return QStringLiteral("Rain");
    case 65: return QStringLiteral("Heavy rain");
    case 66: case 67: return QStringLiteral("Freezing rain");
    case 71: return QStringLiteral("Light snow");
    case 73: return QStringLiteral("Snow");
    case 75: return QStringLiteral("Heavy snow");
    case 77: return QStringLiteral("Snow grains");
    case 80: case 81: return QStringLiteral("Showers");
    case 82: return QStringLiteral("Heavy showers");
    case 85: case 86: return QStringLiteral("Snow showers");
    case 95: return QStringLiteral("Thunderstorm");
    case 96: case 99: return QStringLiteral("Thunderstorm, hail");
    default: return QString();
    }
}

// A place name to coordinates, for the settings page: the same provider, no key. Six hits, English names.
void Weather::searchPlace(const QString &name)
{
    const QString q = name.trimmed();
    if (q.size() < 2) { Q_EMIT placesFound({}); return; }
    if (!m_nam) m_nam = new QNetworkAccessManager(this);
    QUrl url(QStringLiteral("https://geocoding-api.open-meteo.com/v1/search"));
    QUrlQuery query; query.addQueryItem(QStringLiteral("name"), q); query.addQueryItem(QStringLiteral("count"), QStringLiteral("6")); query.addQueryItem(QStringLiteral("language"), QStringLiteral("en")); query.addQueryItem(QStringLiteral("format"), QStringLiteral("json"));
    url.setQuery(query);
    QNetworkRequest req(url); req.setTransferTimeout(8000);
    QNetworkReply *r = m_nam->get(req);
    connect(r, &QNetworkReply::finished, this, [this, r] {
        r->deleteLater();
        QVariantList out;
        if (r->error() == QNetworkReply::NoError) {
            const QJsonArray hits = QJsonDocument::fromJson(r->readAll()).object().value(QLatin1String("results")).toArray();
            for (const QJsonValue &v : hits) { const QJsonObject o = v.toObject();
                out.push_back(QVariantMap{ {QStringLiteral("name"), o.value(QLatin1String("name")).toString()}, {QStringLiteral("region"), o.value(QLatin1String("admin1")).toString()},
                                           {QStringLiteral("country"), o.value(QLatin1String("country")).toString()}, {QStringLiteral("lat"), o.value(QLatin1String("latitude")).toDouble()}, {QStringLiteral("lon"), o.value(QLatin1String("longitude")).toDouble()} }); }
        }
        Q_EMIT placesFound(out);
    });
}
