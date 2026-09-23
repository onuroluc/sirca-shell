#version 140
#include "colormanagement.glsl"
// Glass Key. Works on the window's own (sRGB-encoded) pixels, before colour management.
// ONE key colour (uniform keyContent). keyChrome is the ACCENT since v4 (see the accent rim below). The app's theme paints
//   the window (chrome)  = the bare key                      -> alphaChrome, tintChrome
//   panels (content)     = the key + PANEL of the text colour -> alphaContent, tintContent
//   controls, text       = more of the text colour on top     -> towards solid
// Everything on the straight line key -> text is therefore "surface with some ink on it", and alpha and tint are CONTINUOUS
// functions of the position t on that line. (v1 had a second exact key for the chrome. It sat on the content's line, so a
// gradient on a panel passed through it: horizontal lines across large panels.) Pixels off the line (pictures, coloured
// controls) stay opaque.
uniform sampler2D sampler;
uniform vec4 modulation;
uniform vec3 keyContent, keyChrome, keyText, tintContent, tintChrome;
uniform float alphaContent, alphaChrome;
// own shadow for windows without a decoration (see GlassKeyEffect::drawWindow): where the contents sit in this texture
uniform float shadowStrength, contentRadius;
uniform vec2 texSizePx;
uniform vec4 contentPx;
in vec2 texcoord0;
out vec4 fragColor;

// Where a PANEL sits on the key -> text line. The steps are wide on purpose: an app may hand its pixels over in another
// encoding than it painted them in. Measured with HDR on: Chromium delivers sRGB colours re-encoded as gamma 2.2, so the
// key (20,23,29) arrives as (26,30,35), about 0.03 up the line. With a panel at 0.04 the bare window read as "mostly
// panel": denser and darker than every other window's chrome. Chrome is now everything up to 0.04, a panel sits at 0.08.
const float PANEL = 0.08;

