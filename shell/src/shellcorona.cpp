#include "shellcorona.h"
#include <PlasmaQuick/ConfigView>
#include <QPointer>
#include <KConfigGroup>
#include <KPackage/Package>
#include <KPackage/PackageLoader>
#include <PlasmaQuick/AppletQuickItem>
#include <QDebug>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QScreen>

static ShellCorona *s_self = nullptr;

static int s_pendingStrut[2] = {-1, -1};     // [top, bottom], set before the corona existed

bool ShellCorona::exists() { return s_self != nullptr; }

void ShellCorona::rememberStrut(bool bottom, int px)
{
    s_pendingStrut[bottom ? 1 : 0] = px;
    if (s_self) s_self->setStrut(bottom, px);
}

ShellCorona *ShellCorona::self()
{
    if (!s_self) {
        s_self = new ShellCorona(qApp);
        for (int i = 0; i < 2; ++i) if (s_pendingStrut[i] >= 0) s_self->setStrut(i == 1, s_pendingStrut[i]);
    }
    return s_self;
}

ShellCorona::ShellCorona(QObject *parent) : Plasma::Corona(parent)
{
    KPackage::Package package = KPackage::PackageLoader::self()->loadPackage(QStringLiteral("Plasma/Shell"));
    // own shell package (a copy of org.kde.plasma.desktop whose CompactApplet.qml never opens a popup dialog);
    // falls back to the stock one if it is not installed
    package.setPath(QStringLiteral("onur.sircashell"));
    if (!package.isValid()) {
        qWarning() << "sirca-shell: shell package onur.sircashell missing, using org.kde.plasma.desktop";
        package.setPath(QStringLiteral("org.kde.plasma.desktop"));
    }
    setKPackage(package);
    loadLayout(QStringLiteral("sirca-shell-appletsrc"));
    for (Plasma::Containment *c : containments()) {
        const QString zone = c->config().readEntry("glassZone", QString());
        if (!zone.isEmpty()) m_zones.insert(zone, c);
    }
}

QRect ShellCorona::screenGeometry(int) const
{
    // the screen a hosted applet's window is on, when one is mapped (the bar or a lobe may live on a secondary screen);
    // the primary screen otherwise
    for (Plasma::Containment *c : containments())
        for (Plasma::Applet *a : c->applets())
            if (QQuickItem *item = PlasmaQuick::AppletQuickItem::itemForApplet(a))
                if (item->window() && item->window()->screen()) return item->window()->screen()->geometry();
    return QGuiApplication::primaryScreen() ? QGuiApplication::primaryScreen()->geometry() : QRect();
}

QRect ShellCorona::availableScreenRect(int id) const
{
    return screenGeometry(id).adjusted(0, m_top, 0, -m_bottom);
}

void ShellCorona::setStrut(bool bottom, int px)
{
    int &v = bottom ? m_bottom : m_top;
    if (v == px) return;
    v = px;
    Q_EMIT availableScreenRectChanged(0);
    Q_EMIT availableScreenRegionChanged(0);
}

Plasma::Containment *ShellCorona::zoneContainment(const QString &zone)
{
    if (auto *c = m_zones.value(zone)) return c;
    Plasma::Containment *c = createContainment(QStringLiteral("empty"));
    if (!c) return nullptr;
    c->config().writeEntry("glassZone", zone);
    if (zone == QLatin1String("bar")) {
        c->setFormFactor(Plasma::Types::Horizontal);
        c->setLocation(Plasma::Types::Floating);   /* not TopEdge: for an edge location Plasma places tooltips outside the whole WINDOW, and our bar window includes its popups — tooltips landed below the open popup. Floating = next to the hovered item */
    } else {
        c->setFormFactor(Plasma::Types::Planar);
        c->setLocation(Plasma::Types::Floating);
    }
    m_zones.insert(zone, c);
    requestConfigSync();
    return c;
}

Plasma::Applet *ShellCorona::appletFor(const QString &plugin, const QString &zone)
{
    Plasma::Containment *c = zoneContainment(zone);
    if (!c) return nullptr;
    watchConfigRequests(c);
    // restored layouts come back without form factor: re-assert it for the zone
    if (zone == QLatin1String("bar")) { c->setFormFactor(Plasma::Types::Horizontal); c->setLocation(Plasma::Types::Floating);   /* not TopEdge: for an edge location Plasma places tooltips outside the whole WINDOW, and our bar window includes its popups — tooltips landed below the open popup. Floating = next to the hovered item */ }
    for (Plasma::Applet *a : c->applets()) {
        if (a->pluginMetaData().pluginId() == plugin) return a;
    }
    Plasma::Applet *a = c->createApplet(plugin);
    if (!a) qWarning() << "sirca-shell: cannot load applet" << plugin;
    requestConfigSync();
    return a;
}

QQuickItem *ShellCorona::itemFor(const QString &plugin, const QString &zone)
{
    Plasma::Applet *a = appletFor(plugin, zone);
    return a ? PlasmaQuick::AppletQuickItem::itemForApplet(a) : nullptr;
}

static Plasma::Applet *findApplet(Plasma::Containment *c, const QString &plugin)
{
    for (Plasma::Applet *a : c->applets()) {
        if (a->pluginMetaData().pluginId() == plugin) return a;
        // the hosted tray is itself a containment living as an applet: its items are one level down
        if (auto *inner = qobject_cast<Plasma::Containment *>(a)) if (Plasma::Applet *hit = findApplet(inner, plugin)) return hit;
    }
    return nullptr;
}

QQuickItem *ShellCorona::findItem(const QString &plugin)
{
    for (Plasma::Containment *c : containments()) watchConfigRequests(c);   // picks up the tray's inner containment once it exists
    for (Plasma::Containment *c : containments())
        if (Plasma::Applet *a = findApplet(c, plugin)) return PlasmaQuick::AppletQuickItem::itemForApplet(a);
    return nullptr;
}

// Hosted applets do not open their own settings: they emit configureRequested on their containment and expect the SHELL to
// show a config window. plasmashell does that in its panel/desktop views; without this the tray's gear did nothing.
void ShellCorona::watchConfigRequests(Plasma::Containment *c)
{
    if (!c || c->property("_glass_cfg_watched").toBool()) return;
    c->setProperty("_glass_cfg_watched", true);
    connect(c, &Plasma::Containment::configureRequested, this, &ShellCorona::showConfig);
    auto nested = [this](Plasma::Applet *a) { if (auto *inner = qobject_cast<Plasma::Containment *>(a)) watchConfigRequests(inner); };   // the tray is a containment living as an applet
    for (Plasma::Applet *a : c->applets()) nested(a);
    connect(c, &Plasma::Containment::appletAdded, this, nested);
}

void ShellCorona::showConfig(Plasma::Applet *applet)
{
    if (!applet) return;
    static QHash<Plasma::Applet *, QPointer<PlasmaQuick::ConfigView>> open;
    if (auto v = open.value(applet)) { v->show(); v->raise(); v->requestActivate(); return; }
    auto *view = new PlasmaQuick::ConfigView(applet);
    view->init();
    open.insert(applet, view);
    connect(view, &QWindow::visibleChanged, view, [view](bool visible) { if (!visible) view->deleteLater(); });
    view->show();
    view->requestActivate();
}
