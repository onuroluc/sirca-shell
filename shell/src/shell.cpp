#include "shell.h"
#include <QJSValue>
#include "shellcorona.h"
#include "osdservice.h"
#include <KGlobalAccel>
#include <QAction>
#include <QDBusArgument>
#include <QJsonArray>
#include <KWindowEffects>
#include <KWindowSystem>
#include <KWayland/Client/connection_thread.h>
#include <KWayland/Client/fakeinput.h>
#include <KWayland/Client/registry.h>
#include <LayerShellQt/Window>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusServiceWatcher>
#include <QDBusMessage>
#include <QDBusReply>
#include <QSet>
#include <QSysInfo>
#include <QUrlQuery>
#include <QDBusInterface>
#include <QDBusVariant>
#include <QDir>
#include <QProcess>
#include <QFile>
#include <QGuiApplication>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QDir>
#include <QScreen>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <KConfigGroup>
#include <KSharedConfig>
#include <QElapsedTimer>
#include <QSaveFile>
#include <QScopeGuard>
#include <QPainterPath>
#include <QRegion>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QDebug>


// ---- the shell's own global shortcuts ---------------------------------------------------------------------------------
// Keys are owned by Sirca Shell (component "sirca-shell" in kglobalaccel), not by KWin's key bindings. `kwin` names the
// window-manager action that carries a window operation out (invoked directly over D-Bus); empty = handled in QML.
// `owner`/`ownerAction` say who gets the key back when the shell is switched off.
struct GlassShortcut { const char *id; const char *text; const char *key; const char *kwin; const char *owner; const char *ownerAction; };
static const GlassShortcut kShortcuts[] = {
    {"show-desktop",   "Show Desktop",             "Meta+D",        "",                        "kwin", "Show Desktop"},
    {"win-maximize",   "Maximize Window",          "Meta+Up",       "Window Maximize",         "kwin", "Window Maximize"},
    {"win-maximize2",  "Maximize Window",          "Meta+PgUp",     "Window Maximize",         "kwin", "Window Maximize"},
    {"win-minimize",   "Minimize Window",          "Meta+Down",     "Window Minimize",         "kwin", "Window Minimize"},
    {"win-tile-left",  "Tile Window Left",         "Meta+Left",     "Window Quick Tile Left",  "kwin", "Window Quick Tile Left"},
    {"win-tile-right", "Tile Window Right",        "Meta+Right",    "Window Quick Tile Right", "kwin", "Window Quick Tile Right"},
    {"win-close",      "Close Window",             "Alt+F4",        "Window Close",            "kwin", "Window Close"},
    {"win-menu",       "Window Menu",              "Alt+F3",        "Window Operations Menu",  "kwin", "Window Operations Menu"},
    {"win-kill",       "Kill Window",              "Meta+Ctrl+Esc", "Kill Window",             "kwin", "Kill Window"},
    {"overview",       "Overview",                 "Meta+W",        "Overview",                "kwin", "Overview"},
    {"grid-view",      "All Windows Grid",         "Meta+G",        "Grid View",               "kwin", "Grid View"},
    {"zoom-in",        "Zoom In",                  "Meta+=",        "view_zoom_in",            "kwin", "view_zoom_in"},
    {"zoom-out",       "Zoom Out",                 "Meta+-",        "view_zoom_out",           "kwin", "view_zoom_out"},
    {"power",          "Power Menu",               "Ctrl+Alt+Del",  "",                        "ksmserver", "Log Out"},            // Plasma's logout screen key, handed back on exit
    {"screenshot",     "Screenshot",               "Print",         "",                        "org.kde.spectacle.desktop", "_launch"},   // Spectacle keeps Meta+Shift+S and gets Print back on exit
    {"record",         "Record Screen",            "Meta+Shift+R",  "",                        "org.kde.spectacle.desktop", "RecordRegion"},   // handed back on exit
    {"screenshot-2",   "Screenshot",               "Meta+Shift+S",  "",                        "org.kde.spectacle.desktop", "_launch"},   // for keyboards without a Print key
    {"tiles",          "Tile Picker",              "Meta+A",        "",                        "plasmashell", "next activity"},      // handed back on exit
    {"clipboard",      "Clipboard History",        "Meta+V",        "",                        "plasmashell", "show-on-mouse-pos"},   // Klipper's key, handed back on exit
    {"search",         "Search",                   "Meta+Space",    "",                        "",     ""},          // ours alone: nothing to hand back
    {"cheatsheet",     "Shortcut Cheat Sheet",     "Meta+/",        "",                        "",     ""},          // ours alone
    {"notif-clear",    "Clear Notifications",      "Meta+Shift+N",  "",                        "",     ""},          // ours alone
    {"dock-1", "Dock Entry 1", "Meta+1", "", "plasmashell", "activate task manager entry 1"},
    {"dock-2", "Dock Entry 2", "Meta+2", "", "plasmashell", "activate task manager entry 2"},
    {"dock-3", "Dock Entry 3", "Meta+3", "", "plasmashell", "activate task manager entry 3"},
    {"dock-4", "Dock Entry 4", "Meta+4", "", "plasmashell", "activate task manager entry 4"},
    {"dock-5", "Dock Entry 5", "Meta+5", "", "plasmashell", "activate task manager entry 5"},
    {"dock-6", "Dock Entry 6", "Meta+6", "", "plasmashell", "activate task manager entry 6"},
    {"dock-7", "Dock Entry 7", "Meta+7", "", "plasmashell", "activate task manager entry 7"},
    {"dock-8", "Dock Entry 8", "Meta+8", "", "plasmashell", "activate task manager entry 8"},
    {"dock-9", "Dock Entry 9", "Meta+9", "", "plasmashell", "activate task manager entry 9"},
};

QList<QKeySequence> Shell::launcherKeys()
{
    // "Meta" must come from the string: QKeySequence(Qt::META) serialises empty and kglobalaccel ignores it
    return {QKeySequence::fromString(QStringLiteral("Meta")), QKeySequence(Qt::ALT | Qt::Key_F1)};
}

QAction *Shell::launcherAction(QObject *parent)
{
    auto *a = new QAction(parent);
    a->setObjectName(QStringLiteral("toggle-launcher"));
    a->setText(QStringLiteral("Toggle Application Launcher"));
    a->setProperty("componentName", QStringLiteral("sirca-shell"));
    a->setProperty("componentDisplayName", QStringLiteral("Sirca Shell"));
    return a;
}

void Shell::releaseLauncherKey()
{
    QAction *mine = launcherAction(nullptr);
    KGlobalAccel::self()->setShortcut(mine, {}, KGlobalAccel::NoAutoloading);
    KGlobalAccel::self()->removeAllShortcuts(mine);
    // write the keys back onto plasmashell's launcher action; its Kickoff picks them up when plasmashell next starts
    auto *theirs = new QAction;
    theirs->setObjectName(QStringLiteral("activate application launcher"));
    theirs->setText(QStringLiteral("Activate Application Launcher"));
    theirs->setProperty("componentName", QStringLiteral("plasmashell"));
    theirs->setProperty("componentDisplayName", QStringLiteral("plasmashell"));
    for (const QKeySequence &k : launcherKeys()) KGlobalAccel::stealShortcutSystemwide(k);
    KGlobalAccel::self()->setShortcut(theirs, launcherKeys(), KGlobalAccel::NoAutoloading);
    // every key of our own set goes back to the action that had it
    for (const GlassShortcut &g : kShortcuts) {
        QAction mine; mine.setObjectName(QString::fromLatin1(g.id)); mine.setProperty("componentName", QStringLiteral("sirca-shell"));
        KGlobalAccel::self()->setShortcut(&mine, {}, KGlobalAccel::NoAutoloading); KGlobalAccel::self()->removeAllShortcuts(&mine);
        if (!*g.owner) continue;                                     // a key nobody had before us
        auto *theirs2 = new QAction; theirs2->setObjectName(QString::fromLatin1(g.ownerAction)); theirs2->setText(QString::fromLatin1(g.ownerAction));
        theirs2->setProperty("componentName", QString::fromLatin1(g.owner));
        const QKeySequence key = QKeySequence::fromString(QString::fromLatin1(g.key));
        KGlobalAccel::stealShortcutSystemwide(key);
        QList<QKeySequence> keys = KGlobalAccel::self()->shortcut(theirs2); if (!keys.contains(key)) keys << key;
        KGlobalAccel::self()->setShortcut(theirs2, keys, KGlobalAccel::NoAutoloading);
    }
    // and Alt+Tab back to KWin's switcher
    const QList<QPair<QString, QKeySequence>> kwinKeys{{QStringLiteral("Walk Through Windows"), QKeySequence(Qt::ALT | Qt::Key_Tab)}, {QStringLiteral("Walk Through Windows (Reverse)"), QKeySequence::fromString(QStringLiteral("Alt+Shift+Tab"))}};
    for (const auto &k : kwinKeys) {
        for (const char *mine : {"switch-windows", "switch-windows-reverse"}) { QAction m; m.setObjectName(QString::fromLatin1(mine)); m.setProperty("componentName", QStringLiteral("sirca-shell")); KGlobalAccel::self()->setShortcut(&m, {}, KGlobalAccel::NoAutoloading); KGlobalAccel::self()->removeAllShortcuts(&m); }
        auto *a = new QAction; a->setObjectName(k.first); a->setText(k.first);
        a->setProperty("componentName", QStringLiteral("kwin")); a->setProperty("componentDisplayName", QStringLiteral("KWin"));
        KGlobalAccel::stealShortcutSystemwide(k.second);
        KGlobalAccel::self()->setShortcut(a, {QKeySequence(Qt::META | Qt::Key_Tab), k.second}, KGlobalAccel::NoAutoloading);
    }
}

