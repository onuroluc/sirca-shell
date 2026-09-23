# General
### Window opacity affects blur
Since Plasma 6, window opacity now affects blur opacity with no option to disable it in the stock blur effect.

Enabled (default):
![image](https://github.com/taj-ny/kwin-effects-glass/assets/79316397/525a3611-62f0-4c7e-b01c-253a05cbd3ca)

Disabled:
![image](https://github.com/taj-ny/kwin-effects-glass/assets/79316397/b4f35a24-e288-4c51-9707-494942abdaa0)

### Content blur
These sliders control the blur and noise applied to the window content area.

### Decorations blur
These sliders control the blur and noise applied to window decorations when decoration effects are enabled.

### Docks blur
These sliders control the blur and noise applied to docks and panels.

If the content and decoration blur/noise values match, the effect uses a single blur pass to avoid visible seams between the content and decoration regions.

### Quality tier
Trades looks for GPU time. *Full* is the effect as configured. *Reduced* caps the blur pyramid at two levels and turns noise
and refraction off. *Minimal* blurs with a single level. Stored as `QualityTier` (0, 1, 2) in the `[Effect-blurplus]`
group of `kwinrc`.

### Use at least the reduced tier on battery
While UPower reports the machine as running on battery, the effect runs at the reduced tier (or the configured one if that
is lower already). Stored as `ReduceOnBattery`. Without UPower on the system bus nothing changes.

# Force blur
### Apply effects to window decorations as well
Whether to apply the glass effect to window decorations, including borders. Enable this if your window decoration doesn't support blur, or you want rounded top corners.

This option will override the blur region specified by the decoration.

# Rounded corners
### Use declared corner radius
When enabled, Glass uses the corner radius reported by the window instead of overriding it with the settings below.

### Dynamic corner radius
When enabled, corners that touch the edge of another window are flattened.

The exclude options keep the configured corner radius for docks, tooltips, or menus instead of dynamically flattening those window types.

