#include "privacymonitor.h"
#include <QMetaObject>
#include <QSet>
#include <QHash>

#ifdef HAVE_PIPEWIRE
#include <pipewire/pipewire.h>
#include <spa/utils/dict.h>
#include <cstring>

namespace {
QString prop(const spa_dict *d, const char *key) { const char *v = d ? spa_dict_lookup(d, key) : nullptr; return v ? QString::fromUtf8(v) : QString(); }
}

struct PrivacyMonitor::Private
{
    PrivacyMonitor *q = nullptr;
    pw_thread_loop *loop = nullptr;
    pw_context *context = nullptr;
    pw_core *core = nullptr;
    pw_registry *registry = nullptr;
    spa_hook registryListener {};
    spa_hook coreListener {};
    // everything below is touched on the loop thread only
    struct Node { PrivacyMonitor::Private *d; uint32_t id; pw_proxy *proxy; spa_hook listener; QString mediaClass, name, app, api; bool running = false; bool kwin = false; };
    struct Link { uint32_t out, in; };
    QHash<uint32_t, Node *> nodes;
    QHash<uint32_t, Link> links;

    static bool isKwin(const Node &n) { return n.name.startsWith(QLatin1String("kwin_screencast")) || n.name.startsWith(QLatin1String("kwin-screencast")) || n.app == QLatin1String("kwin_wayland"); }

    void evaluate()
    {
        QStringList cams, screens;
        QSet<uint32_t> kwinIds;
        for (const Node *n : std::as_const(nodes)) if (n->kwin) kwinIds.insert(n->id);
        // consumers linked to a KWin stream are the screen-sharing apps; the other video consumers read a camera
        QHash<uint32_t, bool> consumerOfScreen;
        for (const Link &l : std::as_const(links)) if (kwinIds.contains(l.out)) consumerOfScreen[l.in] = true;
        for (const Node *n : std::as_const(nodes)) {
            const QString label = n->app.isEmpty() ? n->name : n->app;
            if (n->kwin) continue;                                   // the stream exists = a session is live; who reads it is found through the links
            if (n->mediaClass == QLatin1String("Stream/Input/Video")) {
                if (!n->running) continue;
                if (consumerOfScreen.value(n->id)) { if (!screens.contains(label)) screens << label; }
                else if (!cams.contains(label)) cams << label;
            } else if (n->mediaClass.startsWith(QLatin1String("Video/Source")) && (n->api == QLatin1String("v4l2") || n->api == QLatin1String("libcamera"))) {
                if (n->running && !cams.contains(label)) cams << label;     // the device itself is streaming: someone reads it even if we saw no consumer node
            }
        }
        // a KWin stream whose consumer has no name of its own (or is not linked yet) still counts, as "Screen"
        if (!kwinIds.isEmpty() && screens.isEmpty()) screens << QStringLiteral("Screen");
        QMetaObject::invokeMethod(q, "publish", Qt::QueuedConnection, Q_ARG(bool, true), Q_ARG(QStringList, cams), Q_ARG(QStringList, screens));
    }

    static void nodeInfo(void *data, const pw_node_info *info)
    {
        auto *n = static_cast<Node *>(data);
        if (info->change_mask & PW_NODE_CHANGE_MASK_PROPS) {
            n->mediaClass = prop(info->props, PW_KEY_MEDIA_CLASS); n->name = prop(info->props, PW_KEY_NODE_NAME);
            n->app = prop(info->props, PW_KEY_APP_NAME); n->api = prop(info->props, PW_KEY_DEVICE_API); n->kwin = isKwin(*n);
        }
        if (info->change_mask & PW_NODE_CHANGE_MASK_STATE) n->running = info->state == PW_NODE_STATE_RUNNING;
        n->d->evaluate();
    }
    static constexpr pw_node_events nodeEvents = { .version = PW_VERSION_NODE_EVENTS, .info = nodeInfo, .param = nullptr };

    static void globalAdded(void *data, uint32_t id, uint32_t permissions, const char *type, uint32_t version, const spa_dict *props)
    {
        Q_UNUSED(permissions); Q_UNUSED(version);
        auto *d = static_cast<Private *>(data);
        if (std::strcmp(type, PW_TYPE_INTERFACE_Link) == 0) {
            bool ok1 = false, ok2 = false;
            const uint32_t out = prop(props, PW_KEY_LINK_OUTPUT_NODE).toUInt(&ok1), in = prop(props, PW_KEY_LINK_INPUT_NODE).toUInt(&ok2);
            if (ok1 && ok2) { d->links.insert(id, { out, in }); d->evaluate(); }
            return;
        }
        if (std::strcmp(type, PW_TYPE_INTERFACE_Node) != 0) return;
        const QString mediaClass = prop(props, PW_KEY_MEDIA_CLASS), name = prop(props, PW_KEY_NODE_NAME);
        // only video nodes are bound (audio streams come and go all day; binding each would be noise for nothing)
        const bool video = mediaClass.contains(QLatin1String("Video")) || name.startsWith(QLatin1String("kwin"));
        if (!video) return;
        auto *n = new Node { d, id, nullptr, {}, mediaClass, name, prop(props, PW_KEY_APP_NAME), prop(props, PW_KEY_DEVICE_API) };
        n->kwin = isKwin(*n);
        n->proxy = static_cast<pw_proxy *>(pw_registry_bind(d->registry, id, type, PW_VERSION_NODE, 0));
        if (!n->proxy) { delete n; return; }
        pw_node_add_listener(reinterpret_cast<pw_node *>(n->proxy), &n->listener, &nodeEvents, n);   // the state (running / suspended) arrives with the info event
        d->nodes.insert(id, n);
        d->evaluate();
    }
    static void globalRemoved(void *data, uint32_t id)
    {
        auto *d = static_cast<Private *>(data);
        if (d->links.remove(id)) { d->evaluate(); return; }
        if (Node *n = d->nodes.take(id)) { spa_hook_remove(&n->listener); pw_proxy_destroy(n->proxy); delete n; d->evaluate(); }
    }
    static constexpr pw_registry_events registryEvents = { .version = PW_VERSION_REGISTRY_EVENTS, .global = globalAdded, .global_remove = globalRemoved };