void main()
{
    vec4 tex = texture(sampler, texcoord0);
    vec3 p = tex.a > 0.0 ? tex.rgb / tex.a : tex.rgb;
    vec3 d = keyText - keyContent;
    // HOLE: pure magenta is "nothing here" (an undecorated widget rounds its own corners: magenta page, rounded root on top).
    // The anti-aliased corner pixels are magenta MIXED with the surface. Only scaling their alpha left the magenta in them:
    // a red fringe on every corner. So: estimate the magenta share h, take it out of the colour, and accept that only when
    // what remains is surface (on the key line): a pink pixel of a picture has no surface under it and is left alone.
    const vec3 M = vec3(1.0, 0.0, 1.0);
    float h = clamp((p.r + p.b) * 0.5 - p.g, 0.0, 1.0);
    vec3 pc = (p - h * M) / max(1.0 - h, 0.02);
    float tc = clamp(dot(pc - keyContent, d) / dot(d, d), -0.10, 1.0);
    float tolc = 2.6 / 255.0 + 0.07 * abs(tc) + 0.16 * h;             // the un-mix gets noisier the less surface is left
    float surfaceUnder = 1.0 - smoothstep(tolc, tolc * 2.5 + 0.004, length(pc - (keyContent + tc * d)));
    float holeMix = smoothstep(0.02, 0.06, h) * surfaceUnder;
    float holePure = 1.0 - smoothstep(0.02, 0.12, length(p - M));
    // Next to a pure-magenta texel this IS the hole's anti-aliased edge, whatever the un-mix says. The un-mix is noisy there
    // (the app hands its pixels over re-encoded, and a mix does not survive that linearly; the error grows with 1 / (1 - h)):
    // edge pixels that failed the surface test stayed opaque (purple specks on the corner arcs), and ones that landed below
    // the key were read as "darker than the surface" and made denser: a near-black line round each corner.
    vec2 texel = 1.0 / vec2(textureSize(sampler, 0));
    float nearHole = 0.0, tNear = 0.0, tLow = 1.0, tLow2 = 1.0;
    // The 16 taps only matter for a pixel that is near the hole or carries ink; for the bare surface (most of every
    // window) the defaults give the same result exactly: nearHole reaches the output only through
    // edge = ... * smoothstep(0.01, 0.04, h), which is 0 for h <= 0.01; tLow / tLow2 only through
    // panel = smoothstep(0.042, 0.072, min(t, ...)), 0 for t <= 0.042 whatever the neighbours; tNear only through
    // inkLevel, which is moot while c == 0 (t <= base, and base >= 0.035). With h <= 0.01 holeMix is exactly 0 below,
    // so t is the value computed here.
    float t0 = dot(p - keyContent, d) / dot(d, d);
    if (h > 0.01 || t0 > 0.035) {
        for (int i = 0; i < 8; ++i) {
            float ang = float(i) * 0.7853982;
            vec4 nb = texture(sampler, texcoord0 + vec2(cos(ang), sin(ang)) * texel * 1.5);
            vec3 nbp = nb.a > 0.0 ? nb.rgb / nb.a : nb.rgb;
            nearHole = max(nearHole, 1.0 - smoothstep(0.02, 0.12, length(nbp - M) + (1.0 - nb.a)));
            // the strongest ink nearby (see inkLevel below); two rings, so the inside of a 2-3 px stroke is reached
            float nt = dot(nbp - keyContent, d) / dot(d, d);
            tLow = min(tLow, length(nbp - (keyContent + nt * d)) < 0.10 ? nt : 1.0);
            vec3 nb2 = texture(sampler, texcoord0 + vec2(cos(ang), sin(ang)) * texel * 3.0).rgb;
            float nt2 = dot(nb2 - keyContent, d) / dot(d, d);
            tLow2 = min(tLow2, length(nb2 - (keyContent + nt2 * d)) < 0.10 ? nt2 : 1.0);
            tNear = max(tNear, max(nt * step(length(nbp - (keyContent + nt * d)), 0.10), dot(nb2 - keyContent, d) / dot(d, d) * step(length(nb2 - (keyContent + dot(nb2 - keyContent, d) / dot(d, d) * d)), 0.10)));
        }
    }
    // Where the arc runs into the straight edge the magenta sliver is thinner than a texel: no neighbour is PURE magenta, and
    // two purple specks per corner were left. Inside the window's corner squares (nothing but the surface and the hole can
    // be there) any magenta share counts.
    vec2 fromCorner = abs(abs(vec2(texcoord0.x, 1.0 - texcoord0.y) * texSizePx - (contentPx.xy + contentPx.zw * 0.5)) - contentPx.zw * 0.5);
    // ... but only ON the arc (a 4 px band), not in the whole square: the close button sits in the top right square, and its
    // red hover fill carries a "magenta share" of 0.28: it was keyed out, all but a sliver.
    float zr = max(contentRadius, 22.0) + 2.0;
    float cornerZone = texSizePx.x > 0.0 ? step(max(fromCorner.x, fromCorner.y), zr) * step(zr - 4.0, length(max(vec2(zr) - fromCorner, vec2(0.0)))) : 0.0;
    float edge = max(nearHole, cornerZone) * smoothstep(0.01, 0.04, h);
    holeMix = max(holeMix, edge);
    p = mix(p, pc, holeMix);
    float t = clamp(dot(p - keyContent, d) / dot(d, d), -0.10, 1.0);
    // on the hole's edge: plain surface (no "beyond", no off-line colour), its alpha scaled by the share that is not hole
    p = mix(p, keyContent + clamp(t, 0.0, 0.25) * d, edge);
    t = mix(t, clamp(t, 0.0, 0.25), edge);
    float residual = length(p - (keyContent + t * d));
    // a cone: soft shadows (key * (1 - a)) drift off the line as they darken; a tube made contour rings of their 8-bit steps
    float tol = 2.6 / 255.0 + 0.07 * abs(t);
    float onLine = 1.0 - smoothstep(tol, tol * 2.5 + 0.004, residual);

    // A PANEL is a flat area: its neighbours are at panel level too. The faint outermost pixels of a glyph on the bare window
    // (5 - 9 % ink) sit at the same place on the line, and were given the panel's denser glass: a pale ring round every
    // icon in light mode (measured: alpha 0.64 on those pixels, 0.46 on the surface around them), a dark one in dark mode.
    // (the wider ring only where there is ink close by: it reaches the bare surface from inside a glyph's small enclosed
    // gaps, and without ink around it would give every panel a 3 px border of thinner glass)
    float panel = smoothstep(0.042, 0.072, min(t, tNear > 0.2 ? min(tLow, tLow2) : tLow));                        // 0 chrome .. 1 panel (flat on both sides: see PANEL)
    float beyond = clamp(-t * 2.0, 0.0, 0.3);                         // the other side of the key (a shadow in dark, a highlight in light)
    float aSurf = mix(alphaChrome, alphaContent, panel);
    vec3 tint = mix(tintChrome, tintContent, panel);
    // INK on the surface (text, glyphs, a control's fill): how much of the pixel is the text colour. An EXACT un-mix:
    //   pixel = c * text + (1 - c) * surface     ->     alpha = c + (1 - c) * aSurf,   colour = (c * text + (1 - c) * aSurf * tint) / alpha
    // The earlier version gave an anti-aliased edge pixel the plain mix of tint and text at a ramped alpha: too much of the
    // (dark) tint in a pixel that is mostly see-through, a dark fringe round every letter as soon as something coloured or
    // bright lay behind the window ("the text looks janky").
    float base = mix(0.035, 0.105, panel);                            // where the bare surface sits on the line (incl. the encoding shift)
    float c = clamp((t - base) / (1.0 - base), 0.0, 1.0);
    // The ink is not always the text colour: dimmed labels (times, artist) are a GREY on the same line. Read as "64 % white"
    // they came out see-through and dirty over a colourful backdrop. So coverage saturates early (anything from 45 % of
    // the way to the text colour is solid ink), and the ink's own colour is recovered from the pixel instead of assumed.
    // Coverage = this pixel's ink / the ink's own LEVEL, and the level is read off the neighbourhood (the strongest on-line
    // pixel within 3 px: the inside of the glyph this edge belongs to). A fixed curve was wrong both ways: a smoothstep gave
    // faint edge pixels LESS coverage than ink, so the recovered ink colour overshot to pure white: a hair-thin white outline
    // round every grey icon, which read as "not anti-aliased".
    // Floor 0.55: the theme's dimmest real ink (subdued icons and labels) sits at about 0.6 of the way to the text colour.
    // Sampled neighbours are bilinear averages and under-read a thin stroke; with a low level an edge pixel became "a lot
    // of pale ink" instead of "a little dark ink": the same brightness over white, but a pale halo over a coloured backdrop.
    float inkLevel = clamp((max(tNear, t) - base) / (1.0 - base), 0.55, 1.0);
    float ai = clamp(c / inkLevel, 0.0, 1.0);
    vec3 surfaceAsDelivered = keyContent + base * d;
    vec3 inkCol = clamp(((keyContent + t * d) - (1.0 - ai) * surfaceAsDelivered) / max(ai, 0.02), 0.0, 1.0);
    float aG = mix(aSurf, 1.0, beyond);
    float a = ai + (1.0 - ai) * aG;
    vec3 col = (ai * inkCol + (1.0 - ai) * aG * tint) / max(a, 0.001);

    a = mix(1.0, a, onLine);
    float hole = max(holePure, h * holeMix);
    col = mix(p, col, onLine);
    // ACCENT rim (keyChrome = the accent, kwinrc ChromeKey): the anti-aliased edge of an accent-filled control is accent
    // mixed with the surface. Off the text line it stayed opaque: a dark ring round the play button over anything bright.
    vec3 da = keyChrome - keyContent;
    float la = dot(da, da);
    if (la > 0.02) {
        float u = clamp(dot(p - keyContent, da) / la, 0.0, 1.0);
        float tolA = 3.0 / 255.0 + 0.05 * u;
        float onA = (1.0 - smoothstep(tolA, tolA * 2.5 + 0.004, length(p - (keyContent + u * da)))) * (1.0 - onLine) * smoothstep(0.04, 0.10, u);
        float aA = u + (1.0 - u) * alphaChrome;
        a = mix(a, aA, onA);
        col = mix(col, (u * keyChrome + (1.0 - u) * alphaChrome * tintChrome) / max(aA, 0.001), onA);
    }
    // The PICTURE in a self-decorated widget (Spotify's mini player: the only window this effect draws a shadow for). A
    // picture is full of pixels on the key -> text line: every neutral grey, and above all near-white in light mode and
    // near-black in dark mode. Keyed, a cover with a white border got a ragged see-through frame and washed-out greys.
    // The shader cannot tell a picture from a surface by colour, so it is told where the picture is: the theme
    // (apps/spotify/user.css, html.glass-pip) lays the cover out as a centred square in a box with fixed insets.
    if (shadowStrength > 0.0) {
        const vec4 PIC_INSET = vec4(16.0, 34.0, 16.0, 149.0);        // left, top, right, bottom: measured through devtools at 300 x 417
        vec2 wp = vec2(texcoord0.x, 1.0 - texcoord0.y) * texSizePx - contentPx.xy;
        vec2 boxSize = contentPx.zw - PIC_INSET.xy - PIC_INSET.zw;
        float side = min(boxSize.x, boxSize.y);
        vec2 q = abs(wp - (PIC_INSET.xy + boxSize * 0.5)) - vec2(side * 0.5);
        float inPic = step(max(q.x, q.y), 0.0) * step(1.0, side);
        a = mix(a, 1.0, inPic); col = mix(col, p, inPic); hole *= 1.0 - inPic;
    }
    a *= 1.0 - hole;
    // KWin's colour functions work on STRAIGHT colour (its own shaders un-premultiply before them and premultiply after).
    // Feeding them premultiplied colour pushed colour x alpha through the transfer curve: the glass came out as roughly
    // tint x alpha SQUARED, a dark neutral veil (measured on the mini player: 12,13,18 where 16,17,25 was due), grey in
    // light mode. So: convert the opaque colour, then apply the alpha.
    // The app's OWN shadow: a self-decorated window (Chromium's picture-in-picture) paints a soft black shadow into its
    // margin, mostly BELOW itself: measured as a flat 8 % veil reaching 22 px down and then stopping dead, which is the
    // "absurdly big shadow that cuts off". Faint, black pixels are that shadow, not contents: they are dropped, and the
    // effect's own shadow (shaped to fade out inside the margin) takes their place.
    float ghost = (1.0 - smoothstep(0.30, 0.55, tex.a)) * (1.0 - smoothstep(0.03, 0.15, max(p.r, max(p.g, p.b))));
    float A = a * tex.a * (1.0 - ghost);
    // The window's DECORATION is in this texture too, and it is translucent already (the title bar: the glass colour at
    // 62 %). It sits on the key line, so it was keyed like a surface and got the glass alpha a second time: 0.62 x 0.62,
    // measured as a title bar at about 40 % next to a body at 62 % ("decoration and body are different colours").
    // The app's own buffer is opaque; translucent texels of a DECORATED window are decoration and pass through unchanged.
    float deco = shadowStrength > 0.0 ? 0.0 : (1.0 - smoothstep(0.90, 0.98, tex.a)) * step(0.004, tex.a);
    A = mix(A, tex.a, deco); col = mix(col, tex.a > 0.0 ? tex.rgb / tex.a : tex.rgb, deco);
    vec4 outc = nitsToDestinationEncoding(sourceEncodingToNitsInDestinationColorspace(vec4(col, 1.0)));
    outc = vec4(outc.rgb * A, A);
    if (shadowStrength > 0.0) {
        // The shadow can only live in the transparent margin the app leaves around its contents (Chromium: 16 px at the
        // sides, 10 on top, 32 below), so it must reach ZERO before that margin ends: the first version was still strong
        // at the buffer's edge and ended there in a hard box, which read as a huge shadow. Distances are taken per side and
        // scaled by that side's room, soft like the desktop's window shadows, a little deeper below (light from above).
        // the offscreen texture is upside down relative to the window (y = 0 is its BOTTOM edge): without the flip the 10 px
        // top margin was taken for the 32 px bottom one: a flat shadow for 22 px below the window that then stopped dead
        vec2 px = vec2(texcoord0.x, 1.0 - texcoord0.y) * texSizePx, half_ = contentPx.zw * 0.5;
        vec2 c = contentPx.xy + half_;
        vec2 room = vec2(px.x < c.x ? contentPx.x : texSizePx.x - contentPx.x - contentPx.z,
                         px.y < c.y ? contentPx.y : texSizePx.y - contentPx.y - contentPx.w);
        // how far out, as a fraction of THIS side's room: 0 at the window's edge, 1 where the margin ends. (The previous
        // formula mixed the corner radius and the smallest room into it and was still at 15 % of its strength where the
        // 32 px bottom margin ends: measured over a test pattern as a flat 7 % veil that stopped dead, a "huge" shadow.)
        // distance to the window's ROUNDED shape (a plain rectangle left a dark, square-cornered patch in the gap outside
        // each rounded corner: the shadow looked boxy and cut), as a fraction of the room on the side it points to
        float rr = max(contentRadius, 22.0);                               // Chromium clips a picture-in-picture window at about 22 px
        vec2 qd = abs(px - c) - half_ + vec2(rr);
        float dist = max(length(max(qd, 0.0)) + min(max(qd.x, qd.y), 0.0) - rr, 0.0);
        // The room differs per side (16 px at the sides, 32 below). Round a corner it is blended by DIRECTION, seen from the
        // centre of the corner's arc. (It was blended by how far the pixel lies outside the window's rectangle: that jumps
        // on the lines that continue the window's edges, so the wide shadow below stopped dead under the right edge: a
        // faint vertical line that drew a square "ghost corner" outside the rounded one.)
        vec2 v = max(abs(px - c) - (half_ - vec2(rr)), vec2(0.0)); v *= v;
        float roomHere = max((v.x * room.x + v.y * room.y) / max(v.x + v.y, 0.001) - 1.5, 1.0);
        if (v.x + v.y < 0.001) roomHere = max(min(room.x, room.y) - 1.5, 1.0);
        float far = clamp(dist / roomHere, 0.0, 1.0);
        // lighter above, deeper below (light from above): over the window's whole height. (It was a step at the middle: the
        // side shadows changed strength on one line.)
        float below = mix(0.6, 1.0, smoothstep(c.y - half_.y, c.y + half_.y, px.y));
        float s = shadowStrength * below * pow(1.0 - far, 2.6);
        // only where the window itself has NOTHING (its transparent margin). The glass is translucent: a shadow under it is
        // black inside the glass, which made this window's body darker and denser than every other window's (final alpha
        // measured 0.73 for a 0.62 glass). Keyed on the texel's own alpha, not on geometry: that cannot be misplaced.
        // By how much GLASS is there, not by the texel's alpha: the keyed-out page (opaque magenta in the texture, nothing
        // on screen) fills the sliver between the widget's 24 px corner and Chromium's 22 px clip, and the anti-aliased rim
        // pixels are only part glass. With the shadow off in both, the raw backdrop showed there: an "invisible corner"
        // and a rim in the colours of whatever lay behind.
        s *= 1.0 - clamp(A / max(alphaChrome, 0.01), 0.0, 1.0);
        outc += vec4(0.0, 0.0, 0.0, s) * (1.0 - outc.a);
    }
    fragColor = outc * modulation;
}