Shell::Shell(QObject *parent) : QObject(parent)
{
    const qint64 ctorStart = msSinceStart();
    auto ctorDone = qScopeGuard([ctorStart] { qInfo("sirca-shell: start-up: Shell singleton built in %lld ms (at %lld ms)", msSinceStart() - ctorStart, ctorStart); });
    QTimer::singleShot(0, this, [this] { initFakeInput(); });
    watchConfig();
    for (auto sig : {&QGuiApplication::screenAdded, &QGuiApplication::screenRemoved}) connect(qApp, sig, this, [this](QScreen *) { Q_EMIT primaryScreenChanged(); });
    connect(qApp, &QGuiApplication::primaryScreenChanged, this, [this](QScreen *) { Q_EMIT primaryScreenChanged(); });
    connect(this, &Shell::configRevisionChanged, this, &Shell::primaryScreenChanged);
    {   // follow org.kde.plasmashell coming and going
        auto bus = QDBusConnection::sessionBus();
        const QString name = QStringLiteral("org.kde.plasmashell");
        // "running" = somebody ELSE owns the name (in without-plasmashell mode we own it ourselves for the OSD service)
        const QString me = bus.baseService();
        const QString owner = bus.interface() ? bus.interface()->serviceOwner(name).value() : QString();
        m_plasmaRunning = !owner.isEmpty() && owner != me;
        auto *w = new QDBusServiceWatcher(name, bus, QDBusServiceWatcher::WatchForOwnerChange, this);
        connect(w, &QDBusServiceWatcher::serviceOwnerChanged, this, [this, me](const QString &, const QString &, const QString &newOwner) {
            const bool on = !newOwner.isEmpty() && newOwner != me; if (on != m_plasmaRunning) { m_plasmaRunning = on; Q_EMIT plasmaRunningChanged(); }
            updateOsdClaim(); });
        m_osd = new OsdService(this);
        connect(m_osd, &OsdService::osdProgress, this, [this](const QString &icon, int percent, int max, const QString &text) { Q_EMIT dbusSignal(QStringLiteral("org.kde.osdService"), QStringLiteral("osdProgress"), {icon, percent, max, text}); });
        connect(m_osd, &OsdService::osdText, this, [this](const QString &icon, const QString &text) { Q_EMIT dbusSignal(QStringLiteral("org.kde.osdService"), QStringLiteral("osdText"), {icon, text}); });
    }

    (void)KWindowSystem::showingDesktop();   // prime KWindowSystem's Wayland connection early
    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QStringLiteral("onur.SircaShell"))) qWarning() << "sirca-shell: D-Bus name onur.SircaShell is taken (second instance?)";
    else bus.registerObject(QStringLiteral("/SircaShell"), this, QDBusConnection::ExportScriptableSlots);
    // Super / Alt+F1: on Plasma 6 the bare Meta tap is a KGlobalAccel shortcut owned by plasmashell's launcher widget,
    // which is gone once our dock replaces the panels. Only taken with --own-launcher-key (the service passes it), so a
    // hand-started test instance never steals Super from Plasma; `sirca-shell --release-launcher-key` hands it back.
    if (QCoreApplication::arguments().contains(QStringLiteral("--own-launcher-key"))) {
        auto *a = launcherAction(this);
        const QList<QKeySequence> keys = launcherKeys();
        // always steal: the availability check reports a bare modifier as free, after which setShortcut silently drops it
        for (const QKeySequence &k : keys) KGlobalAccel::stealShortcutSystemwide(k);
        KGlobalAccel::self()->setShortcut(a, keys, KGlobalAccel::NoAutoloading);
        connect(a, &QAction::triggered, this, &Shell::launcherToggleRequested);
        // Our own Alt+Tab (KWin's switcher went missing on this machine, and ours matches the glass anyway)
        auto addSwitch = [this](const char *id, const QString &text, const QKeySequence &key, bool reverse) {
            auto *act = new QAction(this);
            act->setObjectName(QString::fromLatin1(id)); act->setText(text);
            act->setProperty("componentName", QStringLiteral("sirca-shell")); act->setProperty("componentDisplayName", QStringLiteral("Sirca Shell"));
            KGlobalAccel::stealShortcutSystemwide(key);
            KGlobalAccel::self()->setShortcut(act, {key}, KGlobalAccel::NoAutoloading);
            connect(act, &QAction::triggered, this, [this, reverse] { Q_EMIT switcherRequested(reverse); });
        };
        for (const GlassShortcut &g : kShortcuts) {
            auto *act = new QAction(this);
            act->setObjectName(QString::fromLatin1(g.id)); act->setText(QString::fromLatin1(g.text));
            act->setProperty("componentName", QStringLiteral("sirca-shell")); act->setProperty("componentDisplayName", QStringLiteral("Sirca Shell"));
            const QKeySequence key = QKeySequence::fromString(QString::fromLatin1(g.key));
            KGlobalAccel::stealShortcutSystemwide(key);
            KGlobalAccel::self()->setShortcut(act, {key}, KGlobalAccel::NoAutoloading);
            const QString id = QString::fromLatin1(g.id), kwin = QString::fromLatin1(g.kwin);
            connect(act, &QAction::triggered, this, [this, id, kwin] {
                if (!kwin.isEmpty()) {   // a window operation: the window manager performs it, asked directly (not through its key bindings)
                    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/kwin"), QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("invokeShortcut"));
                    m.setArguments({kwin}); QDBusConnection::sessionBus().call(m, QDBus::NoBlock);
                }
                Q_EMIT shortcutActivated(id);
            });
        }
        addSwitch("switch-windows", QStringLiteral("Switch Windows"), QKeySequence(Qt::ALT | Qt::Key_Tab), false);
        addSwitch("switch-windows-reverse", QStringLiteral("Switch Windows (Reverse)"), QKeySequence::fromString(QStringLiteral("Alt+Shift+Tab")), true);   // (Alt|Shift|Backtab serialises empty)
    }
}

void Shell::setupLayer(QQuickWindow *window, const QString &edge, int exclusiveZone, const QString &scope)
{
    if (!window) return;
    auto *lw = LayerShellQt::Window::get(window);
    lw->setLayer(LayerShellQt::Window::LayerTop);
    lw->setScope(scope);
    lw->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    lw->setAnchors(edge == QLatin1String("bottom") ? LayerShellQt::Window::AnchorBottom : LayerShellQt::Window::AnchorTop);
    lw->setExclusiveZone(exclusiveZone);
    lw->setScreen(window->screen());              // multi-screen: the QML sets Window.screen before it shows (default: the primary)
    ShellCorona::rememberStrut(edge == QLatin1String("bottom"), exclusiveZone);   // no corona is created for this
}