    static void coreError(void *data, uint32_t id, int seq, int res, const char *message)
    {
        Q_UNUSED(seq); Q_UNUSED(res);
        auto *d = static_cast<Private *>(data);
        if (id == PW_ID_CORE) { qWarning("sirca-shell: privacy monitor: PipeWire core error: %s", message); QMetaObject::invokeMethod(d->q, "publish", Qt::QueuedConnection, Q_ARG(bool, false), Q_ARG(QStringList, QStringList()), Q_ARG(QStringList, QStringList())); }
    }
    static constexpr pw_core_events coreEvents = { .version = PW_VERSION_CORE_EVENTS, .info = nullptr, .done = nullptr, .ping = nullptr, .error = coreError };
};

PrivacyMonitor::PrivacyMonitor(QObject *parent) : QObject(parent) {}
PrivacyMonitor::~PrivacyMonitor() { stop(); }

void PrivacyMonitor::start()
{
    if (d) return;
    pw_init(nullptr, nullptr);
    d = new Private; d->q = this;
    d->loop = pw_thread_loop_new("glass-privacy", nullptr);
    d->context = d->loop ? pw_context_new(pw_thread_loop_get_loop(d->loop), nullptr, 0) : nullptr;
    d->core = d->context ? pw_context_connect(d->context, nullptr, 0) : nullptr;
    if (!d->core) { qWarning("sirca-shell: privacy monitor: no PipeWire (camera / screen-share indicators off)"); stop(); publish(false, {}, {}); return; }
    pw_core_add_listener(d->core, &d->coreListener, &Private::coreEvents, d);
    d->registry = pw_core_get_registry(d->core, PW_VERSION_REGISTRY, 0);
    pw_registry_add_listener(d->registry, &d->registryListener, &Private::registryEvents, d);
    pw_thread_loop_start(d->loop);
    m_available = true; Q_EMIT availableChanged();
}

void PrivacyMonitor::stop()
{
    if (!d) return;
    if (d->loop) pw_thread_loop_stop(d->loop);
    for (Private::Node *n : std::as_const(d->nodes)) { spa_hook_remove(&n->listener); pw_proxy_destroy(n->proxy); delete n; }
    d->nodes.clear(); d->links.clear();
    if (d->registry) { spa_hook_remove(&d->registryListener); pw_proxy_destroy(reinterpret_cast<pw_proxy *>(d->registry)); }
    if (d->core) { spa_hook_remove(&d->coreListener); pw_core_disconnect(d->core); }
    if (d->context) pw_context_destroy(d->context);
    if (d->loop) pw_thread_loop_destroy(d->loop);
    delete d; d = nullptr;
    if (m_available) { m_available = false; Q_EMIT availableChanged(); }
    if (!m_cameraApps.isEmpty() || !m_screenApps.isEmpty()) { m_cameraApps.clear(); m_screenApps.clear(); Q_EMIT stateChanged(); }
}

#else   // no libpipewire at build time: the type exists, reports nothing

struct PrivacyMonitor::Private {};
PrivacyMonitor::PrivacyMonitor(QObject *parent) : QObject(parent) {}
PrivacyMonitor::~PrivacyMonitor() {}
void PrivacyMonitor::start() { qWarning("sirca-shell: privacy monitor: built without libpipewire (camera / screen-share indicators off)"); }
void PrivacyMonitor::stop() {}

#endif

void PrivacyMonitor::setActive(bool on)
{
    if (on == m_active) return;
    m_active = on; Q_EMIT activeChanged();
    if (on) start(); else stop();
}

void PrivacyMonitor::publish(bool available, const QStringList &cameraApps, const QStringList &screenApps)
{
    if (available != m_available) { m_available = available; Q_EMIT availableChanged(); }
    if (cameraApps == m_cameraApps && screenApps == m_screenApps) return;
    m_cameraApps = cameraApps; m_screenApps = screenApps;
    Q_EMIT stateChanged();
}
