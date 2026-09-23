#pragma once

#include <QStringList>

namespace KWin
{

QStringList parseWindowClasses(const QString &input);

enum class WindowClassMatchingMode
{
    Blacklist,
    Whitelist
};


struct GeneralSettings
{
    int blurStrength;
    int noiseStrength;
    int decorationBlurStrength;
    int decorationNoiseStrength;
    int dockBlurStrength;
    int dockNoiseStrength;
    float brightness;
    float saturation;
    float contrast;
    bool oklabSaturation;
    float blurRadius;
    float upsampleOffset;
    bool saturationCompensation;
    QString tintColor;
    bool autoTintAlpha;
    float autoTintAlphaMin;
    float autoTintAlphaMax;
    QString glowColor;
    bool edgeLighting;
    bool edgeLightingDock;
    bool edgeLightingTooltip;
    bool excludeDocks;
    bool excludeDecorations;
    bool excludeTooltips;
    bool excludeMenus;
    bool excludeOSD;
    int qualityTier;        // 0 full, 1 reduced, 2 minimal (see BlurEffect::applySettings)
    bool reduceOnBattery;
};

struct ForceBlurSettings
{
    QStringList windowClasses;
    QStringList forceClasses;          // windows of these classes get blur behind the WHOLE window although they never asked (apps made translucent by a window rule)
    WindowClassMatchingMode windowClassMatchingMode;
    bool blurDecorations;
    bool blurMenus;
    bool blurDocks;
};

struct RoundedCornersSettings
{
    float windowTopRadius;
    float windowBottomRadius;
    float menuRadius;
    float dockRadius;
    bool useDeclaredCornerRadius;
    bool ignoreContentBlurRegion;
    bool roundMaximized;
    bool dynamicCorners;
    bool dynamicCornersExcludeWindows;
    bool dynamicCornersExcludeDocks;
    bool dynamicCornersExcludeTooltips;
    bool dynamicCornersExcludeMenus;
};

struct RefractionSettings
{
    float edgeSizePixels;
    float refractionStrength;
    float refractionNormalPow;
    float refractionRGBFringing;
    float refractionOffsetStrength;
    float refractionBevelIntensity;
    bool physicallyBased;
    bool excludeWindows;
    bool excludeDocks;
    bool excludeMenus;
    bool excludeTooltips;
    bool excludeOSD;
};

class BlurSettings
{
public:
    GeneralSettings general{};
    ForceBlurSettings forceBlur{};
    RoundedCornersSettings roundedCorners{};
    RefractionSettings refraction{};

    void read();
};

}