void Shell::setExclusiveZone(QQuickWindow *window, int zone)
{
    if (window) LayerShellQt::Window::get(window)->setExclusiveZone(zone);
}

void Shell::setKeyboardExclusive(QQuickWindow *window, bool exclusive)
{
    if (!window) return;
    LayerShellQt::Window::get(window)->setKeyboardInteractivity(exclusive ? LayerShellQt::Window::KeyboardInteractivityExclusive : LayerShellQt::Window::KeyboardInteractivityOnDemand);
    window->requestUpdate();
}

void Shell::setKeyboardMode(QQuickWindow *window, const QString &mode)
{
    if (!window) return;
    using W = LayerShellQt::Window;
    W::get(window)->setKeyboardInteractivity(mode == QLatin1String("none") ? W::KeyboardInteractivityNone : mode == QLatin1String("exclusive") ? W::KeyboardInteractivityExclusive : W::KeyboardInteractivityOnDemand);
    window->requestUpdate();
}

static QRegion regionFor(const QVariantList &rects)
{
    QRegion region;
    for (const QVariant &v : rects) {
        const QVariantMap m = v.toMap();
        const QRectF r(m.value("x").toReal(), m.value("y").toReal(), m.value("w").toReal(), m.value("h").toReal());
        if (r.isEmpty()) continue;
        QPainterPath p;
        p.addRoundedRect(r, m.value("r").toReal(), m.value("r").toReal());
        region |= QRegion(p.toFillPolygon().toPolygon());
    }
    return region;
}

void Shell::setShape(QQuickWindow *window, const QVariantList &rects)
{
    if (!window) return;
    const QRegion region = regionFor(rects);
    KWindowEffects::enableBlurBehind(window, !region.isEmpty(), region);
    window->setMask(region);
}

void Shell::setSceneRegions(QQuickWindow *window, const QVariantList &panels, const QVariantList &holes)
{
    if (!window) return;
    const QRegion glass = regionFor(panels);
    KWindowEffects::enableBlurBehind(window, !glass.isEmpty(), glass);
    QRegion mask(0, 0, window->width(), window->height());
    for (const QVariant &h : holes) { const QVariantMap m = h.toMap(); mask -= QRect(qRound(m.value(QStringLiteral("x")).toReal()), qRound(m.value(QStringLiteral("y")).toReal()), qRound(m.value(QStringLiteral("w")).toReal()), qRound(m.value(QStringLiteral("h")).toReal())); }
    window->setMask(mask);
}

QVariant Shell::dbusCall(const QString &service, const QString &path, const QString &iface, const QString &method, const QVariantList &args)
{
    // a plain message, not a QDBusInterface: that one introspects the object first (a second round trip, blocking too), and
    // a service that is busy or gone must not hold the shell for the default 25 s
    QDBusMessage m = QDBusMessage::createMethodCall(service, path, iface, method);
    m.setArguments(args);
    const QDBusMessage reply = QDBusConnection::sessionBus().call(m, QDBus::Block, 500);
    if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) return {};
    const QVariant first = reply.arguments().first();
    if (first.userType() == qMetaTypeId<QDBusVariant>()) return first.value<QDBusVariant>().variant();   // Properties.Get
    return first;
}

void Shell::dbusSend(const QString &service, const QString &path, const QString &iface, const QString &method, const QVariantList &args)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, method);
    msg.setArguments(args);
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void Shell::dbusSendTyped(const QString &service, const QString &path, const QString &iface, const QString &method, const QString &signature, const QVariantList &args)
{
    QVariantList typed;
    for (int i = 0; i < args.size() && i < signature.size(); ++i) {
        const QChar t = signature.at(i);
        if (t == QLatin1Char('i')) typed << QVariant(qRound(args.at(i).toDouble()));
        else if (t == QLatin1Char('d')) typed << QVariant(args.at(i).toDouble());
        else if (t == QLatin1Char('s')) typed << QVariant(args.at(i).toString());
        else if (t == QLatin1Char('b')) typed << QVariant(args.at(i).toBool());
        else if (t == QLatin1Char('S')) typed << QVariant(args.at(i).toStringList());   // 'as'
        else typed << args.at(i);
    }
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, method);
    msg.setArguments(typed);
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

QString Shell::configPath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/sirca-shell/config.json");
}

QVariantMap Shell::loadConfig() const
{
    QFile f(configPath());
    if (!f.open(QIODevice::ReadOnly)) return {};
    return QJsonDocument::fromJson(f.readAll()).object().toVariantMap();
}

void Shell::setShapePolygon(QQuickWindow *window, const QVariantList &points, const QVariantList &maskExtra, bool blur)
{
    if (!window) return;
    QPolygon poly;
    for (int i = 0; i + 1 < points.size(); i += 2)
        poly << QPoint(qRound(points.at(i).toReal()), qRound(points.at(i + 1).toReal()));
    const QRegion region = poly.size() >= 3 ? QRegion(poly) : QRegion();
    KWindowEffects::enableBlurBehind(window, blur && !region.isEmpty(), blur ? region : QRegion());   // blur off: the shape still takes input
    QRegion mask = region;
    for (int i = 0; i + 3 < maskExtra.size(); i += 4)
        mask |= QRect(qRound(maskExtra.at(i).toReal()), qRound(maskExtra.at(i + 1).toReal()), qRound(maskExtra.at(i + 2).toReal()), qRound(maskExtra.at(i + 3).toReal()));
    if (mask.isEmpty()) mask = QRegion(0, 0, 1, 1);   // an empty mask would mean "the whole window takes input"
    window->setMask(mask);
}

QJsonObject Shell::readConfigObject() const
{
    QFile f(configPath());
    if (f.open(QIODevice::ReadOnly)) return QJsonDocument::fromJson(f.readAll()).object();
    return {};
}

// Every write of config.json goes through here: a QSaveFile writes next to it and renames over it, so a reader (the
// shell itself through its watcher, glass-mode, a hand-started settings window) never sees a half-written file. The
// revision is bumped right away; the watcher's own notifications for this write are ignored (see watchConfig).
void Shell::writeConfigObject(const QJsonObject &o)
{
    QDir().mkpath(QFileInfo(configPath()).absolutePath());
    QSaveFile f(configPath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) { qWarning("sirca-shell: cannot write %s", qPrintable(configPath())); return; }
    const QByteArray bytes = QJsonDocument(o).toJson();
    f.write(bytes);
    m_ownConfigBytes = bytes;
    if (!f.commit()) { qWarning("sirca-shell: cannot replace %s", qPrintable(configPath())); return; }
    // announced from the event loop, not from inside the caller (a QML handler that has just written a key must not have
    // every Config binding re-evaluated under its feet; the watcher route used to arrive 30 ms later)
    QTimer::singleShot(0, this, [this] { ++m_configRevision; Q_EMIT configRevisionChanged(); });
}

// A JS array or object reaches a QVariant parameter wrapped as a QJSValue, which QJsonValue::fromVariant turns into null
// (Quick settings' tile list was written as null, 2026-09-23): unwrap it first.
static QJsonValue jsonFrom(const QVariant &v)
{
    if (v.userType() == qMetaTypeId<QJSValue>()) return QJsonValue::fromVariant(v.value<QJSValue>().toVariant());
    return QJsonValue::fromVariant(v);
}

void Shell::saveConfigKeys(const QVariantMap &values)
{
    QJsonObject o = readConfigObject();
    for (auto it = values.begin(); it != values.end(); ++it) o.insert(it.key(), jsonFrom(it.value()));
    writeConfigObject(o);
}

void Shell::removeConfigKeys(const QStringList &keys)
{
    QJsonObject o = readConfigObject();
    for (const QString &k : keys) o.remove(k);
    writeConfigObject(o);
}

