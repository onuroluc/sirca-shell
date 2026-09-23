// Theme icon in the shell's "this is open" language, shared by launcher, show-desktop, bell, gear and the OSD glyph.
// Dark mode: a white glyph that GLOWS white while `active`.
// Light mode: a bright WHITE glyph too, lifted off the milky glass by a soft dark shadow underneath (no outline, no
// colour-themed glow: onur 2026-09-20). Hover and `active` do not change colour, they let the shadow reach a little further.
import SircaShell
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Item {
    id: root
    property string source: ""
    property bool active: false
    property bool hovered: false
    property real size: 18
    property color color: Config.fgSolid          // dark mode's glyph colour (light mode is white by design)
    // calm: the earlier, quieter light-mode shadow (no growing on hover / open, smaller). The launcher's logo keeps it: a big
    // glyph with a reaching shadow looked heavy (onur 2026-09-20); the small bar icons use the reaching one.
    property bool calm: false
    width: size; height: size
    // Only the pair for the current mode exists (a Loader each): four MultiEffects per icon, two of them never visible,
    // was four framebuffers and shader passes per bar icon. The visuals are unchanged; `visible: Config.dark` became `active`.
    // ---- dark: white glow behind the glyph while active
    Loader { z: -1; anchors.fill: parent; active: Config.dark; sourceComponent: Item {
        MultiEffect { x: icon.x; y: icon.y; width: icon.width; height: icon.height; source: icon; autoPaddingEnabled: true; blurEnabled: true; blur: 1.0; blurMax: 32; brightness: 0.5; saturation: -0.2; scale: 1.5; transformOrigin: Item.Center
            opacity: root.active ? 0.75 : 0; Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
        MultiEffect { x: icon.x; y: icon.y; width: icon.width; height: icon.height; source: icon; autoPaddingEnabled: true; blurEnabled: true; blur: 0.8; blurMax: 10; brightness: 0.5; scale: 1.12; transformOrigin: Item.Center
            opacity: root.active ? 0.6 : 0; Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } } } }
    // ---- light: the glyph's own shape as a soft dark shadow, a touch lower. It REACHES FURTHER while the pointer is over
    // the icon and further still while it is open (the gear with quick settings up): the light-mode counterpart of dark
    // mode's glow. The reach is a scale of the blurred shape, which shows; a larger blur radius alone only got fainter.
    Loader { z: -1; anchors.fill: parent; active: !Config.dark; sourceComponent: Item {
        MultiEffect { id: reach; x: icon.x; y: icon.y + Math.max(1, root.size / (root.calm ? 16 : 14)); width: icon.width; height: icon.height; source: icon; autoPaddingEnabled: true
            blurEnabled: true; blur: 1.0; blurMax: root.calm ? (root.active ? 16 : (root.hovered ? 12 : 8)) : 12; colorization: 1; colorizationColor: Config.ink; brightness: -1.0; transformOrigin: Item.Center
            scale: root.calm ? 1.0 : (root.active ? 1.42 : (root.hovered ? 1.22 : 1.10)); Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            opacity: root.calm ? (root.active ? 0.92 : (root.hovered ? 0.84 : 0.74)) : (root.active ? 1.0 : (root.hovered ? 0.88 : 0.78)); Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
        MultiEffect { x: icon.x; y: icon.y + 0.5; width: icon.width; height: icon.height; source: icon; autoPaddingEnabled: true     // a tight second layer: keeps thin strokes readable
            blurEnabled: true; blur: 0.7; blurMax: 4; colorization: 1; colorizationColor: Config.ink; brightness: -1.0; opacity: 0.74 } } }
    Kirigami.Icon { id: icon; anchors.fill: parent; source: root.source; color: Config.dark ? root.color : "white"; isMask: true; roundToIconSize: false   // literal-ok: white glyphs on light glass, by design
        opacity: root.hovered || root.active ? 1 : (Config.dark ? 0.85 : 0.96); Behavior on opacity { NumberAnimation { duration: 120 } } }
}
