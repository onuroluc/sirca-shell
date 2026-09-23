#pragma once
// Glass Key: per-pixel glass for apps whose toolkit always paints an opaque window (Spotify and other Chromium shells).
// The app's theme paints its SURFACES in exact, slightly tinted key colours. This effect draws the listed windows through a
// shader that un-mixes the key: a pixel on the line key -> text colour is surface (+ anti-aliased text / a control fill on
// it) and gets the surface's alpha; anything off that line (pictures, coloured controls) stays opaque. The key colour itself
// is replaced by the desktop's neutral glass tint. Blur behind the window comes from the Glass effect (ForceBlurClasses).
#include <effect/offscreeneffect.h>
#include <QSet>
#include <QStringList>
#include <QVector3D>
#include <memory>

namespace KWin
{
class GLShader;

class GlassKeyEffect : public OffscreenEffect
{
    Q_OBJECT
public:
    GlassKeyEffect();
    ~GlassKeyEffect() override;
    static bool supported();
    void reconfigure(ReconfigureFlags flags) override;
    bool isActive() const override { return !m_windows.isEmpty(); }
    int requestedEffectChainPosition() const override { return 98; }     // above the blur (it paints behind), below overlays

protected:
    void drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const Region &deviceRegion, WindowPaintData &data) override;

private:
    void consider(EffectWindow *w);
    void forget(EffectWindow *w);
    void pushUniforms();
    std::unique_ptr<GLShader> m_shader;
    struct { int shadowStrength = -1, texSizePx = -1, contentPx = -1, contentRadius = -1; } m_loc;   // per-frame uniforms
    QList<EffectWindow *> m_windows;
    QSet<EffectWindow *> m_followed;
    QStringList m_classes;
    bool shaderOk() const;
    QVector3D m_content, m_chrome, m_text, m_tintContent, m_tintChrome;
    float m_alphaContent = 0.72f, m_alphaChrome = 0.60f, m_shadow = 0.34f, m_cornerRadius = 12.0f;
};
}