QVariantMap Shell::sysStats()
{
    QVariantMap out{{QStringLiteral("cpu"), 0.0}, {QStringLiteral("mem"), 0.0}};
    { QFile f(QStringLiteral("/proc/stat"));
      if (f.open(QIODevice::ReadOnly)) { const QList<QByteArray> p = f.readLine().simplified().split(' ');     // cpu user nice system idle iowait irq softirq steal
        quint64 total = 0, idle = 0; for (int i = 1; i < p.size() && i <= 8; ++i) { const quint64 v = p.at(i).toULongLong(); total += v; if (i == 4 || i == 5) idle += v; }
        if (m_cpuTotal && total > m_cpuTotal) out[QStringLiteral("cpu")] = 1.0 - double(idle - m_cpuIdle) / double(total - m_cpuTotal);
        m_cpuTotal = total; m_cpuIdle = idle; } }
    { QFile f(QStringLiteral("/proc/meminfo"));
      if (f.open(QIODevice::ReadOnly)) { double tot = 0, avail = 0;
        for (int i = 0; i < 6; ++i) { const QByteArray l = f.readLine(); if (l.startsWith("MemTotal:")) tot = l.mid(9).simplified().split(' ').first().toDouble(); else if (l.startsWith("MemAvailable:")) avail = l.mid(13).simplified().split(' ').first().toDouble(); }
        if (tot > 0) out[QStringLiteral("mem")] = 1.0 - avail / tot; } }
    return out;
}

void Shell::saveConfigKey(const QString &key, const QVariant &value)
{
    QJsonObject o = readConfigObject();
    o.insert(key, jsonFrom(value));
    writeConfigObject(o);
}

void Shell::dbusListen(const QString &service, const QString &path, const QString &iface, const QString &signal)
{
    QDBusConnection::sessionBus().connect(service, path, iface, signal, this, SLOT(onDbusSignal(QDBusMessage)));
}

void Shell::onDbusSignal(const QDBusMessage &msg)
{
    QVariantList out;
    for (const QVariant &v : msg.arguments()) {
        if (v.userType() == qMetaTypeId<QDBusArgument>()) {
            const auto a = v.value<QDBusArgument>();
            if (a.currentType() == QDBusArgument::MapType) { QVariantMap m; a >> m; out << m; }
            else out << QVariant();
        } else out << v;
    }
    Q_EMIT dbusSignal(msg.interface(), msg.member(), out);
}

QQuickItem *Shell::appletItem(const QString &plugin)
{
    return ShellCorona::exists() ? ShellCorona::self()->findItem(plugin) : nullptr;      // asking must not start the hosting layer
}

void Shell::setShowingDesktop(bool showing)
{
    // KWindowSystem binds the plasma window-management global lazily: the very first request can be dropped while it
    // connects. Ask, then check shortly after and ask once more if nothing changed.
    KWindowSystem::setShowingDesktop(showing);
    QTimer::singleShot(300, this, [showing] { if (KWindowSystem::showingDesktop() != showing) KWindowSystem::setShowingDesktop(showing); });
}

QString Shell::defaultTerminal() const
{
    const QString cfg = KSharedConfig::openConfig(QStringLiteral("kdeglobals"))->group(QStringLiteral("General")).readEntry("TerminalApplication", QString());
    if (!cfg.isEmpty() && !QStandardPaths::findExecutable(cfg.section(QLatin1Char(' '), 0, 0)).isEmpty()) return cfg.section(QLatin1Char(' '), 0, 0);
    for (const char *t : {"ghostty", "konsole", "kitty", "alacritty", "foot", "gnome-terminal", "xterm"}) if (!QStandardPaths::findExecutable(QString::fromLatin1(t)).isEmpty()) return QString::fromLatin1(t);
    return QStringLiteral("xterm");
}

void Shell::setupWallpaper(QQuickWindow *window, bool takesInput)
{
    if (!window) return;
    using W = LayerShellQt::Window;
    auto *lw = W::get(window);
    lw->setLayer(W::LayerBackground);
    lw->setScope(QStringLiteral("sirca-shell-wallpaper"));
    lw->setKeyboardInteractivity(W::KeyboardInteractivityNone);
    lw->setAnchors(W::Anchors(W::AnchorTop | W::AnchorBottom | W::AnchorLeft | W::AnchorRight));
    lw->setScreen(window->screen());              // one wallpaper per screen
    lw->setExclusiveZone(-1);
    if (takesInput) window->setMask(QRegion());                       // the desktop: right click menu, a click closes popups
    else window->setMask(QRegion(0, 0, 1, 1));                        // only a picture: clicks reach what is below
}

QString Shell::plasmaWallpaper() const
{
    // the last Image= of Plasma's desktop containments is the one for the current activity on a single screen
    QFile f(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/plasma-org.kde.plasma.desktop-appletsrc"));
    QString found;
    if (f.open(QIODevice::ReadOnly)) {
        const QList<QByteArray> lines = f.readAll().split('\n');
        for (const QByteArray &l : lines) if (l.startsWith("Image=")) found = QString::fromUtf8(l.mid(6)).trimmed();
    }
    if (found.startsWith(QLatin1String("file://"))) found = QUrl(found).toLocalFile();
    return QFileInfo::exists(found) ? found : QString();
}

QStringList Shell::wallpaperFiles(const QString &folder) const
{
    QStringList out;
    const QStringList filters{QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.png"), QStringLiteral("*.webp")};
    QDir top(folder);
    for (const QFileInfo &fi : top.entryInfoList(filters, QDir::Files, QDir::Name)) out << fi.absoluteFilePath();
    for (const QFileInfo &sub : top.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        if (sub.fileName().startsWith(QLatin1String("originals"))) continue;                    // source files of generated sets
        for (const QFileInfo &fi : QDir(sub.absoluteFilePath()).entryInfoList(filters, QDir::Files, QDir::Name)) out << fi.absoluteFilePath();
    }
    return out;
}

void Shell::setupCatcher(QQuickWindow *window)
{
    if (!window) return;
    using W = LayerShellQt::Window;
    auto *lw = W::get(window);
    lw->setLayer(W::LayerTop);
    lw->setScope(QStringLiteral("sirca-shell-catcher"));          // not "dock": KWin must not type it as a panel
    lw->setKeyboardInteractivity(W::KeyboardInteractivityNone);
    lw->setAnchors(W::Anchors(W::AnchorTop | W::AnchorBottom | W::AnchorLeft | W::AnchorRight));
    lw->setExclusiveZone(-1);                                       // cover the whole output, ignore everyone's struts
}

void Shell::setCatcherHoles(QQuickWindow *window, const QVariantList &holes)
{
    if (!window) return;
    QRegion region(QRect(QPoint(0, 0), window->size()));
    for (int i = 0; i + 3 < holes.size(); i += 4)
        region -= QRect(qRound(holes.at(i).toReal()), qRound(holes.at(i + 1).toReal()), qRound(holes.at(i + 2).toReal()), qRound(holes.at(i + 3).toReal()));
    window->setMask(region);
    window->requestUpdate();
}

void Shell::setupSwitcher(QQuickWindow *window)
{
    if (!window) return;
    using W = LayerShellQt::Window;
    auto *lw = W::get(window);
    lw->setLayer(W::LayerOverlay);
    lw->setScope(QStringLiteral("dock"));                          // "dock" = the Glass effect gives it the panel treatment
    lw->setKeyboardInteractivity(W::KeyboardInteractivityExclusive);
    lw->setAnchors(W::Anchors());                                  // no anchors: the compositor centres it
    lw->setExclusiveZone(-1);
}

void Shell::setupSearch(QQuickWindow *window)
{
    if (!window) return;
    using W = LayerShellQt::Window;
    auto *lw = W::get(window);
    lw->setLayer(W::LayerOverlay);
    lw->setScope(QStringLiteral("dock"));
    lw->setKeyboardInteractivity(W::KeyboardInteractivityExclusive);
    lw->setAnchors(W::Anchors(W::AnchorTop | W::AnchorBottom | W::AnchorLeft | W::AnchorRight));
    lw->setExclusiveZone(-1);
}

bool Shell::hasProgram(const QString &name) const { return !QStandardPaths::findExecutable(name).isEmpty(); }

bool Shell::kwinHasAction(const QString &action) const
{
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/kwin"), QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("shortcutNames"));
    const QDBusReply<QStringList> r = QDBusConnection::sessionBus().call(m, QDBus::Block, 500);
    return r.isValid() && r.value().contains(action);
}

void Shell::tileActiveWindow(double xFraction, double widthFraction)
{
    // KWin moves windows for scripts, not for clients: write a three-line script, run it once, unload it
    const QString name = QStringLiteral("sirca-shell-tile");
    const QString file = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/sirca-shell-tile.js");
    { QFile f(file); if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) return;
      f.write(QStringLiteral("const w = workspace.activeWindow;\n"
                             "if (w && w.normalWindow && w.moveable && w.resizeable) {\n"
                             "  const a = workspace.clientArea(KWin.MaximizeArea, w);\n"
                             "  w.setMaximize(false, false);\n"
                             "  w.frameGeometry = { x: Math.round(a.x + a.width * %1), y: a.y, width: Math.round(a.width * %2), height: a.height };\n"
                             "}\n").arg(xFraction, 0, 'f', 5).arg(widthFraction, 0, 'f', 5).toUtf8()); }
    QDBusConnection bus = QDBusConnection::sessionBus();
    const QString svc = QStringLiteral("org.kde.KWin"), path = QStringLiteral("/Scripting"), iface = QStringLiteral("org.kde.kwin.Scripting");
    { QDBusMessage u = QDBusMessage::createMethodCall(svc, path, iface, QStringLiteral("unloadScript")); u.setArguments({name}); bus.call(u, QDBus::Block, 500); }
    QDBusMessage l = QDBusMessage::createMethodCall(svc, path, iface, QStringLiteral("loadScript")); l.setArguments({file, name});
    const QDBusReply<int> id = bus.call(l, QDBus::Block, 500);
    if (!id.isValid() || id.value() < 0) return;
    bus.call(QDBusMessage::createMethodCall(svc, QStringLiteral("/Scripting/Script%1").arg(id.value()), QStringLiteral("org.kde.kwin.Script"), QStringLiteral("run")), QDBus::NoBlock);
    QTimer::singleShot(1500, this, [name] { QDBusMessage u = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), QStringLiteral("org.kde.kwin.Scripting"), QStringLiteral("unloadScript")); u.setArguments({name}); QDBusConnection::sessionBus().call(u, QDBus::NoBlock); });
}

