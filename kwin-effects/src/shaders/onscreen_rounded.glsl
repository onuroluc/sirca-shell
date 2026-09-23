#include "sdf.glsl"

uniform sampler2D texUnit;
uniform mat4 colorMatrix;
uniform float offset;
uniform vec2 halfpixel;
uniform vec4 box;
uniform vec4 cornerRadius;
uniform float opacity;
uniform vec2 blurSize;
// the grain that hides banding, added HERE so the shape mask below applies to it: as a separate additive pass over the
// blur region's rectangles it lit up every strip where the region is larger than the glass (the bounce room above a
// popup, the squares outside rounded corners) as a faint ghost panel (issue #9, 2026-09-23). noiseScale 0 = off.
uniform sampler2D noiseTex;
uniform vec2 noiseTextureSize;
uniform float noiseScale;

in vec2 uv;
in vec2 vertex;
#include "glass.glsl"
#include "oklab.glsl"

void main(void)
{
    vec2 halfBlurSize = blurSize * 0.5;
    float minHalfSize = min(halfBlurSize.x, halfBlurSize.y);

    vec2 position = uv * blurSize - halfBlurSize.xy;
    float dist = shapeDist(position, halfBlurSize, cornerRadius);

    vec4 sum = vec4(0);
    if (dist <= 0.0) {
        sum = texture(texUnit, uv + vec2(-halfpixel.x * 2.0, 0.0) * offset);
        sum += texture(texUnit, uv + vec2(-halfpixel.x, halfpixel.y) * offset) * 2.0;
        sum += texture(texUnit, uv + vec2(0.0, halfpixel.y * 2.0) * offset);
        sum += texture(texUnit, uv + vec2(halfpixel.x, halfpixel.y) * offset) * 2.0;
        sum += texture(texUnit, uv + vec2(halfpixel.x * 2.0, 0.0) * offset);
        sum += texture(texUnit, uv + vec2(halfpixel.x, -halfpixel.y) * offset) * 2.0;
        sum += texture(texUnit, uv + vec2(0.0, -halfpixel.y * 2.0) * offset);
        sum += texture(texUnit, uv + vec2(-halfpixel.x, -halfpixel.y) * offset) * 2.0;
        sum /= 12.0;
    }

    sum = glass(sum, cornerRadius, position, dist);
    if (noiseScale > 0.0) {
        sum.rgb += texture(noiseTex, gl_FragCoord.xy / noiseTextureSize).rrr * noiseScale;
    }

    float f = lobeCount > 0
        ? shapeDist(vec2(vertex.x - box.x, box.y - vertex.y), box.zw, cornerRadius)
        : sdfRoundedBox(vertex, box.xy, box.zw, cornerRadius);
    float df = fwidth(f);
    sum *= 1.0 - clamp(0.5 + f / df, 0.0, 1.0);

    if (useOklabSaturation == 1) {
        sum.rgb = oklabSaturate(sum.rgb, saturation);
    }

    fragColor = sum * colorMatrix * opacity;
}
