/*
 * Copyright 2014  Martin Gräßlin <mgraesslin@kde.org>
 * Copyright 2014  Hugo Pereira Da Costa <hugo.pereira@free.fr>
 * Copyright 2018  Vlad Zahorodnii <vlad.zahorodnii@kde.org>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License or (at your option) version 3 or any later version
 * accepted by the membership of KDE e.V. (or its successor approved
 * by the membership of KDE e.V.), which shall act as a proxy
 * defined in Section 14 of version 3 of the license.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "darklydecoration.h"

#include "config-darkly.h"
#include "darkly.h"
#include "darklysettingsprovider.h"

#include "darklybutton.h"

#include "darklyboxshadowrenderer.h"

#include <KDecoration3/DecorationButtonGroup>
#include <KDecoration3/DecorationShadow>
#include <KDecoration3/ScaleHelpers>

#include <KColorScheme>
#include <KColorUtils>
#include <KConfigGroup>
#include <KPluginFactory>
#include <KSharedConfig>

#include <QPainter>
#include <QTextStream>
#include <QTimer>
#include <QVariantAnimation>

#if DARKLY_HAVE_X11
#include <QX11Info>
#endif

#include <cmath>

K_PLUGIN_FACTORY_WITH_JSON(DarklyDecoFactory, "darkly.json", registerPlugin<Darkly::Decoration>(); registerPlugin<Darkly::Button>();)

namespace
{
struct ShadowParams {
    ShadowParams()
        : offset(QPoint(0, 0))
        , radius(0)
        , opacity(0)
    {
    }

    ShadowParams(const QPoint &offset, int radius, qreal opacity)
        : offset(offset)
        , radius(radius)
        , opacity(opacity)
    {
    }

    QPoint offset;
    int radius;
    qreal opacity;
};

struct CompositeShadowParams {
    CompositeShadowParams() = default;

    CompositeShadowParams(const QPoint &offset, const ShadowParams &shadow1, const ShadowParams &shadow2)
        : offset(offset)
        , shadow1(shadow1)
        , shadow2(shadow2)
    {
    }

    bool isNone() const
    {
        return qMax(shadow1.radius, shadow2.radius) == 0;
    }

    QPoint offset;
    ShadowParams shadow1;
    ShadowParams shadow2;
};

const CompositeShadowParams s_shadowParams[] = {
    // None
    CompositeShadowParams(),
    // Small
    CompositeShadowParams(QPoint(0, 4), ShadowParams(QPoint(0, 0), 16, 1), ShadowParams(QPoint(0, -2), 8, 0.4)),
    // Medium
    CompositeShadowParams(QPoint(0, 8), ShadowParams(QPoint(0, 0), 32, 0.9), ShadowParams(QPoint(0, -4), 16, 0.3)),
    // Large
    CompositeShadowParams(QPoint(0, 12), ShadowParams(QPoint(0, 0), 48, 0.8), ShadowParams(QPoint(0, -6), 24, 0.2)),
    // Very large
    CompositeShadowParams(QPoint(0, 16), ShadowParams(QPoint(0, 0), 64, 0.7), ShadowParams(QPoint(0, -8), 32, 0.1)),
};

inline CompositeShadowParams lookupShadowParams(int size)
{
    switch (size) {
    case Darkly::InternalSettings::ShadowNone:
        return s_shadowParams[0];
    case Darkly::InternalSettings::ShadowSmall:
        return s_shadowParams[1];
    case Darkly::InternalSettings::ShadowMedium:
        return s_shadowParams[2];
    case Darkly::InternalSettings::ShadowLarge:
        return s_shadowParams[3];
    case Darkly::InternalSettings::ShadowVeryLarge:
        return s_shadowParams[4];
    default:
        // Fallback to the Large size.
        return s_shadowParams[3];
    }
}
}

namespace Darkly
{

using KDecoration3::ColorGroup;
using KDecoration3::ColorRole;

//________________________________________________________________
static int g_sDecoCount = 0;
#ifndef GLASS_OUTLINE_PX
#define GLASS_OUTLINE_PX 2
#endif
static int g_shadowSizeEnum = InternalSettings::ShadowLarge;
static int g_shadowStrength = 255;
static QColor g_shadowColor = Qt::black;
static int g_outlineKey = -1;                 // the outline settings the cached shadows were drawn with (see createShadow)
static std::shared_ptr<KDecoration3::DecorationShadow> g_sShadow;
static std::shared_ptr<KDecoration3::DecorationShadow> g_sShadowActive;   // Glass: focused window
static std::shared_ptr<KDecoration3::DecorationShadow> g_sShadowBare;     // Glass: windows with a hidden title bar (widgets): shadow only
// Glass: a window corner that sits IN a corner of the screen is square, so it fills that corner (see Decoration::squareCorners).
// The shadow texture holds the edge line and the cut-out of the window shape, so every combination of square corners needs a
// texture of its own: kept here by (kind of window, corner mask). The three slots above are the mask-0 textures.
static QHash<int, std::shared_ptr<KDecoration3::DecorationShadow>> g_sShadowSquared;
enum GlassCorner { GlassTopLeft = 1, GlassTopRight = 2, GlassBottomRight = 4, GlassBottomLeft = 8 };
// a rounded rectangle with the corners in `square` left square
static QPainterPath glassCornerPath(const QRectF &r, qreal radius, int square)
{
    QPainterPath p;
    p.addRoundedRect(r, radius, radius);
    if (!square) return p;
    QPainterPath c;
    c.setFillRule(Qt::WindingFill);
    if (square & GlassTopLeft) c.addRect(QRectF(r.left(), r.top(), radius, radius));
    if (square & GlassTopRight) c.addRect(QRectF(r.right() - radius, r.top(), radius, radius));
    if (square & GlassBottomRight) c.addRect(QRectF(r.right() - radius, r.bottom() - radius, radius, radius));
    if (square & GlassBottomLeft) c.addRect(QRectF(r.left(), r.bottom() - radius, radius, radius));
    return p.united(c).simplified();
}

//________________________________________________________________
Decoration::Decoration(QObject *parent, const QVariantList &args)
    : KDecoration3::Decoration(parent, args)
    , m_animation(new QVariantAnimation(this))
{
    g_sDecoCount++;
}

//________________________________________________________________
Decoration::~Decoration()
{
    g_sDecoCount--;
    if (g_sDecoCount == 0) {
        // last deco destroyed, clean up shadow
        g_sShadow.reset();
        g_sShadowActive.reset();
        g_sShadowBare.reset();
        g_sShadowSquared.clear();
    }
}

//________________________________________________________________
void Decoration::setOpacity(qreal value)
{
    if (m_opacity == value)
        return;
    m_opacity = value;
    update();
}

//________________________________________________________________
QColor Decoration::titleBarColor() const
{
    auto c = window();
    QColor color;
    if (hideTitleBar())
        color = c->color(ColorGroup::Inactive, ColorRole::TitleBar);
    else if (m_animation->state() == QAbstractAnimation::Running)
        color = KColorUtils::mix(c->color(ColorGroup::Inactive, ColorRole::TitleBar), c->color(ColorGroup::Active, ColorRole::TitleBar), m_opacity);
    else
        color = c->color(c->isActive() ? ColorGroup::Active : ColorGroup::Inactive, ColorRole::TitleBar);
    // Glass: the frost level is ours, not the palette's (KWin's decoration palette does not reliably carry alpha)
    if (m_internalSettings) color.setAlphaF(qBound(0.2, m_internalSettings->glassTitleBarOpacity() / 100.0, 1.0));
    return color;
}
//________________________________________________________________
// Glass: the window's ONE edge line. KWin renders the decoration's border outline itself (KDecoration 6.5), perfectly
// anti-aliased and following the corner radius, so that is the lit rim — a light hairline, brighter on the focused window.
QColor Decoration::glassOutlineColor() const
{
    const bool active = window() && window()->isActive();
    return QColor(255, 255, 255, qBound(0, active ? m_internalSettings->glassOutlineActive() : m_internalSettings->glassOutlineInactive(), 255));
}

//________________________________________________________________
QColor Decoration::outlineColor() const
{
    auto c(window());
    if (!m_internalSettings->drawTitleBarSeparator())
        return QColor();
    if (m_animation->state() == QAbstractAnimation::Running) {
        QColor color(c->palette().color(QPalette::Highlight));
        color.setAlpha(color.alpha() * m_opacity);
        return color;
    } else if (c->isActive())
        return c->palette().color(QPalette::Highlight);
    else
        return QColor();
}

//________________________________________________________________
QColor Decoration::fontColor() const
{
    auto c = window();
    return c->color(c->isActive() ? ColorGroup::Active : ColorGroup::Inactive, ColorRole::Foreground);
}

//________________________________________________________________
bool Decoration::init()
{
    auto c = window();

    // active state change animation
    // It is important start and end value are of the same type, hence 0.0 and not just 0
    m_animation->setStartValue(0.0);
    m_animation->setEndValue(1.0);
    m_animation->setEasingCurve(QEasingCurve::InOutQuad);
    connect(m_animation, &QVariantAnimation::valueChanged, this, [this](const QVariant &value) {
        setOpacity(value.toReal());
    });

    reconfigure();
    updateTitleBar();
    updateBlur();
    auto s = settings();
    connect(s.get(), &KDecoration3::DecorationSettings::borderSizeChanged, this, &Decoration::recalculateBorders);

    // a change in font might cause the borders to change
    connect(s.get(), &KDecoration3::DecorationSettings::fontChanged, this, &Decoration::recalculateBorders);
    connect(s.get(), &KDecoration3::DecorationSettings::spacingChanged, this, &Decoration::recalculateBorders);

    // buttons
    connect(s.get(), &KDecoration3::DecorationSettings::spacingChanged, this, &Decoration::updateButtonsGeometryDelayed);
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsLeftChanged, this, &Decoration::updateButtonsGeometryDelayed);
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsRightChanged, this, &Decoration::updateButtonsGeometryDelayed);

    // full reconfiguration
    connect(s.get(), &KDecoration3::DecorationSettings::reconfigured, this, &Decoration::reconfigure);
    connect(s.get(), &KDecoration3::DecorationSettings::reconfigured, SettingsProvider::self(), &SettingsProvider::reconfigure, Qt::UniqueConnection);
    connect(s.get(), &KDecoration3::DecorationSettings::reconfigured, this, &Decoration::updateButtonsGeometryDelayed);

    connect(window(), &KDecoration3::DecoratedWindow::activeChanged, this, &Decoration::recalculateBorders);
    connect(c, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, &Decoration::recalculateBorders);
    connect(c, &KDecoration3::DecoratedWindow::maximizedHorizontallyChanged, this, &Decoration::recalculateBorders);
    connect(c, &KDecoration3::DecoratedWindow::maximizedVerticallyChanged, this, &Decoration::recalculateBorders);
    connect(c, &KDecoration3::DecoratedWindow::shadedChanged, this, &Decoration::recalculateBorders);
    connect(c, &KDecoration3::DecoratedWindow::captionChanged, this, [this]() {
        // update the caption area
        update(titleBar());
    });

    connect(c, &KDecoration3::DecoratedWindow::activeChanged, this, &Decoration::updateAnimationState);
    connect(c, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, &Decoration::updateTitleBar);
    connect(this, &KDecoration3::Decoration::bordersChanged, this, &Decoration::updateTitleBar);

    connect(c, &KDecoration3::DecoratedWindow::activeChanged, this, &Decoration::updateBlur);
    connect(c, &KDecoration3::DecoratedWindow::activeChanged, this, &Decoration::createShadow);   // Glass: focus glow
    connect(c, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, &Decoration::createShadow);   // Glass: square corners
    connect(c, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, &Decoration::updateBlur);
    connect(c, &KDecoration3::DecoratedWindow::widthChanged, this, &Decoration::updateTitleBar);
    connect(c, &KDecoration3::DecoratedWindow::maximizedChanged, this, &Decoration::updateTitleBar);

    connect(c, &KDecoration3::DecoratedWindow::sizeChanged, this, &Decoration::updateBlur); // recalculate blur region on resize

    connect(c, &KDecoration3::DecoratedWindow::widthChanged, this, &Decoration::updateButtonsGeometry);
    connect(c, &KDecoration3::DecoratedWindow::maximizedChanged, this, &Decoration::updateButtonsGeometry);
    connect(c, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, &Decoration::updateButtonsGeometry);
    connect(c, &KDecoration3::DecoratedWindow::shadedChanged, this, &Decoration::updateButtonsGeometry);

    // shade button doesn't resize properly so this is now required
    connect(this, &KDecoration3::Decoration::bordersChanged, this, &Decoration::updateButtonsGeometryDelayed);

    createButtons();
    createShadow();
    return true;
}

//________________________________________________________________
void Decoration::updateBlur()
{
if (m_internalSettings->floatingTitlebar()){
    auto c = window();
    const QColor titleBarColor = this->titleBarColor();

    // set opaque to false when non-maximized, regardless of color (prevents kornerbug)
    if (titleBarColor.alpha() == 255) {
        this->setOpaque(c->isMaximized());
    } else {
        this->setOpaque(false);
    }

    // Recalculate window shapes
    calculateWindowAndTitleBarShapes(true);

    // Get window rectangle as integers
    QRect windowRect(QPoint(0, 0), c->size().toSize());

    // Height of the blur region
    const int blurHeight = (buttonSize() + (Metrics::TitleBar_TopMargin * 2) + 8);

    // Corner radius
    const qreal blurRadius = c->isMaximized() ? 0.0 : m_scaledCornerRadius;

    // Create a rounded rectangle path for the top strip
    QPainterPath path;
    path.addRoundedRect(QRectF(0, 0, windowRect.width(), blurHeight), blurRadius, blurRadius);

    // Convert path to QRegion and set as blur region
    QRegion blurRegion(path.toFillPolygon().toPolygon());
    this->setBlurRegion(blurRegion);
} else {
    auto c = window();
    const QColor titleBarColor = this->titleBarColor();

    // set opaque to false when non-maximized, regardless of color (prevents kornerbug)
    if (titleBarColor.alpha() == 255) {
        this->setOpaque(c->isMaximized());
    } else {
        this->setOpaque(false);
    }

    calculateWindowAndTitleBarShapes(true);
    this->setBlurRegion(QRegion(m_windowPath->toFillPolygon().toPolygon()));
}
}

//________________________________________________________________
void Decoration::calculateWindowAndTitleBarShapes(const bool windowShapeOnly)
{
if (m_internalSettings->floatingTitlebar()){
    auto c = window();
    auto s = settings();

    const qreal shrinkAmount = !isMaximized() ? 4 : 0; // shrink decoration height by 5px

    // --- Title Bar ---
    if (!windowShapeOnly || c->isShaded()) {
        int titleHeight = std::max(int(borderTop() - shrinkAmount), 0);
        m_titleRect = QRect(QPoint(0, 0), QSize(size().width(), titleHeight));

        // Clear previous path
        m_titleBarPath->clear();

        if (isMaximized() || !s->isAlphaChannelSupported()) {
            m_titleBarPath->addRect(m_titleRect);
        } else {
            m_titleBarPath->addRoundedRect(m_titleRect, m_scaledCornerRadius, m_scaledCornerRadius);
        }
    }

    // --- Window Shape ---
    m_windowPath->clear();

    if (!c->isShaded()) {
        QRect adjustedRect = rect().toRect();
        adjustedRect.setHeight(std::max(adjustedRect.height() - int(shrinkAmount), 0));

        if (s->isAlphaChannelSupported() && !isMaximized()) {
            m_windowPath->addRoundedRect(adjustedRect, m_scaledCornerRadius, m_scaledCornerRadius);
        } else {
            m_windowPath->addRect(adjustedRect);
        }
    } else {
        *m_windowPath = *m_titleBarPath;
    }
} else {
    auto c = window();
    auto s = settings();

    if (!windowShapeOnly || c->isShaded()) {
        // set titleBar geometry and path
        m_titleRect = QRect(QPoint(0, 0), QSize(size().width(), borderTop()));
        m_titleBarPath->clear(); // clear the path for subsequent calls to this function
        if (isMaximized() || !s->isAlphaChannelSupported()) {
            m_titleBarPath->addRect(m_titleRect);

        } else if (c->isShaded()) {
            m_titleBarPath->addRoundedRect(m_titleRect, m_scaledCornerRadius, m_scaledCornerRadius);

        } else {
            QPainterPath clipRect;
            clipRect.addRect(m_titleRect);

            // the rect is made a little bit larger to be able to clip away the rounded corners at the bottom.
            // Glass: a top corner is square only when it sits in a corner of the screen (it used to go square as soon as ONE
            // of its edges touched: a window tiled to the left half lost both left corners AND both top corners)
            *m_titleBarPath = glassCornerPath(QRectF(m_titleRect.adjusted(0, 0, 0, m_scaledCornerRadius)), m_scaledCornerRadius, squareCorners());

            *m_titleBarPath = m_titleBarPath->intersected(clipRect);
        }
    }

    // set windowPath
    m_windowPath->clear(); // clear the path for subsequent calls to this function
    if (!c->isShaded()) {
        if (s->isAlphaChannelSupported() && !isMaximized())
            *m_windowPath = glassCornerPath(rect(), m_scaledCornerRadius, squareCorners());
        else
            m_windowPath->addRect(rect());

    } else {
        *m_windowPath = *m_titleBarPath;
    }
}
}

//________________________________________________________________
void Decoration::updateTitleBar()
{
    // The titlebar rect has margins around it so the window can be resized by dragging a decoration edge.
    auto s = settings();
    const bool maximized = isMaximized();
    const qreal width = maximized ? window()->width() : window()->width() - 2 * s->smallSpacing() * Metrics::TitleBar_SideMargin;
    const qreal height = (maximized || isTopEdge()) ? borderTop() : borderTop() - s->smallSpacing() * Metrics::TitleBar_TopMargin;
    const qreal x = maximized ? 0 : s->smallSpacing() * Metrics::TitleBar_SideMargin;
    const qreal y = (maximized || isTopEdge()) ? 0 : s->smallSpacing() * Metrics::TitleBar_TopMargin;
    setTitleBar(QRectF(x, y, width, height));
}

//________________________________________________________________
void Decoration::updateAnimationState()
{
    if (m_internalSettings->animationsEnabled()) {
        auto c = window();
        m_animation->setDirection(c->isActive() ? QAbstractAnimation::Forward : QAbstractAnimation::Backward);
        if (m_animation->state() != QAbstractAnimation::Running)
            m_animation->start();

    } else {
        update();
    }
}

//________________________________________________________________
qreal Decoration::borderSize(bool bottom, qreal scale) const
{
    const qreal pixelSize = KDecoration3::pixelSize(scale);
    const qreal baseSize = std::max<qreal>(pixelSize, KDecoration3::snapToPixelGrid(settings()->smallSpacing(), scale));

    if (m_internalSettings && (m_internalSettings->mask() & BorderSize)) {
        switch (m_internalSettings->borderSize()) {
        case InternalSettings::BorderNone:
            return 0;
        case InternalSettings::BorderNoSides:
            if (bottom) {
                return KDecoration3::snapToPixelGrid(std::max(4.0, baseSize + Metrics::Frame_FrameRadius), scale);
            } else {
                return 0;
            }
        default:
        case InternalSettings::BorderTiny:
            if (bottom) {
                return KDecoration3::snapToPixelGrid(std::max(4.0, baseSize), scale);
            } else {
                return baseSize;
            }
        case InternalSettings::BorderNormal:
            return baseSize * 2;
        case InternalSettings::BorderLarge:
            return baseSize * 3;
        case InternalSettings::BorderVeryLarge:
            return baseSize * 4;
        case InternalSettings::BorderHuge:
            return baseSize * 5;
        case InternalSettings::BorderVeryHuge:
            return baseSize * 6;
        case InternalSettings::BorderOversized:
            return baseSize * 10;
        }

    } else {
        switch (settings()->borderSize()) {
        case KDecoration3::BorderSize::None:
            return 0;
        case KDecoration3::BorderSize::NoSides:
            if (bottom) {
                return KDecoration3::snapToPixelGrid(std::max(4.0, baseSize + Metrics::Frame_FrameRadius), scale);
            } else {
                return 0;
            }
        default:
        case KDecoration3::BorderSize::Tiny:
            if (bottom) {
                return KDecoration3::snapToPixelGrid(std::max(4.0, baseSize), scale);
            } else {
                return baseSize;
            }
        case KDecoration3::BorderSize::Normal:
            return baseSize * 2;
        case KDecoration3::BorderSize::Large:
            return baseSize * 3;
        case KDecoration3::BorderSize::VeryLarge:
            return baseSize * 4;
        case KDecoration3::BorderSize::Huge:
            return baseSize * 5;
        case KDecoration3::BorderSize::VeryHuge:
            return baseSize * 6;
        case KDecoration3::BorderSize::Oversized:
            return baseSize * 10;
        }
    }
}

//________________________________________________________________
void Decoration::reconfigure()
{
    m_internalSettings = SettingsProvider::self()->internalSettings(this);

    setScaledCornerRadius();

    // animation
    m_animation->setDuration(m_internalSettings->animationsDuration());

    // borders
    recalculateBorders();

    // shadow
    createShadow();

    updateBlur();
}

//________________________________________________________________
void Decoration::recalculateBorders()
{
if (m_internalSettings->floatingTitlebar()){
    const qreal scale = window()->nextScale();
    setBorders(bordersFor(scale));

    const qreal extSize = KDecoration3::snapToPixelGrid(settings()->largeSpacing(), scale);
    qreal extSides = 0;
    qreal extBottom = 0;

    if (hasNoBorders()) {
        if (!isMaximizedHorizontally()) extSides = extSize;
        if (!isMaximizedVertically())   extBottom = extSize;
    } else if (hasNoSideBorders() && !isMaximizedHorizontally()) {
        extSides = extSize;
    }

    setResizeOnlyBorders(QMarginsF(extSides, 0, extSides, extBottom));
#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
    qreal topLeftRadius = 0;
    qreal topRightRadius = 0;
    qreal bottomLeftRadius = 0;
    qreal bottomRightRadius = 0;

    if (m_internalSettings->roundedCorners()) {
        // Glass: per corner (see squareCorners)
        const int sq = squareCorners();
        if (!(sq & GlassTopLeft)) topLeftRadius = m_scaledCornerRadius;
        if (!(sq & GlassTopRight)) topRightRadius = m_scaledCornerRadius;
        if (!(sq & GlassBottomLeft)) bottomLeftRadius = m_scaledCornerRadius;
        if (!(sq & GlassBottomRight)) bottomRightRadius = m_scaledCornerRadius;
    }
#endif
#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
    setBorderRadius(KDecoration3::BorderRadius(topLeftRadius, topRightRadius, bottomRightRadius, bottomLeftRadius));
#endif

    if (true) {   // Glass: never KWin's border outline — it stops at the corners and doubles our edge line (see createShadow)
#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
        setBorderOutline(KDecoration3::BorderOutline()); // no outline
#endif
    } else {
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0) && KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
        const auto color = KColorUtils::mix(
            window()->color(window()->isActive() ? ColorGroup::Active : ColorGroup::Inactive,
                            ColorRole::Frame),
                            window()->palette().text().color(),
                                            KColorScheme::frameContrast()
        );
#else
        KColorUtils::mix(window()->color(window()->isActive() ? ColorGroup::Active : ColorGroup::Inactive, ColorRole::Frame),
                         window()->palette().text().color(),
                         0.2);
#endif

#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
        const qreal thickness = std::max(KDecoration3::pixelSize(window()->scale()),
                                         KDecoration3::snapToPixelGrid(GLASS_OUTLINE_PX, window()->scale()));
#endif
#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
        const KDecoration3::BorderRadius outlineRadius(
            topLeftRadius, topRightRadius, bottomRightRadius, bottomLeftRadius
        );

        setBorderOutline(KDecoration3::BorderOutline(thickness, glassOutlineColor(), outlineRadius));
#endif
    }
} else {
    setBorders(bordersFor(window()->nextScale()));

    // extended sizes
    const qreal extSize = KDecoration3::snapToPixelGrid(settings()->largeSpacing(), window()->nextScale());
    qreal extSides = 0;
    qreal extBottom = 0;
    if (hasNoBorders()) {
        if (!isMaximizedHorizontally()) {
            extSides = extSize;
        }
        if (!isMaximizedVertically()) {
            extBottom = extSize;
        }

    } else if (hasNoSideBorders() && !isMaximizedHorizontally()) {
        extSides = extSize;
    }

    setResizeOnlyBorders(QMarginsF(extSides, 0, extSides, extBottom));
#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
    qreal bottomLeftRadius = 0;
    qreal bottomRightRadius = 0;

    if (hasNoBorders() && m_internalSettings->roundedCorners()) {
        // Glass: per corner (see squareCorners). It used to be: no bottom radius at all once ANY of the three edges touched.
        const int sq = squareCorners();
        if (!(sq & GlassBottomLeft)) bottomLeftRadius = m_scaledCornerRadius;
        if (!(sq & GlassBottomRight)) bottomRightRadius = m_scaledCornerRadius;
    }
#endif
#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
    setBorderRadius(KDecoration3::BorderRadius(0, 0, bottomRightRadius, bottomLeftRadius));
#endif
    if (true) {   // Glass: never KWin's border outline — it stops at the corners and doubles our edge line (see createShadow)
#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
        setBorderOutline(KDecoration3::BorderOutline());
#endif
    } else {
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0) && KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
        const auto color = KColorUtils::mix(window()->color(window()->isActive() ? ColorGroup::Active : ColorGroup::Inactive, ColorRole::Frame),
                                            window()->palette().text().color(),
                                            KColorScheme::frameContrast());
#else
        KColorUtils::mix(window()->color(window()->isActive() ? ColorGroup::Active : ColorGroup::Inactive, ColorRole::Frame),
                         window()->palette().text().color(),
                         0.2);
#endif

#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
        const qreal thickness = std::max(KDecoration3::pixelSize(window()->scale()), KDecoration3::snapToPixelGrid(GLASS_OUTLINE_PX, window()->scale()));

        qreal bottomLeftRadius = 0;
        qreal bottomRightRadius = 0;

        if (!hasNoBorders() || m_internalSettings->roundedCorners()) {
            bottomLeftRadius = m_scaledCornerRadius;
            bottomRightRadius = m_scaledCornerRadius;
        }
#endif

#if KDECORATION_VERSION >= KDECORATION_VERSION_CHECK(6, 5, 0)
        const auto radius = KDecoration3::BorderRadius(m_scaledCornerRadius, m_scaledCornerRadius, bottomRightRadius, bottomLeftRadius);
        setBorderOutline(KDecoration3::BorderOutline(thickness, glassOutlineColor(), radius));
#endif
    }
}
}


//________________________________________________________________
void Decoration::createButtons()
{
    m_leftButtons = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Left, this, &Button::create);
    m_rightButtons = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Right, this, &Button::create);
    updateButtonsGeometry();
}

//________________________________________________________________
void Decoration::updateButtonsGeometryDelayed()
{
    QTimer::singleShot(0, this, &Decoration::updateButtonsGeometry);
}

//________________________________________________________________
void Decoration::updateButtonsGeometry()
{
if (m_internalSettings->floatingTitlebar()){
    const auto s = settings();

    // adjust button position
    const auto buttonList = m_leftButtons->buttons() + m_rightButtons->buttons();
    for (KDecoration3::DecorationButton *button : buttonList) {
        auto btn = static_cast<Button *>(button);

        // vertical offset reduced to move buttons up
        const int verticalOffset = (isTopEdge() ? s->smallSpacing() * Metrics::TitleBar_TopMargin : 0) + (isMaximized() ? 0 : 1);

        const QSizeF preferredSize = btn->preferredSize();
        const int bHeight = preferredSize.height() + verticalOffset;
        const int bWidth = preferredSize.width();

        btn->setGeometry(QRectF(QPoint(0, 0), QSizeF(bWidth, bHeight)));
        btn->setPadding(QMargins(0, verticalOffset, 0, 0));
        btn->setOffset(QPointF(0, verticalOffset));
        btn->setIconSize(QSizeF(bHeight, bWidth));
    }

    // left buttons
    if (!m_leftButtons->buttons().isEmpty()) {
        // spacing
        m_leftButtons->setSpacing(s->smallSpacing() * Metrics::TitleBar_ButtonSpacing);

        // padding
        int vPadding = (isTopEdge() ? 0 : s->smallSpacing() * Metrics::TitleBar_TopMargin) + (isMaximized() ? 0 : 1);
        const int hPadding = s->smallSpacing() * Metrics::TitleBar_SideMargin;

        if (isLeftEdge()) {
            // add offsets on the side buttons, to preserve padding, but satisfy Fitts law
            auto button = static_cast<Button *>(m_leftButtons->buttons().front());

            QRectF geometry = button->geometry();
            geometry.adjust(-hPadding, 0, 0, 0);
            button->setGeometry(geometry);
            button->setFlag(Button::FlagFirstInList);
            button->setLeftPadding(hPadding);
            button->setIconSize(button->preferredSize());

            m_leftButtons->setPos(QPointF(0, vPadding));

        } else {
            m_leftButtons->setPos(QPointF(hPadding + borderLeft(), vPadding));
        }
    }

    // right buttons
    if (!m_rightButtons->buttons().isEmpty()) {
        // spacing
        m_rightButtons->setSpacing(s->smallSpacing() * Metrics::TitleBar_ButtonSpacing);

        // padding
        int vPadding = (isTopEdge() ? 0 : s->smallSpacing() * Metrics::TitleBar_TopMargin) + (isMaximized() ? 0 : 1);
        const int hPadding = s->smallSpacing() * Metrics::TitleBar_SideMargin;

        if (isRightEdge()) {
            auto button = static_cast<Button *>(m_rightButtons->buttons().back());

            QRectF geometry = button->geometry();
            geometry.adjust(0, 0, hPadding, 0);
            button->setGeometry(geometry);
            button->setFlag(Button::FlagFirstInList);
            button->setRightPadding(hPadding);
            button->setIconSize(button->preferredSize());

            m_rightButtons->setPos(QPointF(size().width() - m_rightButtons->geometry().width(), vPadding));

        } else {
            m_rightButtons->setPos(QPointF(size().width() - m_rightButtons->geometry().width() - hPadding - borderRight(), vPadding));
        }
    }

    {   // Glass: centre both button groups in the title bar, whatever its height
        const qreal cy = std::max<qreal>(0, (borderTop() - buttonSize()) / 2.0);
        if (!m_leftButtons->buttons().isEmpty()) m_leftButtons->setPos(QPointF(m_leftButtons->pos().x(), cy));
        if (!m_rightButtons->buttons().isEmpty()) m_rightButtons->setPos(QPointF(m_rightButtons->pos().x(), cy));
    }
    update();
} else {
    const auto s = settings();

    // adjust button position
    const auto buttonList = m_leftButtons->buttons() + m_rightButtons->buttons();
    for (KDecoration3::DecorationButton *button : buttonList) {
        auto btn = static_cast<Button *>(button);

        const int verticalOffset = (isTopEdge() ? s->smallSpacing() * Metrics::TitleBar_TopMargin : 0);

        const QSizeF preferredSize = btn->preferredSize();
        const int bHeight = preferredSize.height() + verticalOffset;
        const int bWidth = preferredSize.width();

        btn->setGeometry(QRectF(QPoint(0, 0), QSizeF(bWidth, bHeight)));
        btn->setPadding(QMargins(0, verticalOffset, 0, 0));
        btn->setOffset(QPointF(0, verticalOffset));
        btn->setIconSize(QSizeF(bHeight, bWidth));
    }

    // left buttons
    if (!m_leftButtons->buttons().isEmpty()) {
        // spacing
        m_leftButtons->setSpacing(s->smallSpacing() * Metrics::TitleBar_ButtonSpacing);

        // padding
        const int vPadding = isTopEdge() ? 0 : s->smallSpacing() * Metrics::TitleBar_TopMargin;
        const int hPadding = s->smallSpacing() * Metrics::TitleBar_SideMargin;
        if (isLeftEdge()) {
            // add offsets on the side buttons, to preserve padding, but satisfy Fitts law
            auto button = static_cast<Button *>(m_leftButtons->buttons().front());

            QRectF geometry = button->geometry();
            geometry.adjust(-hPadding, 0, 0, 0);
            button->setGeometry(geometry);
            button->setFlag(Button::FlagFirstInList);
            button->setLeftPadding(hPadding);
            button->setIconSize(button->preferredSize());

            m_leftButtons->setPos(QPointF(0, vPadding));

        } else {
            m_leftButtons->setPos(QPointF(hPadding + borderLeft(), vPadding));
        }
    }

    // right buttons
    if (!m_rightButtons->buttons().isEmpty()) {
        // spacing
        m_rightButtons->setSpacing(s->smallSpacing() * Metrics::TitleBar_ButtonSpacing);

        // padding
        const int vPadding = isTopEdge() ? 0 : s->smallSpacing() * Metrics::TitleBar_TopMargin;
        const int hPadding = s->smallSpacing() * Metrics::TitleBar_SideMargin;
        if (isRightEdge()) {
            auto button = static_cast<Button *>(m_rightButtons->buttons().back());

            QRectF geometry = button->geometry();
            geometry.adjust(0, 0, hPadding, 0);
            button->setGeometry(geometry);
            button->setFlag(Button::FlagFirstInList);
            button->setRightPadding(hPadding);
            button->setIconSize(button->preferredSize());

            m_rightButtons->setPos(QPointF(size().width() - m_rightButtons->geometry().width(), vPadding));

        } else {
            m_rightButtons->setPos(QPointF(size().width() - m_rightButtons->geometry().width() - hPadding - borderRight(), vPadding));
        }
    }

    {   // Glass: centre both button groups in the title bar, whatever its height
        const qreal cy = std::max<qreal>(0, (borderTop() - buttonSize()) / 2.0);
        if (!m_leftButtons->buttons().isEmpty()) m_leftButtons->setPos(QPointF(m_leftButtons->pos().x(), cy));
        if (!m_rightButtons->buttons().isEmpty()) m_rightButtons->setPos(QPointF(m_rightButtons->pos().x(), cy));
    }
    update();
}
}

//________________________________________________________________
void Decoration::paint(QPainter *painter, const QRectF &repaintRegion)
{
    // TODO: optimize based on repaintRegion
    auto c = window();
    auto s = settings();

    calculateWindowAndTitleBarShapes();

    // paint background
    if (!c->isShaded()) {
        painter->fillRect(rect(), Qt::transparent);
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing);
        painter->setPen(Qt::NoPen);
        painter->setBrush(c->color(c->isActive() ? ColorGroup::Active : ColorGroup::Inactive, ColorRole::Frame));

        // clip away the top part
        if (!hideTitleBar())
            painter->setClipRect(0, borderTop(), size().width(), size().height() - borderTop(), Qt::IntersectClip);

        if (s->isAlphaChannelSupported())
            painter->drawPath(glassCornerPath(rect(), m_scaledCornerRadius, squareCorners()));
        else
            painter->drawRect(rect());

        painter->restore();
    }

    if (!hideTitleBar())
        paintTitleBar(painter, repaintRegion);

    if (hasBorders() && !s->isAlphaChannelSupported()) {
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, false);
        painter->setBrush(Qt::NoBrush);
        painter->setPen(c->isActive() ? c->color(ColorGroup::Active, ColorRole::TitleBar) : c->color(ColorGroup::Inactive, ColorRole::Foreground));

        painter->drawRect(rect().adjusted(0, 0, -1, -1));
        painter->restore();
    }
}

//________________________________________________________________
void Decoration::paintTitleBar(QPainter *painter, const QRectF &repaintRegion)
{
    const auto c = window();
    QRectF rect(QPointF(0, 0), QSizeF(size().width(), borderTop()));
    QBrush frontBrush;
    QBrush backBrush(this->titleBarColor());

    if (!rect.intersects(repaintRegion)) {
        return;
    }

    painter->save();
    painter->setPen(Qt::NoPen);

    // render a linear gradient on title area
    if (c->isActive() && m_internalSettings->drawBackgroundGradient()) {
        const QColor titleBarColor(this->titleBarColor());
        QLinearGradient gradient(0, 0, 0, m_titleRect.height());
        gradient.setColorAt(0.0, titleBarColor.lighter(120));
        gradient.setColorAt(0.8, titleBarColor);
        painter->setBrush(gradient);

    } else {
        painter->setBrush(titleBarColor());
    }

    auto s = settings();
    painter->drawPath(*m_titleBarPath);

    // Glass: no separate rim here — the window's ONE outline (drawn in the shadow texture, see createShadow) is the lit
    // edge: bright along the top and round the corners, softer down the sides and along the bottom.

    // top highlight
    if (false && qGray(this->titleBarColor().rgb()) < 130 && m_internalSettings->drawHighlight()) {   // Glass: one edge line only (KWin's outline)
        if (isMaximized() || !s->isAlphaChannelSupported()) {
            painter->setPen(QColor(255, 255, 255, 30));
            painter->drawLine(m_titleRect.topLeft(), m_titleRect.topRight());

        } else if (!c->isShaded()) {
            QRect copy(m_titleRect.adjusted(isLeftEdge() ? -m_scaledCornerRadius : 0,
                                            isTopEdge() ? -m_scaledCornerRadius : 0,
                                            isRightEdge() ? m_scaledCornerRadius : 0,
                                            m_scaledCornerRadius));

            QPixmap pix = QPixmap(copy.width(), copy.height());
            pix.fill(Qt::transparent);

            QPainter p(&pix);
            p.setRenderHint(QPainter::Antialiasing);
            p.setPen(Qt::NoPen);
            p.setBrush(QColor(255, 255, 255, 30));
            p.drawRoundedRect(copy, m_scaledCornerRadius, m_scaledCornerRadius);

            p.setBrush(Qt::black);
            p.setCompositionMode(QPainter::CompositionMode_DestinationOut);
            p.drawRoundedRect(copy.adjusted(0, 1, 0, 3), m_scaledCornerRadius, m_scaledCornerRadius);

            painter->drawPixmap(copy, pix);
        }
    }

    const QColor outlineColor(this->outlineColor());
    if (!c->isShaded() && outlineColor.isValid()) {
        // outline
        painter->setRenderHint(QPainter::Antialiasing, false);
        painter->setBrush(Qt::NoBrush);
        painter->setPen(outlineColor);
        painter->drawLine(m_titleRect.bottomLeft(), m_titleRect.bottomRight());
    }

    painter->restore();
if (m_internalSettings->floatingTitlebar()){

    // draw caption
    painter->setFont(s->font());
    painter->setPen(fontColor());
    const auto cR = captionRect();

    // Move caption up by 2 pixels
    QRectF captionRectMoved = cR.first;
    if (!isMaximized())
    captionRectMoved.translate(0, -2.0); // floating-point translation
    const QString caption = painter->fontMetrics().elidedText(
        c->caption(), Qt::ElideMiddle, int(captionRectMoved.width())
    );
    painter->drawText(captionRectMoved, cR.second | Qt::TextSingleLine, caption);

    // draw all buttons
    m_leftButtons->paint(painter, repaintRegion);
    m_rightButtons->paint(painter, repaintRegion);
} else {
    // draw caption
    painter->setFont(s->font());
    painter->setPen(fontColor());
    const auto cR = captionRect();
    const QString caption = painter->fontMetrics().elidedText(c->caption(), Qt::ElideMiddle, cR.first.width());
    painter->drawText(cR.first, cR.second | Qt::TextSingleLine, caption);

    // draw all buttons
    m_leftButtons->paint(painter, repaintRegion);
    m_rightButtons->paint(painter, repaintRegion);
}
}

//________________________________________________________________
int Decoration::buttonSize() const
{
    // Glass: a round dot of GlassDotSize px inside a slightly larger hit area
    return m_internalSettings->glassDotSize() + 8;
}

//________________________________________________________________
int Decoration::captionHeight() const
{
    return hideTitleBar() ? borderTop() : borderTop() - settings()->smallSpacing() * (Metrics::TitleBar_BottomMargin + Metrics::TitleBar_TopMargin) - 1;
}

//________________________________________________________________
QPair<QRectF, Qt::Alignment> Decoration::captionRect() const
{
    if (hideTitleBar())
        return qMakePair(QRect(), Qt::AlignCenter);
    else {
        auto c = window();
        const qreal leftOffset = KDecoration3::snapToPixelGrid(m_leftButtons->buttons().isEmpty() ? Metrics::TitleBar_SideMargin * settings()->smallSpacing()
                                                                                       : m_leftButtons->geometry().x() + m_leftButtons->geometry().width()
                                                            + Metrics::TitleBar_SideMargin * settings()->smallSpacing(), window()->scale());

        const qreal rightOffset = KDecoration3::snapToPixelGrid(m_rightButtons->buttons().isEmpty() ? Metrics::TitleBar_SideMargin * settings()->smallSpacing()
                                                                                         : size().width() - m_rightButtons->geometry().x()
                                                             + Metrics::TitleBar_SideMargin * settings()->smallSpacing(), window()->scale());

        const qreal yOffset = KDecoration3::snapToPixelGrid(settings()->smallSpacing() * Metrics::TitleBar_TopMargin, window()->scale());
        const QRectF maxRect(leftOffset, yOffset, size().width() - leftOffset - rightOffset, captionHeight());

        switch (m_internalSettings->titleAlignment()) {
        case InternalSettings::AlignLeft:
            return qMakePair(maxRect, Qt::AlignVCenter | Qt::AlignLeft);

        case InternalSettings::AlignRight:
            return qMakePair(maxRect, Qt::AlignVCenter | Qt::AlignRight);

        case InternalSettings::AlignCenter:
            return qMakePair(maxRect, Qt::AlignCenter);

        default:
        case InternalSettings::AlignCenterFullWidth: {
            // full caption rect
            const QRectF fullRect = QRect(0, yOffset, size().width(), captionHeight());
            QRectF boundingRect(settings()->fontMetrics().boundingRect(c->caption()));

            // text bounding rect
            boundingRect.setTop(yOffset);
            boundingRect.setHeight(captionHeight());
            boundingRect.moveLeft((size().width() - boundingRect.width()) / 2);

            if (boundingRect.left() < leftOffset)
                return qMakePair(maxRect, Qt::AlignVCenter | Qt::AlignLeft);
            else if (boundingRect.right() > size().width() - rightOffset)
                return qMakePair(maxRect, Qt::AlignVCenter | Qt::AlignRight);
            else
                return qMakePair(fullRect, Qt::AlignCenter);
        }
        }
    }
}

//________________________________________________________________
void Decoration::createShadow()
{
    // Glass: the focused window has its own shadow texture (light hairline + a very faint glow); everything else shares one
    const bool glassActive = window() && window()->isActive();
    // Glass: a window whose title bar is hidden by an exception is a WIDGET that draws itself edge to edge (a Chromium
    // picture-in-picture window clips its contents with its OWN corner radius, which is not ours). An edge line drawn here
    // at the decoration's radius cannot meet such a window's corners: the surface stopped short of the line. Those windows
    // get the shadow only, and draw their own rim.
    const bool bare = hideTitleBar();
    const int sq = isMaximized() ? 0 : squareCorners();       // a maximized window shows neither its shadow nor its line
    const int kind = bare ? 2 : (glassActive ? 1 : 0);
    // the outline is part of the texture: a change of its width, alpha or arc boost must redraw the cached shadows too
    const int outlineKey = m_internalSettings->glassOutlineWidthActive() * 1000003 ^ m_internalSettings->glassOutlineWidthInactive() * 10007 ^ m_internalSettings->glassOutlineActive() * 131 ^ m_internalSettings->glassOutlineInactive() * 17 ^ m_internalSettings->glassOutlineArcActive() * 3 ^ m_internalSettings->glassOutlineArcInactive();
    if (g_shadowSizeEnum != m_internalSettings->shadowSize() || g_shadowStrength != m_internalSettings->shadowStrength() || g_shadowColor != m_internalSettings->shadowColor() || g_outlineKey != outlineKey) { g_sShadow.reset(); g_sShadowActive.reset(); g_sShadowBare.reset(); g_sShadowSquared.clear(); }
    std::shared_ptr<KDecoration3::DecorationShadow> &slot = sq ? g_sShadowSquared[kind * 16 + sq] : (bare ? g_sShadowBare : (glassActive ? g_sShadowActive : g_sShadow));
    if (!slot || g_shadowSizeEnum != m_internalSettings->shadowSize() || g_shadowStrength != m_internalSettings->shadowStrength()
        || g_shadowColor != m_internalSettings->shadowColor() || g_outlineKey != outlineKey) {
        g_shadowSizeEnum = m_internalSettings->shadowSize();
        g_shadowStrength = m_internalSettings->shadowStrength();
        g_shadowColor = m_internalSettings->shadowColor();
        g_outlineKey = outlineKey;

        const CompositeShadowParams params = lookupShadowParams(g_shadowSizeEnum);
        if (params.isNone()) {
            slot.reset();
            setShadow(slot);
            return;
        }

        auto withOpacity = [](const QColor &color, qreal opacity) -> QColor {
            QColor c(color);
            c.setAlphaF(opacity);
            return c;
        };

        const QSize boxSize =
            BoxShadowRenderer::calculateMinimumBoxSize(params.shadow1.radius).expandedTo(BoxShadowRenderer::calculateMinimumBoxSize(params.shadow2.radius));

        BoxShadowRenderer shadowRenderer;
        shadowRenderer.setBorderRadius(m_scaledCornerRadius + 0.5);
        shadowRenderer.setBoxSize(boxSize);

        const qreal strength = static_cast<qreal>(g_shadowStrength) / 255.0;
        shadowRenderer.addShadow(params.shadow1.offset, params.shadow1.radius, withOpacity(g_shadowColor, params.shadow1.opacity * strength));
        shadowRenderer.addShadow(params.shadow2.offset, params.shadow2.radius, withOpacity(g_shadowColor, params.shadow2.opacity * strength));
        if (glassActive && m_internalSettings->glassFocusGlow()) shadowRenderer.addShadow(QPoint(0, 0), 18, QColor(255, 255, 255, 22));   // Glass: focus glow, a real blur — no edges

        QImage shadowTexture = shadowRenderer.render();

        QPainter painter(&shadowTexture);
        painter.setRenderHint(QPainter::Antialiasing);

        const QRect outerRect = shadowTexture.rect();

        QRect boxRect(QPoint(0, 0), boxSize);
        boxRect.moveCenter(outerRect.center());

        const QMargins padding = QMargins(boxRect.left() - outerRect.left() - Metrics::Shadow_Overlap - params.offset.x(),
                                          boxRect.top() - outerRect.top() - Metrics::Shadow_Overlap - params.offset.y(),
                                          outerRect.right() - boxRect.right() - Metrics::Shadow_Overlap + params.offset.x(),
                                          outerRect.bottom() - boxRect.bottom() - Metrics::Shadow_Overlap + params.offset.y());
        const QRect innerRect = outerRect - padding;

        // Mask out inner rect.
        painter.setPen(Qt::NoPen);
        painter.setBrush(Qt::black);
        painter.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        if (m_internalSettings->floatingTitlebar()){
        painter.drawRoundedRect(innerRect.adjusted(0, isMaximized() ? 0 : (buttonSize() + (Metrics::TitleBar_TopMargin * 2) + 13), 0, 0), m_scaledCornerRadius + 0.5, m_scaledCornerRadius + 0.5);
        } else {
        painter.drawPath(glassCornerPath(QRectF(innerRect), m_scaledCornerRadius + 0.5, sq));
        }

        // Glass: THE edge line. Drawn after the window area has been cut out, as a full hairline just outside the edge, so
        // straight runs and corner arcs get exactly the same stroke. KWin's own border outline is switched off (see
        // recalculateBorders): it thinned out on the arcs, and two lines next to each other never agree at the corners.
        if (!bare) {
            painter.setCompositionMode(QPainter::CompositionMode_SourceOver);
            painter.setRenderHint(QPainter::Antialiasing);
            const int a = glassOutlineColor().alpha();
            QLinearGradient lit(0, innerRect.top(), 0, innerRect.top() + m_scaledCornerRadius + 40);
            lit.setColorAt(0.0, QColor(255, 255, 255, qMin(255, int(a * 1.25))));
            lit.setColorAt(1.0, QColor(255, 255, 255, int(a * 0.62)));          // carries on down the sides and along the bottom
            // width: the line grows OUTWARD from the window edge (its inner side stays on the edge), so a thicker focused
            // outline never eats into the window
            const qreal lw = qBound(0.5, (glassActive ? m_internalSettings->glassOutlineWidthActive() : m_internalSettings->glassOutlineWidthInactive()) / 10.0, 4.0);
            painter.setPen(QPen(QBrush(lit), lw));
            if (qEnvironmentVariableIsSet("GLASS_DEBUG_OUTLINE")) painter.setPen(QPen(QColor(255, 0, 0, 255), lw));
            painter.setBrush(Qt::NoBrush);
            const QRectF o = QRectF(innerRect).adjusted(-lw / 2, -lw / 2, lw / 2, lw / 2);
            const qreal r = m_scaledCornerRadius + lw / 2;
            painter.drawPath(glassCornerPath(o, r, sq));
            // A 1 px anti-aliased ARC spreads its light over two pixels, so at this low alpha it reads far dimmer than the
            // straight runs next to it ("the corners are missing"). Stroke the four arcs a second time to even them out.
            QPainterPath arcs;
            if (!(sq & GlassTopLeft)) { arcs.moveTo(o.left(), o.top() + r);        arcs.arcTo(QRectF(o.left(), o.top(), 2 * r, 2 * r), 180, -90); }
            if (!(sq & GlassTopRight)) { arcs.moveTo(o.right() - r, o.top());       arcs.arcTo(QRectF(o.right() - 2 * r, o.top(), 2 * r, 2 * r), 90, -90); }
            if (!(sq & GlassBottomRight)) { arcs.moveTo(o.right(), o.bottom() - r);    arcs.arcTo(QRectF(o.right() - 2 * r, o.bottom() - 2 * r, 2 * r, 2 * r), 0, -90); }
            if (!(sq & GlassBottomLeft)) { arcs.moveTo(o.left() + r, o.bottom());     arcs.arcTo(QRectF(o.left(), o.bottom() - 2 * r, 2 * r, 2 * r), 270, -90); }
            // How much: a setting per state (GlassOutlineArcActive / Inactive, percent). The old formula 0.85 / lw^4.4 was
            // tuned by summing brightness ACROSS the line; for the 1 px inactive line that turns the arc into a two-pixel
            // 90 % stroke next to a one-pixel run, i.e. brighter and thicker corners on every unfocused window (2026-09-23).
            painter.setOpacity(qBound(0.0, (glassActive ? m_internalSettings->glassOutlineArcActive() : m_internalSettings->glassOutlineArcInactive()) / 100.0, 1.0));
            painter.drawPath(arcs);
            painter.setOpacity(1.0);
        }

        painter.end();

        slot = std::make_shared<KDecoration3::DecorationShadow>();
        slot->setPadding(padding);
        slot->setInnerShadowRect(QRect(outerRect.center(), QSize(1, 1)));
        slot->setShadow(shadowTexture);
    }

    setShadow(slot);
}

QMarginsF Decoration::bordersFor(qreal scale) const
{
    const qreal left = isLeftEdge() ? 0 : borderSize(false, scale);
    const qreal right = isRightEdge() ? 0 : borderSize(false, scale);
    const qreal bottom = (window()->isShaded() || isBottomEdge()) ? 0 : borderSize(true, scale);

    qreal top = 0;
    if (hideTitleBar()) {
        top = bottom;
    } else {
        QFontMetrics fm(settings()->font());
        top += KDecoration3::snapToPixelGrid(std::max(fm.height(), buttonSize()), scale);

        // padding below
        const int baseSize = settings()->smallSpacing();
        if (m_internalSettings->floatingTitlebar()){
        if (isMaximized())
        top += KDecoration3::snapToPixelGrid((baseSize + 2) * Metrics::TitleBar_BottomMargin, scale);
        else
        top += KDecoration3::snapToPixelGrid((baseSize + 4.5) * Metrics::TitleBar_BottomMargin, scale);
        } else {
        top += KDecoration3::snapToPixelGrid(baseSize * Metrics::TitleBar_BottomMargin, scale);
        }
        // padding above
        top += KDecoration3::snapToPixelGrid(baseSize * Metrics::TitleBar_TopMargin, scale);
    }
    if (!hideTitleBar()) top = std::max<qreal>(top, KDecoration3::snapToPixelGrid(m_internalSettings->glassTitleBarHeight(), scale));   // Glass: fixed, roomier title bar
    return QMarginsF(left, top, right, bottom);
}

void Decoration::setScaledCornerRadius()
{
    // On X11, the smallSpacing value is used for scaling.
    // On Wayland, this value has constant factor of 2.
    // Removing it will break radius scaling on X11.
    m_scaledCornerRadius = KDecoration3::snapToPixelGrid(((m_internalSettings->otherCornerRadius() < 0) ? m_internalSettings->cornerRadius() : m_internalSettings->otherCornerRadius()) * settings()->smallSpacing(), window()->nextScale());
}

void Decoration::updateScale()
{
    setScaledCornerRadius();
    recalculateBorders();
}

} // namespace

#include "darklydecoration.moc"