QString Shell::kwinShortcutKey(const QString &action) const
{
    const QList<QKeySequence> keys = KGlobalAccel::self()->globalShortcut(QStringLiteral("kwin"), action);
    for (const QKeySequence &k : keys) if (!k.isEmpty()) return k.toString(QKeySequence::NativeText);
    return {};
}

static QElapsedTimer s_sinceStart;
void Shell::markStart() { s_sinceStart.start(); }
qint64 Shell::msSinceStart() { return s_sinceStart.isValid() ? s_sinceStart.elapsed() : -1; }
int Shell::sinceStart() const { return s_sinceStart.isValid() ? int(s_sinceStart.elapsed()) : -1; }

void Shell::setupCapture(QQuickWindow *window)
{
    if (!window) return;
    using W = LayerShellQt::Window;
    auto *lw = W::get(window);
    lw->setLayer(W::LayerOverlay);
    lw->setScope(QStringLiteral("glass-capture"));                       // not "dock": the Glass effect leaves it alone
    lw->setKeyboardInteractivity(W::KeyboardInteractivityExclusive);
    lw->setAnchors(W::Anchors(W::AnchorTop | W::AnchorBottom | W::AnchorLeft | W::AnchorRight));
    lw->setExclusiveZone(-1);
}

// The level meter's own window: the four bars change up to 25 times a second, and every change repainted the whole bar
// surface (a 5120-wide layer window: ~8 % of a core in KWin and 3 % GPU while music played, measured 2026-09-23). In a
// 16x14 window of its own the damage is 16x14. Top layer like the bar (mapped later, so above it), no input, no keyboard,
// its own scope so the Glass effect never treats it as a panel. Position = margins from the screen's top-left corner.
void Shell::setupPatch(QQuickWindow *window, int x, int y)
{
    if (!window) return;
    using W = LayerShellQt::Window;
    auto *lw = W::get(window);
    lw->setLayer(W::LayerTop);
    lw->setScope(QStringLiteral("glass-patch"));
    lw->setKeyboardInteractivity(W::KeyboardInteractivityNone);
    lw->setAnchors(W::Anchors(W::AnchorTop | W::AnchorLeft));
    lw->setExclusiveZone(-1);
    lw->setMargins(QMargins(x, y, 0, 0));
    lw->setScreen(window->screen());
    window->setFlag(Qt::WindowTransparentForInput, true);
}

void Shell::movePatch(QQuickWindow *window, int x, int y)
{
    if (!window) return;
    LayerShellQt::Window::get(window)->setMargins(QMargins(x, y, 0, 0));
}

void Shell::notify(const QString &title, const QString &text, const QString &imagePath, const QString &showPath)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    const QString svc = QStringLiteral("org.freedesktop.Notifications"), path = QStringLiteral("/org/freedesktop/Notifications");
    QDBusMessage m = QDBusMessage::createMethodCall(svc, path, svc, QStringLiteral("Notify"));
    QVariantMap hints{{QStringLiteral("desktop-entry"), QStringLiteral("sirca-shell")}};
    if (!imagePath.isEmpty()) hints.insert(QStringLiteral("image-path"), imagePath);
    QStringList actions;
    if (!showPath.isEmpty()) actions = {QStringLiteral("default"), QStringLiteral("Show in folder"), QStringLiteral("show"), QStringLiteral("Show in folder")};
    m.setArguments({QStringLiteral("Sirca Shell"), uint(0), QStringLiteral("camera-photo"), title, text, actions, hints, 6000});
    if (showPath.isEmpty()) { bus.call(m, QDBus::NoBlock); return; }
    if (!m_notifyListening) {
        m_notifyListening = true;
        bus.connect(svc, path, svc, QStringLiteral("ActionInvoked"), this, SLOT(onNotificationAction(uint, QString)));
        bus.connect(svc, path, svc, QStringLiteral("NotificationClosed"), this, SLOT(onNotificationClosed(uint, uint)));
    }
    auto *w = new QDBusPendingCallWatcher(bus.asyncCall(m), this);           // the id comes back in the reply
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, showPath](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<uint> reply = *w;
        if (!reply.isError()) m_notifyPaths.insert(reply.value(), showPath);
    });
}

void Shell::onNotificationAction(uint id, const QString &action)
{
    const QString file = m_notifyPaths.take(id);
    if (file.isEmpty()) return;
    if (file == QLatin1String("<update>")) { runUpdate(); return; }
    if (file == QLatin1String("<crash>") && action != QLatin1String("issue")) { QProcess::startDetached(QStringLiteral("xdg-open"), {m_crashFile}); return; }
    if (file == QLatin1String("<crash>")) {
        QUrl u(QStringLiteral("https://github.com/onuroluc/sirca-shell/issues/new"));
        QUrlQuery q; q.addQueryItem(QStringLiteral("title"), QStringLiteral("Crash: (what were you doing?)"));
        q.addQueryItem(QStringLiteral("body"), QStringLiteral("Version %1 (build %2)\n\nWhat I was doing:\n\n\nPaste the report here (it opened in your editor; it is also at %3):\n\n").arg(version(), buildCommit().left(7), m_crashFile));
        u.setQuery(q); QProcess::startDetached(QStringLiteral("xdg-open"), {u.toString()}); return; }
    // Dolphin directly, not org.freedesktop.FileManager1: Nautilus, Nemo and Dolphin all register that name here and
    // D-Bus activation would pick whichever it likes. --select opens the folder with the file highlighted.
    if (!QProcess::startDetached(QStringLiteral("dolphin"), {QStringLiteral("--select"), file}))
        QProcess::startDetached(QStringLiteral("xdg-open"), {QFileInfo(file).absolutePath()});
}

