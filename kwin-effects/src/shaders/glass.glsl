// Constants (rim, tint, highlights) are sRGB values, but the framebuffer is in the OUTPUT's encoding: on an HDR output, or
// with the brightness turned down, KWin bakes reference luminance and brightness into it. A raw constant therefore never
// dimmed with the screen (the rim stayed bright when brightness went down). The C++ side converts them once per draw
// with ColorDescription::mapTo(sRGB -> render target), the same maths as KWin's surface conversion; these three arrive
// already in the target's encoding.
uniform vec3 tintColor;
uniform float tintGray;
uniform float tintStrength;
uniform vec2 autoTintAlphaRange;
uniform int autoTintAlpha;
uniform vec3 glowColor;
uniform vec3 rimColor;      // sRGB white, target-encoded
uniform float glowStrength;
uniform int edgeLighting;

uniform float edgeSizePixels;
uniform float refractionStrength;
uniform float refractionNormalPow;
uniform float refractionRGBFringing;
uniform float refractionOffsetStrength;
uniform float refractionBevelIntensity;
uniform int physicallyBasedRefraction;
// Lobe shapes (Sirca Shell): up to 8 rounded boxes in "position" space (centre-origin, y up, device px),
// smooth-unioned so a lobe growing out of a bar gets a concave fillet. lobeCount == 0 → single rounded box.
uniform int lobeCount;
uniform vec4 lobes[8];
uniform float lobeRadius;
uniform float lobeFillet;

