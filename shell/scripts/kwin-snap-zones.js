// Sirca Shell snap zones, the KWin half. A KWin script is the only thing that knows when a window is being MOVED with
// the pointer and where the cursor is (the pointer is grabbed by the move, no surface gets it): it tells the shell
// (src/kwinsnap.cpp, D-Bus object /SnapZones on the shell's service) when a move starts, where the cursor is while it
// lasts, and where the window is dropped. The shell draws the zones and tiles the window; KWin scripts cannot draw.
// Loaded and unloaded by the shell with the config key snapZones (default on); the file lives in the shell's resources.
const service = "onur.SircaShell", path = "/SnapZones", iface = "onur.SircaShell.SnapZones";
let dragging = null, lastSent = 0;

function cursor() { const p = workspace.cursorPos; return [Math.round(p.x), Math.round(p.y)]; }

function hook(w) {
    if (!w || !w.normalWindow) return;                     // panels, the desktop, our own layer surfaces: no zones
    w.interactiveMoveResizeStarted.connect(function () {
        if (!w.move || w.resize) return;                    // a resize has no zones
        dragging = w; lastSent = 0;
        callDBus(service, path, iface, "dragStarted");
    });
    w.interactiveMoveResizeStepped.connect(function () {
        if (dragging !== w) return;
        const t = Date.now();
        if (t - lastSent < 33) return;                      // ~30 positions a second is plenty for a hover highlight
        lastSent = t;
        const c = cursor();
        callDBus(service, path, iface, "dragMoved", c[0], c[1]);
    });
    w.interactiveMoveResizeFinished.connect(function () {
        if (dragging !== w) return;
        dragging = null;
        const c = cursor();
        callDBus(service, path, iface, "dragFinished", c[0], c[1]);
    });
}

workspace.windowList().forEach(hook);
workspace.windowAdded.connect(hook);