// A notification with buttons (the update, the crash report): the action ids come back through onNotificationAction
// with the token stored under the notification's id.
void Shell::notifyWithActions(const QString &title, const QString &text, const QString &icon, const QStringList &actions, const QString &token, bool resident)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    const QString svc = QStringLiteral("org.freedesktop.Notifications"), path = QStringLiteral("/org/freedesktop/Notifications");
    if (!m_notifyListening) { m_notifyListening = true;
        bus.connect(svc, path, svc, QStringLiteral("ActionInvoked"), this, SLOT(onNotificationAction(uint, QString)));
        bus.connect(svc, path, svc, QStringLiteral("NotificationClosed"), this, SLOT(onNotificationClosed(uint, uint))); }
    QDBusMessage m = QDBusMessage::createMethodCall(svc, path, svc, QStringLiteral("Notify"));
    QVariantMap hints{{QStringLiteral("desktop-entry"), QStringLiteral("sirca-shell")}};
    if (resident) hints.insert(QStringLiteral("resident"), true);
    m.setArguments({QStringLiteral("Sirca Shell"), uint(0), icon, title, text, actions, hints, resident ? 0 : 15000});
    auto *w = new QDBusPendingCallWatcher(bus.asyncCall(m), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, token](QDBusPendingCallWatcher *w) { w->deleteLater(); const QDBusPendingReply<uint> reply = *w; if (!reply.isError()) m_notifyPaths.insert(reply.value(), token); });
}

void Shell::markReady(const QString &what)
{
    m_ready.insert(what);
    // the login splash waits for plasmashell's "desktop" stage; without plasmashell (withoutPlasmashell) the shell says it
    // once bar and dock have drawn, or ksplash sits there until its own timeout. Harmless when no splash is running.
    static bool splashTold = false;
    if (!splashTold && m_ready.contains(QStringLiteral("top")) && m_ready.contains(QStringLiteral("bottom")) && loadConfig().value(QStringLiteral("withoutPlasmashell"), false).toBool()) {
        splashTold = true;
        QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(QStringLiteral("org.kde.KSplash"), QStringLiteral("/KSplash"), QStringLiteral("org.kde.KSplash"), QStringLiteral("setStage")) << QStringLiteral("desktop"));
        qInfo("sirca-shell: told ksplash the desktop is up");
    }
}

// ---- Start-up self-test: a few seconds in, is everything that should be there, there? One line in the journal either
// way ("self-test: bar ok, dock ok, ..."), and a notification only when something is missing, so "my bar is gone" comes
// with the reason attached. Config "selfTestNotify": false keeps the notification away.
void Shell::selfTest()
{
    QStringList ok, bad;
    auto check = [&](bool good, const QString &name, const QString &why) { if (good) ok << name; else bad << name + QStringLiteral(" (") + why + QLatin1Char(')'); };
    const QVariantMap cfg = loadConfig();
    // the primary screen carries bar and dock unless "screens": { <name>: { bar: false / dock: false } } says otherwise;
    // another screen listed with bar: true counts too
    const QVariantMap screens = cfg.value(QStringLiteral("screens")).toMap();
    auto wanted = [&](const QString &key) { bool any = false, primaryListed = false;
        for (auto it = screens.begin(); it != screens.end(); ++it) { const QVariantMap c = it.value().toMap(); const bool isPrimary = it.key() == primaryScreenName();
            if (isPrimary) primaryListed = true; if (c.value(key, isPrimary).toBool()) any = true; }
        return any || !primaryListed; };
    const bool wantBar = wanted(QStringLiteral("bar")), wantDock = wanted(QStringLiteral("dock"));
    if (wantBar) check(m_ready.contains(QStringLiteral("top")), QStringLiteral("bar"), QStringLiteral("no first frame: is the layer shell available? is another shell holding the top edge?"));
    if (wantDock) check(m_ready.contains(QStringLiteral("bottom")), QStringLiteral("dock"), QStringLiteral("no first frame"));
    check(QDBusConnection::sessionBus().interface()->isServiceRegistered(QStringLiteral("onur.SircaShell")), QStringLiteral("D-Bus name"), QStringLiteral("onur.SircaShell is not ours: a second instance?"));
    // global shortcuts: ours must be known to kglobalaccel (the Search key is registered unconditionally)
    QString comp = QCoreApplication::applicationName(); comp.replace(QLatin1Char('-'), QLatin1Char('_'));
    QDBusReply<QStringList> names = QDBusInterface(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/") + comp, QStringLiteral("org.kde.kglobalaccel.Component")).call(QStringLiteral("shortcutNames"));
    check(names.isValid() && names.value().contains(QStringLiteral("search")), QStringLiteral("shortcuts"), QStringLiteral("kglobalaccel does not list ours: is kglobalacceld running?"));
    auto *fake = qobject_cast<KWayland::Client::FakeInput *>(m_fakeInput);
    check(fake && fake->isValid(), QStringLiteral("fake input"), QStringLiteral("org_kde_kwin_fake_input not granted: the desktop file must list it (installed by install.sh)"));
    // the Glass effect: without it the bar is a flat translucent strip
    const QStringList effects = QDBusInterface(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"), QStringLiteral("org.kde.kwin.Effects")).property("loadedEffects").toStringList();
    bool glass = false; for (const QString &e : effects) if (e.startsWith(QLatin1String("glass")) && !e.startsWith(QLatin1String("glasskey"))) glass = true;
    check(glass, QStringLiteral("Glass effect"), QStringLiteral("no glass* effect loaded in KWin: the bar has no blur (install the effect, or System Settings > Desktop Effects)"));
    check(QDBusConnection::sessionBus().interface()->isServiceRegistered(QStringLiteral("org.freedesktop.Notifications")), QStringLiteral("notifications"), QStringLiteral("no notification server on the bus"));
    qInfo("sirca-shell: self-test: ok: %s%s%s", qPrintable(ok.join(QStringLiteral(", "))), bad.isEmpty() ? "" : "; MISSING: ", qPrintable(bad.join(QStringLiteral("; "))));
    if (bad.isEmpty() || !cfg.value(QStringLiteral("selfTestNotify"), true).toBool()) return;
    notifyWithActions(QStringLiteral("Sirca Shell started with problems"), bad.join(QStringLiteral("\n")) + QStringLiteral("\n\nDetails: journalctl --user -u %1").arg(QCoreApplication::applicationName()),
                      QStringLiteral("dialog-warning"), {}, QString(), false);
}

// ---- Crash report: systemd restarts the shell on failure (Restart=on-failure) and counts it in NRestarts; a fresh
// start after such a restart writes the previous run's last journal lines and the machine's basics into a report file
// under the state folder and says so, with buttons to open it and to file an issue. A plain `systemctl restart` resets
// NRestarts, so a reload never counts as a crash.
void Shell::crashReport()
{
    const QString unit = QCoreApplication::applicationName() + QStringLiteral(".service");
    QProcess p; p.start(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("show"), unit, QStringLiteral("-p"), QStringLiteral("NRestarts"), QStringLiteral("--value")});
    if (!p.waitForFinished(2000)) return;
    const int restarts = QString::fromUtf8(p.readAllStandardOutput()).trimmed().toInt();
    if (restarts <= 0) return;
    const QString stateDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation); QDir().mkpath(stateDir);
    // once per run: systemd gives every start its own INVOCATION_ID (the restart count resets on a manual restart)
    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
    const QByteArray invocation = qgetenv("INVOCATION_ID");
    const QString marker = stateDir + QStringLiteral("/crash-reported");
    QFile mf(marker); if (!invocation.isEmpty() && mf.open(QIODevice::ReadOnly) && mf.readAll().trimmed() == invocation) return;
    mf.close();
    QProcess j; j.start(QStringLiteral("journalctl"), {QStringLiteral("--user"), QStringLiteral("-u"), unit, QStringLiteral("-b"), QStringLiteral("-n"), QStringLiteral("120"), QStringLiteral("--no-pager"), QStringLiteral("-o"), QStringLiteral("short-iso")});
    j.waitForFinished(4000);
    QString lines = QString::fromUtf8(j.readAllStandardOutput());
    // only what came before this run's first line
    const int cut = lines.lastIndexOf(QStringLiteral("start-up: Shell singleton built"));
    if (cut > 0) { const int nl = lines.lastIndexOf(QLatin1Char('\n'), cut); if (nl > 0) lines = lines.left(nl); }
    QProcess pv; pv.start(QStringLiteral("plasmashell"), {QStringLiteral("--version")}); pv.waitForFinished(2000);
    QProcess nv; nv.start(QStringLiteral("nvidia-smi"), {QStringLiteral("--query-gpu=driver_version,name"), QStringLiteral("--format=csv,noheader")}); nv.waitForFinished(2000);
    const QString report = QStringLiteral("Sirca Shell crash report  %1\n\nversion %2  build %3\nrestart #%4 of this session (systemd NRestarts)\n%5kernel %6\nGPU %7\n\n---- last journal lines of the run that ended ----\n%8\n")
        .arg(QDateTime::currentDateTime().toString(Qt::ISODate), version(), buildCommit().left(7)).arg(restarts)
        .arg(QString::fromUtf8(pv.readAllStandardOutput()).trimmed() + QLatin1Char('\n'), QSysInfo::kernelVersion(), QString::fromUtf8(nv.readAllStandardOutput()).trimmed(), lines);
    m_crashFile = stateDir + QStringLiteral("/crash-") + stamp + QStringLiteral(".txt");
    QFile f(m_crashFile); if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) return; f.write(report.toUtf8()); f.close();
    if (mf.open(QIODevice::WriteOnly | QIODevice::Truncate)) mf.write(invocation);
    qWarning("sirca-shell: the previous run ended by a crash (restart #%d); report: %s", restarts, qPrintable(m_crashFile));
    notifyWithActions(QStringLiteral("Sirca Shell restarted after a crash"), QStringLiteral("The last lines of its log are in a report. If it keeps happening, please file it so it can be fixed."),
                      QStringLiteral("dialog-error"), {QStringLiteral("default"), QStringLiteral("Show report"), QStringLiteral("show"), QStringLiteral("Show report"), QStringLiteral("issue"), QStringLiteral("File an issue")}, QStringLiteral("<crash>"), true);
}