float roundedRectangleDist(vec2 p, vec2 b, vec4 cornerRadius)
{
    float r = p.x > 0.0
        ? (p.y > 0.0 ? cornerRadius.y : cornerRadius.w)
        : (p.y > 0.0 ? cornerRadius.x : cornerRadius.z);
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float lobeBoxDist(vec2 p, vec2 hs, float r)
{
    vec2 q = abs(p) - hs + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float lobeSmin(float a, float b, float k)
{
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

float shapeDist(vec2 p, vec2 halfBlurSize, vec4 cornerRadius)
{
    if (lobeCount <= 0) {
        return roundedRectangleDist(p, halfBlurSize, cornerRadius);
    }
    float d = 1e9;
    for (int i = 0; i < 8; ++i) {
        if (i >= lobeCount) break;
        float r = min(lobeRadius, min(lobes[i].z, lobes[i].w));
        float di = lobeBoxDist(p - lobes[i].xy, lobes[i].zw, r);
        d = (i == 0) ? di : lobeSmin(d, di, max(lobeFillet, 0.001));
    }
    return d;
}

struct GlassFragment {
    vec4 color;
    float dist;
    float edgeFactor;
    float concaveFactor;
    vec3 normal;
    float ior;
};

#include "snells-glass.glsl"

vec4 roundedRectangle(float dist, vec3 color)
{
    if (dist <= 0.0) {
        return vec4(color, 1.0);
    }

    float s = smoothstep(0.0, 1.0, dist);
    return vec4(color, mix(1.0, 0.0, s));
}

GlassFragment glassRefraction(vec2 position, vec2 halfBlurSize, vec4 cornerRadius, float dist, float edgeFactor, float concaveFactor)
{
    const float h = 1.0;
    vec2 gradient = vec2(
            shapeDist(position + vec2(h, 0), halfBlurSize, cornerRadius) - shapeDist(position - vec2(h, 0), halfBlurSize, cornerRadius),
            shapeDist(position + vec2(0, h), halfBlurSize, cornerRadius) - shapeDist(position - vec2(0, h), halfBlurSize, cornerRadius)
    );

    vec2 normal = length(gradient) > 0.0 ? -normalize(gradient) : vec2(0.0, 1.0);

    float finalStrength = min(0.4 * concaveFactor * refractionStrength, 1.0);

    vec2 refractOffsetG = -normal.xy * finalStrength;
    vec2 refractOffsetR = -normal.xy * finalStrength;
    vec2 refractOffsetB = -normal.xy * finalStrength;

    // Different refraction offsets for each color channel
    float fringingFactor = refractionRGBFringing * 0.3;
    if (fringingFactor > 0.0) {
        // Red bends most
        refractOffsetR = -normal.xy * (finalStrength * (1.0 + fringingFactor));
        // Blue bends least
        refractOffsetB = -normal.xy * (finalStrength * (1.0 - fringingFactor));
    }

    vec2 coordR = clamp(uv - refractOffsetR, 0.0, 1.0);
    vec2 coordG = clamp(uv - refractOffsetG, 0.0, 1.0);
    vec2 coordB = clamp(uv - refractOffsetB, 0.0, 1.0);

    vec4 color = vec4(
        texture(texUnit, coordR).r,
        texture(texUnit, coordG).g,
        texture(texUnit, coordB).b,
        texture(texUnit, coordG).a
    );
    return GlassFragment(color, dist, edgeFactor, concaveFactor, vec3(0.0, 0.0, 1.0), 1.0);
}

vec3 glassGlow(vec2 position, GlassFragment s)
{
    float rimMask = clamp(0.25 * s.concaveFactor, 0.0, glowStrength);
    vec3 glow = mix(s.color.rgb, glowColor, rimMask);
    if (edgeLighting == 1) {
        glow += (s.color.rgb * s.concaveFactor);
    }

    return glow;
}

vec3 glassOutline(vec2 position, GlassFragment s)
{
    vec3 glow = s.color.rgb;

    if (glowStrength > 0.0) {
        float edgeMask = smoothstep(0.0, -1.0, s.dist);          // rim: about 1 px at half height, with soft 1 px ramps (0.5 px ramps stair-stepped on the curves)
        float borderInner = smoothstep(-0.6, -1.8, s.dist);
        float edgeProfile = edgeMask - borderInner;
        float thicknessShadow = pow(edgeProfile, 0.9);
        // Uniform outline all the way around the shape. The original directional masks
        // (bright towards the bottom-left and top-right, dark towards the other two corners)
        // left two of a pill's rounded corners without any highlight.
        glow = mix(glow, rimColor, thicknessShadow * 0.44);   // rim strength (0.7 -> 0.56 -> 0.44, onur 2026-09-20: thinner and less bright). Bar, dock and every popup lobe share it
    }

    return glow;
}

float adjustedTintStrength(float baseTintStrength, vec3 backgroundColor)
{
    float strength = clamp(baseTintStrength, 0.0, 1.0);

    const vec3 grayscaleWeights = vec3(0.299, 0.587, 0.114);
    float backgroundGray = dot(backgroundColor, grayscaleWeights);

    float finalScale = clamp(abs(backgroundGray - tintGray), 0.0, 1.0);
    float rangedScale = mix(autoTintAlphaRange.x, autoTintAlphaRange.y, finalScale);

    float localStrength = strength * rangedScale;
    float useLocal = step(0.5, float(autoTintAlpha)) * step(0.001, strength);

    return mix(strength, localStrength, useLocal);
}

// position and dist are the caller's: the SDF is evaluated once per fragment and passed through.
vec4 glass(vec4 sum, vec4 cornerRadius, vec2 position, float dist)
{
    vec2 halfBlurSize = blurSize * 0.5;
    float minHalfSize = min(halfBlurSize.x, halfBlurSize.y);

    if (dist >= 0.0) {
        return sum;
    }

    float minEsp = clamp(edgeSizePixels, 0.1, minHalfSize * 0.9);
    float edgeFactor = 1.0 - clamp(abs(dist) / minEsp, 0.0, 1.0);
    float concaveFactor = 1.0 - sqrt(1.0 - pow(smoothstep(0.0, 1.0, edgeFactor), refractionNormalPow));

    GlassFragment s;
    // Refraction only bends light in the edge band: outside it (edgeFactor == 0) both refraction models collapse to a
    // single tap at uv. Use the 8-tap upsample the caller already paid for there, and refetch only inside the band.
    if (refractionStrength > 0.0 && edgeFactor > 0.0) {
        vec4 r = clamp(cornerRadius * 2.0, min(64.0, minHalfSize), min(128.0, minHalfSize));
        s = physicallyBasedRefraction == 0
            ? glassRefraction(position, halfBlurSize, r, dist, edgeFactor, concaveFactor)
            : snellsRefraction(position, halfBlurSize, r, minHalfSize, dist, edgeFactor, concaveFactor);
    } else {
        s = GlassFragment(sum, dist, edgeFactor, concaveFactor, vec3(0.0, 0.0, 1.0), 1.0);
    }

    vec3 rgb = s.concaveFactor < 1.0 ? glassGlow(position, s) : s.color.rgb;
    s.color.rgb = mix(rgb, tintColor, adjustedTintStrength(tintStrength, rgb));
    vec3 final = glassOutline(position, s);
    return roundedRectangle(dist, final);
}
