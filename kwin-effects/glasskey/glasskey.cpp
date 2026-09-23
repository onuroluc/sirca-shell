#include "glasskey.h"
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>
#include <window.h>
#include <KConfigGroup>
#include <KSharedConfig>
#include <QColor>
#include <QFileInfo>
#include <QStandardPaths>
#include <dlfcn.h>
#include <QVector2D>
#include <QVector4D>
#include <QFile>
#include <QRegularExpression>
#include <QStandardPaths>

static void ensureResources() { Q_INIT_RESOURCE(glasskey); }

namespace KWin
{
// KWin 6.7 removed GLShader::isValid(): there the shader manager returns no shader at all when compiling fails.
bool GlassKeyEffect::shaderOk() const
{
#ifdef GLASS_KWIN_67
    return m_shader != nullptr;
#else
    return m_shader && m_shader->isValid();
#endif
}

static QVector3D rgb(const KConfigGroup &g, const char *key, const char *fallback)
{
    const QColor c(g.readEntry(key, QString::fromLatin1(fallback)));
    return QVector3D(c.redF(), c.greenF(), c.blueF());
}

GlassKeyEffect::GlassKeyEffect()
{
    ensureResources();
    // a shader in ~/.local/share/glass-effect/shaders/<plugin file name>/ (glasskey4/ for glasskey4.so) wins over the
    // built-in one (tuning without a rebuild). Per build on purpose: the uniform contract changes between builds and a
    // flat folder handed a stale shader to a new build (2026-09-23). The embedded one lives under a prefix of its own:
    // KWin never dlcloses an old plugin build, and the first ":/effects/glasskey/..." registered would shadow every
    // later build's copy (same trap as the Glass effect's "glass-lobes" prefix).
    Dl_info info{};
    QString plugin = QStringLiteral("glasskey");
    if (dladdr(reinterpret_cast<const void *>(&ensureResources), &info) && info.dli_fname) plugin = QFileInfo(QString::fromLocal8Bit(info.dli_fname)).completeBaseName();
    QString frag = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("glass-effect/shaders/") + plugin + QStringLiteral("/glasskey.frag"));
    if (frag.isEmpty()) frag = QStringLiteral(":/effects/glasskey-lobes/generated/glasskey.frag");
    qInfo("glasskey: shader %s", qPrintable(frag));
    m_shader = ShaderManager::instance()->generateShaderFromFile(ShaderTrait::MapTexture, QString(), frag);
    if (!shaderOk()) {
        qWarning("glasskey: the shader failed to load");
    } else {
        // resolved once: setUniform(const char *) looks the name up in the program on every call
        m_loc.shadowStrength = m_shader->uniformLocation("shadowStrength");
        m_loc.texSizePx = m_shader->uniformLocation("texSizePx");
        m_loc.contentPx = m_shader->uniformLocation("contentPx");
        m_loc.contentRadius = m_shader->uniformLocation("contentRadius");
    }
    reconfigure(ReconfigureAll);
    connect(effects, &EffectsHandler::windowAdded, this, &GlassKeyEffect::consider);
    // a closing window stays keyed through its close animation: it is forgotten when KWin deletes it, not when it closes
    connect(effects, &EffectsHandler::windowDeleted, this, &GlassKeyEffect::forget);
}

GlassKeyEffect::~GlassKeyEffect()
{
    for (EffectWindow *w : std::as_const(m_windows)) unredirect(w);
}

bool GlassKeyEffect::supported() { return effects->isOpenGLCompositing(); }

void GlassKeyEffect::reconfigure(ReconfigureFlags)
{
    KSharedConfig::Ptr cfg = KSharedConfig::openConfig(QStringLiteral("kwinrc")); cfg->reparseConfiguration();
    const KConfigGroup g = cfg->group(QStringLiteral("Effect-glasskey"));
    m_classes = g.readEntry("Classes", QString()).toLower().split(QRegularExpression(QStringLiteral("[,;\\s]+")), Qt::SkipEmptyParts);
    m_content = rgb(g, "ContentKey", "#14171d"); m_chrome = rgb(g, "ChromeKey", "#191c22"); m_text = rgb(g, "Text", "#eff0f1");
    m_tintContent = rgb(g, "ContentTint", "#111213"); m_tintChrome = rgb(g, "ChromeTint", "#18191b");
    m_alphaContent = g.readEntry("ContentAlpha", 0.72); m_alphaChrome = g.readEntry("ChromeAlpha", 0.60);
    m_shadow = g.readEntry("Shadow", 0.34); m_cornerRadius = g.readEntry("ShadowCornerRadius", 12.0);
    pushUniforms();
    const auto all = effects->stackingOrder();
    for (EffectWindow *w : all) consider(w);
    effects->addRepaintFull();
}

void GlassKeyEffect::pushUniforms()
{
    if (!shaderOk()) return;
    ShaderBinder binder(m_shader.get());
    m_shader->setUniform("keyContent", m_content); m_shader->setUniform("keyChrome", m_chrome); m_shader->setUniform("keyText", m_text);
    m_shader->setUniform("tintContent", m_tintContent); m_shader->setUniform("tintChrome", m_tintChrome);
    m_shader->setUniform("alphaContent", m_alphaContent); m_shader->setUniform("alphaChrome", m_alphaChrome);
}

void GlassKeyEffect::consider(EffectWindow *w)
{
    if (!w || !shaderOk() || !w->window()) return;
    const bool want = w->isNormalWindow() && !w->isFullScreen()
        && (m_classes.contains(w->window()->resourceClass().toLower()) || m_classes.contains(w->window()->resourceName().toLower()));
    const bool have = m_windows.contains(w);
    if (want && !have) { redirect(w); setShader(w, m_shader.get()); m_windows.append(w); }
    else if (!want && have) { unredirect(w); m_windows.removeAll(w); }
    // some apps name themselves late. (Qt::UniqueConnection does not work with a lambda: connect once per window instead)
    // A full-screen window (a video, a game) is not glass; it comes back when it leaves full screen.
    if (!m_followed.contains(w)) {
        m_followed.insert(w);
        connect(w->window(), &Window::windowClassChanged, this, [this, w]() { consider(w); });
        connect(w, &EffectWindow::windowFullScreenChanged, this, &GlassKeyEffect::consider);
    }
}

// A window WITHOUT a server-side decoration has no window shadow: KWin's shadow is cast by the decoration. A Chromium
// picture-in-picture window (Spotify's Miniplayer) decorates itself, and leaves a transparent margin around its contents in
// its buffer (16 / 10 / 32 px) without painting a shadow there. The shader paints one into that margin: it is told where the
// contents are inside the texture. Decorated windows already have their shadow: for them the strength is 0.
void GlassKeyEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const Region &deviceRegion, WindowPaintData &data)
{
    if (shaderOk() && m_windows.contains(w)) {
        const QRectF e = w->expandedGeometry(), f = w->frameGeometry();
        const bool own = !w->hasDecoration() && e.width() > f.width() + 2 && e.height() > f.height() + 2;
        ShaderBinder binder(m_shader.get());
        m_shader->setUniform(m_loc.shadowStrength, own ? m_shadow : 0.0f);
        m_shader->setUniform(m_loc.texSizePx, QVector2D(e.width(), e.height()));
        m_shader->setUniform(m_loc.contentPx, QVector4D(f.x() - e.x(), f.y() - e.y(), f.width(), f.height()));
        m_shader->setUniform(m_loc.contentRadius, m_cornerRadius);
    }
    OffscreenEffect::drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

void GlassKeyEffect::forget(EffectWindow *w) { m_windows.removeAll(w); m_followed.remove(w); }
}