void Shell::onNotificationClosed(uint id, uint) { if (m_notifyPaths.size() > 64) m_notifyPaths.clear(); Q_UNUSED(id) }   // entries stay for the history; just bounded

void Shell::setBlurRegion(QQuickWindow *window, const QVariantList &rects)
{
    if (!window) return;
    const QRegion region = regionFor(rects);
    KWindowEffects::enableBlurBehind(window, !region.isEmpty(), region);
}

bool Shell::altHeld() const
{
    return QGuiApplication::queryKeyboardModifiers().testFlag(Qt::AltModifier);
}

void Shell::initFakeInput()
{
    if (m_fakeTried) return;
    m_fakeTried = true;
    auto *conn = KWayland::Client::ConnectionThread::fromApplication(this);
    if (!conn) return;
    auto *registry = new KWayland::Client::Registry(this);
    connect(registry, &KWayland::Client::Registry::fakeInputAnnounced, this, [this, registry](quint32 name, quint32 version) {
        auto *fake = registry->createFakeInput(name, version, this);
        fake->authenticate(QStringLiteral("Sirca Shell"), QStringLiteral("pass the click that closed a popup on to the window under it"));
        m_fakeInput = fake;
        qInfo("sirca-shell: fake input ready (clicks that dismiss a popup are passed on)");
    });
    registry->create(conn);
    registry->setup();
}

void Shell::replayClick(int button)
{
    initFakeInput();
    auto *fake = qobject_cast<KWayland::Client::FakeInput *>(m_fakeInput);
    if (!fake || !fake->isValid()) { qWarning("sirca-shell: fake input is not available (org_kde_kwin_fake_input missing from sirca-shell.desktop?): the click is not passed on"); return; }
    fake->requestPointerButtonClick(Qt::MouseButton(button));
}

void Shell::watchConfig()
{
    const QString file = configPath(), dir = QFileInfo(file).absolutePath();
    QDir().mkpath(dir);
    m_configDebounce.setSingleShot(true);
    m_configDebounce.setInterval(30);
    connect(&m_configDebounce, &QTimer::timeout, this, [this, file] {
        if (QFile::exists(file) && !m_configWatcher.files().contains(file)) m_configWatcher.addPath(file);   // editors (and our QSaveFile) replace the file
        // our own write already bumped the revision when it was made; its inotify echo must not reload everything a second
        // time. Judged by content, not by time: glass-mode writes the file right after our "mode" write, and that must count.
        if (!m_ownConfigBytes.isEmpty()) { QFile f(file); if (f.open(QIODevice::ReadOnly) && f.readAll() == m_ownConfigBytes) return; }
        ++m_configRevision;
        Q_EMIT configRevisionChanged();
    });
    m_configWatcher.addPath(dir);
    if (QFile::exists(file)) m_configWatcher.addPath(file);
    connect(&m_configWatcher, &QFileSystemWatcher::fileChanged, this, [this] { m_configDebounce.start(); });
    connect(&m_configWatcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_configDebounce.start(); });
}

void Shell::removeConfigKey(const QString &key)
{
    QJsonObject o = readConfigObject();
    if (!o.contains(key)) return;
    o.remove(key);
    writeConfigObject(o);
}

bool Shell::runDetached(const QString &program, const QStringList &arguments)
{
    return QProcess::startDetached(program, arguments);
}

QString Shell::homePath() const { return QDir::homePath(); }
QString Shell::picturesPath() const { return QStandardPaths::writableLocation(QStandardPaths::PicturesLocation); }

static QString installedRoot();
QString Shell::toolPath(const QString &name) const
{
    const QString onPath = QStandardPaths::findExecutable(name);
    if (!onPath.isEmpty()) return onPath;
    const QString root = installedRoot();
    if (!root.isEmpty() && QFileInfo::exists(root + QStringLiteral("/scripts/") + name)) return root + QStringLiteral("/scripts/") + name;
    const QString local = QDir::homePath() + QStringLiteral("/.local/bin/") + name;
    return QFileInfo::exists(local) ? local : QString();
}

void Shell::setWithoutPlasmashell(bool on) { if (on == m_withoutPlasmashell) return; m_withoutPlasmashell = on; updateOsdClaim(); }
bool Shell::servesOsd() const { return m_osd && m_osd->claimed(); }

void Shell::updateOsdClaim()
{
    if (!m_osd) return;
    const bool before = m_osd->claimed();
    if (m_withoutPlasmashell && !m_plasmaRunning) m_osd->claim(); else m_osd->release();
    if (before != m_osd->claimed()) { qInfo("sirca-shell: org.kde.osdService %s", m_osd->claimed() ? "served by the shell (no plasmashell)" : "released"); Q_EMIT plasmaRunningChanged(); }
}

QString Shell::primaryScreenName() const
{
    const QString cfg = loadConfig().value(QStringLiteral("primaryScreen")).toString();
    if (!cfg.isEmpty()) { for (QScreen *s : QGuiApplication::screens()) if (s->name() == cfg) return cfg; }
    QScreen *p = QGuiApplication::primaryScreen();
    return p ? p->name() : QString();
}

