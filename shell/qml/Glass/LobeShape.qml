// The bar and every lobe hanging off it drawn as ONE path: outer corners convex (radius R), the junctions between the
// bar and a lobe filleted concave (radius F) so the lobe reads as the bar growing, not a box pinned under it.
// Exposes `polygon` (sampled outline) for the blur region / input mask.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import SircaShell

Item {
    id: root
    property rect bar: Qt.rect(0, 0, 100, 37)
    property var lobes: []            // [{x, w, h}] hanging below the bar (h may animate; h <= 0 → ignored)
    property bool flip: false         // true: lobes grow UP from the bar's top edge (the dock); built mirrored in y
    property real radius: Config.cornerRadius
    property real fillet: 14
    property color tint: Config.tint
    property color rim: Config.rim
    property real sheen: Config.sheen
    property real shadowReach: 26      // same reach/strength as the Plasma panels' theme shadow
    property real shadowStrength: 0.55
    property real shadowOffsetY: 6
    readonly property var built: build(bar, lobes, flip, fillet)          // one pass per change, shared by the path and the polygon
    readonly property string pathData: built.svg
    readonly property var polygon: built.poly
    // ---- how big the offscreen layers are. The shadow (two layered sources and a blur) used to fill this whole item: on
    // the dock that is the screen's width, on the full-screen overlays 5120x1440, three times over, for a panel a fraction
    // of that size. They now cover the outline's bounding box plus the shadow's reach, on whole pixels. `reach` (optional)
    // is the outline the shape can grow INTO: the surface's fully grown mask polygon (points) or a rect. With it an
    // opening lobe does not resize the layers every frame (a layer that changes size is re-allocated, which is the one
    // thing worse than a big one); without it the current outline is used (fine for a panel whose outline does not animate).
    property var reach: null
    readonly property int pad: Math.ceil(shadowReach * 1.5 + Math.abs(shadowOffsetY)) + 2
    function boundsOf(v, b) {           // extend bounds b = [x0, y0, x1, y1] by a points array or a rect
        if (!v) return b
        if (v.length !== undefined) { for (let i = 0; i + 1 < v.length; i += 2) { b[0] = Math.min(b[0], v[i]); b[1] = Math.min(b[1], v[i + 1]); b[2] = Math.max(b[2], v[i]); b[3] = Math.max(b[3], v[i + 1]) } }
        else if (v.width > 0) { b[0] = Math.min(b[0], v.x); b[1] = Math.min(b[1], v.y); b[2] = Math.max(b[2], v.x + v.width); b[3] = Math.max(b[3], v.y + v.height) }
        return b }
    readonly property rect layerRect: {
        let b = boundsOf(built.poly, [Infinity, Infinity, -Infinity, -Infinity]); b = boundsOf(reach, b)   // the union: a bouncing lobe may overshoot the reach for a frame
        if (!(b[0] < b[2])) return Qt.rect(0, 0, 1, 1)
        const x = Math.max(0, Math.floor(b[0] - pad)), y = Math.max(0, Math.floor(b[1] - pad))
        return Qt.rect(x, y, Math.max(1, Math.min(Math.ceil(width), Math.ceil(b[2] + pad)) - x), Math.max(1, Math.min(Math.ceil(height), Math.ceil(b[3] + pad)) - y)) }

    function arcPts(cx, cy, r, a0, a1, n, out) {   // sample an arc from angle a0 to a1 (radians, y down)
        for (let i = 1; i <= n; ++i) { const a = a0 + (a1 - a0) * i / n; out.push(cx + r * Math.cos(a), cy + r * Math.sin(a)); }
    }
    // Same outline for other inputs, e.g. the fully grown shape: surfaces use that for blur region + input mask so those
    // are sent once per open/close, not once per animation frame (the Glass effect clips to its own boxes anyway).
    function polygonFor(bar, lobes, flip, fillet) { return build(bar, lobes, flip, fillet).poly }
    function build(bar, lobes, flip, fillet) {
        const H = root.height, fl = flip;
        const x0 = bar.x, x1 = bar.x + bar.width, y0 = fl ? H - bar.y - bar.height : bar.y, y1 = y0 + bar.height;   // mirrored space when flipped
        const LR = radius, F = fillet;                 // LR: lobe corners
        const R = Math.max(0.5, Math.min(radius, bar.height / 2, bar.width / 2));   // bar corners never exceed half its height (a growing panel starts as a sliver)
        const ls = (lobes || []).filter(l => l.h > 0.5).map(l => ({ x0: Math.max(l.x, x0 + R + F), x1: Math.min(l.x + l.w, x1 - R - F), y1: y1 + l.h })).sort((a, b) => a.x0 - b.x0);
        let d = ""; const pts = [];
        const Y = y => fl ? H - y : y;
        const M = (x, y) => { d += `M${x},${Y(y)} `; pts.push(x, Y(y)); };
        const L = (x, y) => { d += `L${x},${Y(y)} `; pts.push(x, Y(y)); };
        const A = (r, sweep, x, y, cx, cy, a0, a1) => { d += `A${r},${r} 0 0 ${fl ? 1 - sweep : sweep} ${x},${Y(y)} `; if (fl) arcPts(cx, H - cy, r, -a0, -a1, 8, pts); else arcPts(cx, cy, r, a0, a1, 8, pts); };
        const PI = Math.PI;
        M(x0 + R, y0);
        L(x1 - R, y0);  A(R, 1, x1, y0 + R, x1 - R, y0 + R, -PI/2, 0);
        L(x1, y1 - R);  A(R, 1, x1 - R, y1, x1 - R, y1 - R, 0, PI/2);
        // bottom edge, right → left, dropping into each lobe (right-most first)
        for (let i = ls.length - 1; i >= 0; --i) {
            const l = ls[i];
            const lr = Math.min(LR, l.y1 - y1, (l.x1 - l.x0) / 2);   // lobe's bottom radius shrinks while it is still tiny
            L(l.x1 + F, y1);           A(F, 0, l.x1, y1 + F, l.x1 + F, y1 + F, -PI/2, -PI);   // concave into the lobe's right wall
            L(l.x1, l.y1 - lr);        A(lr, 1, l.x1 - lr, l.y1, l.x1 - lr, l.y1 - lr, 0, PI/2);
            L(l.x0 + lr, l.y1);        A(lr, 1, l.x0, l.y1 - lr, l.x0 + lr, l.y1 - lr, PI/2, PI);
            L(l.x0, y1 + F);           A(F, 0, l.x0 - F, y1, l.x0 - F, y1 + F, 0, -PI/2);      // concave back onto the bar
        }
        L(x0 + R, y1);  A(R, 1, x0, y1 - R, x0 + R, y1 - R, PI/2, PI);
        L(x0, y0 + R);  A(R, 1, x0 + R, y0, x0 + R, y0 + R, PI, 3*PI/2);
        d += "Z";
        return { svg: d, poly: pts };
    }

    // shadow: the same outline, black, blurred — follows every lobe (KWin shadows cannot)
    // (each layered item sits at layerRect; the Shape inside is shifted back by -layerRect.x/y so the path, which is in
    // this item's coordinates, lands where it belongs. Mask and picture are the same size, so they line up pixel for pixel.)
    Item {
        id: shadowSource
        x: root.layerRect.x; y: root.layerRect.y; width: root.layerRect.width; height: root.layerRect.height
        visible: false
        layer.enabled: true
        Shape { x: -root.layerRect.x; y: -root.layerRect.y; width: root.width; height: root.height; preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: -1; fillColor: "black"; PathSvg { path: root.pathData } } }
    }
    // The shadow is cut OUT under the shape itself. It used to lie under the whole glass as well: 55 % black beneath a 15 %
    // tint, so the bar was a dark slab that hid what is behind it ("the top bar is not transparent"), whatever the tint
    // setting said. A shadow belongs around the glass, not inside it.
    // How: the blur's own mask, inverted, with the UNSHIFTED outline; the blurred picture is the outline drawn lower by the
    // offset. (Both are the same size and padding is off, so mask and picture line up pixel for pixel. A
    // masked layer around the old effect did nothing.) Both are the size of layerRect, see above.
    Item {
        id: shadowSourceLow
        x: root.layerRect.x; y: root.layerRect.y; width: root.layerRect.width; height: root.layerRect.height
        visible: false
        layer.enabled: true
        Shape { x: -root.layerRect.x; y: -root.layerRect.y; width: root.width; height: root.height; preferredRendererType: Shape.CurveRenderer; transform: Translate { y: root.shadowOffsetY }
            ShapePath { strokeWidth: -1; fillColor: "black"; PathSvg { path: root.pathData } } }
    }
    MultiEffect {
        z: -1
        x: root.layerRect.x; y: root.layerRect.y; width: root.layerRect.width; height: root.layerRect.height
        source: shadowSourceLow
        autoPaddingEnabled: false
        blurEnabled: true; blur: 1.0; blurMax: root.shadowReach * 1.5
        maskEnabled: true; maskSource: shadowSource; maskInverted: true; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0
        opacity: root.shadowStrength
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath { strokeWidth: -1; fillColor: root.tint; PathSvg { path: root.pathData } }
        ShapePath {   // sheen along the bar's top edge only
            strokeWidth: -1
            fillGradient: LinearGradient { x1: 0; y1: root.bar.y; x2: 0; y2: root.bar.y + Math.min(root.bar.height * 0.55, 22)   // a short highlight. Stretched over a tall panel (the launcher) the same 6 % → 0 ramp has ~15 alpha steps across hundreds of px: visible bands
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, root.sheen) }
                GradientStop { position: 1; color: "transparent" } }
            PathSvg { path: root.pathData }
        }
        ShapePath { strokeWidth: 1; strokeColor: root.rim; fillColor: "transparent"; PathSvg { path: root.pathData } }
    }
}