// plasmashell's desktop window and our wallpaper share KWin's desktop layer, and a freshly mapped layer-shell surface does
// NOT land on top of it (measured 2026-09-22: after every shell restart plasmashell's desktop was above the wallpaper, so a
// right click on the desktop opened Plasma's menu). workspace.raiseWindow from a KWin script does put ours on top.
void Shell::raiseWallpaper()
{
    // A persistent KWin script: whenever plasmashell's desktop window is activated or added (a click on the desktop
    // activates and raises it), or our own wallpaper is mapped again, and Plasma's desktop has come out above our
    // wallpaper, raise ours again. Loaded once per compositor session: when it is already loaded there is nothing to do
    // (its windowAdded handler sees the re-mapped wallpaper). Everything below is asynchronous: KWin answers these calls
    // slowly while it is busy, and a blocking call here stalled the shell for the whole wait.
    const QString name = QStringLiteral("sirca-shell-raise-wallpaper");
    const QString svc = QStringLiteral("org.kde.KWin"), spath = QStringLiteral("/Scripting"), iface = QStringLiteral("org.kde.kwin.Scripting");
    QDBusMessage q = QDBusMessage::createMethodCall(svc, spath, iface, QStringLiteral("isScriptLoaded"));
    q.setArguments({name});
    auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(q, 500), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, name, svc, spath, iface](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<bool> loaded = *w;
        if (loaded.isValid() && loaded.value()) return;
        const QString path = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/sirca-shell-raise-wallpaper.js");
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) return;
        // fix() walks the whole stacking order, so it only runs for the two windows that matter: Plasma's desktop window,
        // and our wallpaper being (re)mapped. (No stackingOrderChanged in KWin scripting.)
        f.write("const cls = \"" + QCoreApplication::applicationName().toUtf8() + "\";\n"
                "function isOurs(w) { return w.resourceClass == cls && w.layer == 0 && !w.desktopWindow && w.frameGeometry.width >= 64; }\n"
                "function fix() { const st = workspace.stackingOrder; let ours = null, oi = -1, theirs = -1;\n"
                "  for (let i = 0; i < st.length; i++) { const w = st[i]; if (isOurs(w)) { ours = w; oi = i; } else if (w.desktopWindow) theirs = Math.max(theirs, i); }\n"
                "  if (ours && theirs > oi) workspace.raiseWindow(ours); }\n"
                "function onWindow(w) { if (w && (w.desktopWindow || isOurs(w))) fix(); }\n"
                "workspace.windowActivated.connect(onWindow); workspace.windowAdded.connect(onWindow); fix();\n");
        f.close();
        QDBusMessage l = QDBusMessage::createMethodCall(svc, spath, iface, QStringLiteral("loadScript"));
        l.setArguments({path, name});
        auto *w2 = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(l, 1000), this);
        connect(w2, &QDBusPendingCallWatcher::finished, this, [svc](QDBusPendingCallWatcher *w2) {
            w2->deleteLater();
            const QDBusPendingReply<int> id = *w2;
            if (!id.isValid() || id.value() < 0) return;
            QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(svc, QStringLiteral("/Scripting/Script") + QString::number(id.value()), QStringLiteral("org.kde.kwin.Script"), QStringLiteral("run")), 1000);
        });
    });
}

// ---- update check ---------------------------------------------------------------------------------------------------
QString Shell::buildCommit() const { return QStringLiteral(GLASS_BUILD_COMMIT); }
QString Shell::version() const { return QStringLiteral(GLASS_VERSION); }

// "0.5.10" > "0.5.9": numeric per component, a missing component counts as 0
static int versionCompare(const QString &a, const QString &b)
{
    const QStringList x = a.split(QLatin1Char('.')), y = b.split(QLatin1Char('.'));
    for (int i = 0; i < qMax(x.size(), y.size()); ++i) {
        const int p = i < x.size() ? x[i].toInt() : 0, q = i < y.size() ? y[i].toInt() : 0;
        if (p != q) return p < q ? -1 : 1;
    }
    return 0;
}

static QString installedRoot()
{
    const QString state = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QLatin1Char('/') + QCoreApplication::applicationName() + QStringLiteral("/root.txt");
    QFile f(state);
    if (f.open(QIODevice::ReadOnly)) { const QString p = QString::fromUtf8(f.readAll()).trimmed(); if (QDir(p).exists()) return p; }
    return QString();
}

void Shell::checkForUpdate(bool announceUpToDate)
{
    const QVariantMap cfg = loadConfig();
    const QString repo = cfg.value(QStringLiteral("updateRepo"), QStringLiteral("onuroluc/sirca-shell")).toString();
    const QString branch = cfg.value(QStringLiteral("updateBranch"), QStringLiteral("main")).toString();
    // Releases are versions, not commits: main only moves per release, so the VERSION file on the branch IS the newest
    // release (one small raw-file GET, no API, no rate limit). A dev build newer than the release stays quiet.
    static QNetworkAccessManager *nam = nullptr;
    if (!nam) nam = new QNetworkAccessManager(this);
    QNetworkRequest req(QUrl(QStringLiteral("https://raw.githubusercontent.com/%1/%2/VERSION").arg(repo, branch)));
    req.setRawHeader("User-Agent", QCoreApplication::applicationName().toUtf8());
    req.setTransferTimeout(15000);
    QNetworkReply *r = nam->get(req);
    connect(r, &QNetworkReply::finished, this, [this, r, announceUpToDate, repo, branch] {
        r->deleteLater();
        if (r->error() != QNetworkReply::NoError) { qInfo("sirca-shell: update check failed: %s", qPrintable(r->errorString())); return; }
        const QString remote = QString::fromUtf8(r->readAll()).trimmed();
        if (remote.isEmpty() || remote.size() > 32 || !remote[0].isDigit()) { qInfo("sirca-shell: update check: no version file on %s/%s", qPrintable(repo), qPrintable(branch)); return; }
        qInfo("sirca-shell: update check: this is %s, the release is %s", qPrintable(version()), qPrintable(remote));
        if (versionCompare(remote, version()) <= 0) {
            if (announceUpToDate) notify(QStringLiteral("Up to date"), QStringLiteral("Sirca Shell %1 is the newest version.").arg(version()), QString());
            return;
        }
        Q_EMIT updateAvailable(remote);
        // one notification with a button; its action id "default" / "update" comes back through onNotificationAction
        QDBusConnection bus = QDBusConnection::sessionBus();
        const QString svc = QStringLiteral("org.freedesktop.Notifications"), path = QStringLiteral("/org/freedesktop/Notifications");
        if (!m_notifyListening) { m_notifyListening = true;
            bus.connect(svc, path, svc, QStringLiteral("ActionInvoked"), this, SLOT(onNotificationAction(uint, QString)));
            bus.connect(svc, path, svc, QStringLiteral("NotificationClosed"), this, SLOT(onNotificationClosed(uint, uint))); }
        QDBusMessage m = QDBusMessage::createMethodCall(svc, path, svc, QStringLiteral("Notify"));
        QVariantMap hints{{QStringLiteral("desktop-entry"), QStringLiteral("sirca-shell")}, {QStringLiteral("resident"), true}};
        const QStringList actions{QStringLiteral("default"), QStringLiteral("Update now"), QStringLiteral("update"), QStringLiteral("Update now")};
        m.setArguments({QStringLiteral("Sirca Shell"), uint(0), QStringLiteral("system-software-update"), QStringLiteral("Sirca Shell %1 is available").arg(remote),
                        QStringLiteral("You have %1. Update now pulls the new version and re-runs the installer in a terminal.").arg(version()), actions, hints, 0});
        auto *w = new QDBusPendingCallWatcher(bus.asyncCall(m), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) { w->deleteLater(); const QDBusPendingReply<uint> reply = *w; if (!reply.isError()) m_notifyPaths.insert(reply.value(), QStringLiteral("<update>")); });
    });
}

void Shell::runUpdate()
{
    const QString root = installedRoot();
    if (root.isEmpty()) { notify(QStringLiteral("Cannot update"), QStringLiteral("The installed folder is not known (run install.sh once from the repository)."), QString()); return; }
    const QString script = root + QStringLiteral("/update.sh");
    if (!QFile::exists(script)) { notify(QStringLiteral("Cannot update"), QStringLiteral("%1 is missing.").arg(script), QString()); return; }
    const QString term = defaultTerminal();
    // the terminal shows the pull and the installer (it may ask for sudo); the shell is restarted by the installer
    if (term.contains(QLatin1String("ghostty")) || term.contains(QLatin1String("kitty")) || term.contains(QLatin1String("alacritty")) || term.contains(QLatin1String("foot")))
        QProcess::startDetached(term, {QStringLiteral("-e"), QStringLiteral("bash"), script});
    else if (term.contains(QLatin1String("konsole")) || term.contains(QLatin1String("gnome-terminal")) || term.contains(QLatin1String("xterm")))
        QProcess::startDetached(term, {QStringLiteral("-e"), QStringLiteral("bash"), script});
    else QProcess::startDetached(QStringLiteral("xterm"), {QStringLiteral("-e"), QStringLiteral("bash"), script});
}
