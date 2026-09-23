// Sirca Shell core: the `Shell` QML singleton. Layer-shell placement, blur region + input mask that follow the
// drawn shape, exclusive zone, a tiny D-Bus caller and the JSON config loader.
#pragma once
#include <QKeySequence>
#include <QDBusMessage>
#include <QHash>
#include <QObject>
#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QTimer>
#include <QQuickWindow>
#include <QVariantList>
#include <QVariantMap>
#include <qqml.h>

class Shell : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "onur.SircaShell")
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit Shell(QObject *parent = nullptr);
    static QList<QKeySequence> launcherKeys();
    static class QAction *launcherAction(QObject *parent);
    static void releaseLauncherKey();   // give Super / Alt+F1 back to plasmashell's launcher

    // Before the window is first shown. edge: "top" | "bottom". exclusiveZone: strut in px. scope "dock" makes KWin
    // type the surface as a dock, which is what the Glass effect keys its panel treatment on.
    Q_INVOKABLE void setupLayer(QQuickWindow *window, const QString &edge, int exclusiveZone, const QString &scope = QStringLiteral("dock"));
    Q_INVOKABLE void setExclusiveZone(QQuickWindow *window, int zone);
    // multi-screen: the primary output (QGuiApplication::primaryScreen); the config key "primaryScreen" (an output name)
    // overrides it. Screens come and go: primaryScreenChanged fires on both.
    Q_PROPERTY(QString primaryScreenName READ primaryScreenName NOTIFY primaryScreenChanged)
    QString primaryScreenName() const;
    // Click catcher: a transparent full-screen layer surface shown only while a popup is open. `holes` = flat [x,y,w,h,…] in
    // screen coordinates that stay click-through (our bars and the open popup); a click anywhere else lands on the catcher.
    Q_INVOKABLE void setupCatcher(QQuickWindow *window);
    // wallpaper: a full-screen surface on the BACKGROUND layer, no input, no keyboard
    Q_INVOKABLE void setupWallpaper(QQuickWindow *window, bool takesInput = false);   // takesInput: it is THE desktop (right click menu), not a picture under Plasma's
    Q_INVOKABLE QString defaultTerminal() const;                 // KDE's configured terminal (kdeglobals), else the first one found
    Q_INVOKABLE QString plasmaWallpaper() const;                 // the image Plasma shows now (first-run default for ours)
    Q_INVOKABLE QStringList wallpaperFiles(const QString &folder) const;   // pictures in a folder, one level of sub-folders
    // Window switcher: centred overlay surface that owns the keyboard while it is up
    Q_INVOKABLE void setupSwitcher(QQuickWindow *window);
    // Search: a full-screen overlay surface that owns the keyboard. Full-screen so a click anywhere outside the panel
    // reaches it (close + replayClick); only the panel is blurred (setBlurRegion), the rest is transparent.
    Q_INVOKABLE QString kwinShortcutKey(const QString &action) const;   // the key bound to one of the window manager's actions ("" if none)
    Q_INVOKABLE bool hasProgram(const QString &name) const;             // on the PATH?
    Q_INVOKABLE bool kwinHasAction(const QString &action) const;          // does the window manager know this shortcut action (e.g. one of Mudeer's)?
    // place the focused window: x and width as fractions of the usable screen area, full height (a one-off KWin script)
    Q_INVOKABLE void tileActiveWindow(double xFraction, double widthFraction);
    Q_INVOKABLE void saveConfigKeys(const QVariantMap &values);         // several keys in one write (one reload)
    Q_INVOKABLE void removeConfigKeys(const QStringList &keys);
    Q_INVOKABLE QVariantMap sysStats();                                  // {cpu: 0..1 since the last call, mem: 0..1}
    Q_INVOKABLE int sinceStart() const;                         // ms since the process started (start-up budget marks)
    static void markStart();
    static qint64 msSinceStart();
    // edit scene: glass behind `panels` (rounded rects), input everywhere except `holes` (the bar and the dock stay clickable)
    Q_INVOKABLE void setSceneRegions(QQuickWindow *window, const QVariantList &panels, const QVariantList &holes);
    Q_INVOKABLE void setupSearch(QQuickWindow *window);
    Q_INVOKABLE void setupCapture(QQuickWindow *window);         // screenshot overlay: over everything, no glass treatment
    // a notification of our own. showPath: a file; clicking the notification (or its "Show in folder" button) opens the
    // file manager with that file selected
    Q_INVOKABLE void notify(const QString &title, const QString &text, const QString &imagePath, const QString &showPath = QString());
    Q_INVOKABLE void setBlurRegion(QQuickWindow *window, const QVariantList &rects);   // blur only; the input region stays the whole surface
    Q_INVOKABLE bool altHeld() const;          // is Alt (still) down, as far as this client has been told
    Q_INVOKABLE void setCatcherHoles(QQuickWindow *window, const QVariantList &holes);
    // The catcher swallows the click that dismisses a popup. This sends the same click again through KWin's fake-input
    // protocol (needs org_kde_kwin_fake_input in sirca-shell.desktop), so the window under the pointer gets it after all.
    Q_INVOKABLE void replayClick(int button);
    // exclusive = take the keyboard now (launcher opened by the Meta key); false = back to on-demand (focus on click)
    Q_INVOKABLE void setKeyboardExclusive(QQuickWindow *window, bool exclusive);
    // "none": clicks never move keyboard focus to us (the dock: the clicked app must still be the active one)
    Q_INVOKABLE void setKeyboardMode(QQuickWindow *window, const QString &mode);
    // rects: list of {x, y, w, h, r} in window coordinates; their union becomes the blur region and the input mask.
    Q_INVOKABLE void setShape(QQuickWindow *window, const QVariantList &rects);
    // points: flat list [x0,y0,x1,y1,…] of one closed polygon (window coordinates) → blur region + input mask.
    // maskExtra: flat [x,y,w,h,…] rects added to the INPUT mask only (the screen-edge strip that reveals a dodging bar).
    // An empty polygon turns blur off; the mask is then just the extras.
    Q_INVOKABLE void setShapePolygon(QQuickWindow *window, const QVariantList &points, const QVariantList &maskExtra, bool blur = true);
    // fire-and-forget variant (no round trip) for per-frame messages
    // same, with a D-Bus signature so QML numbers land as the right type (i = int32, d = double, s = string, v = as-is)
    Q_INVOKABLE void dbusSendTyped(const QString &service, const QString &path, const QString &iface, const QString &method, const QString &signature, const QVariantList &args);
    Q_INVOKABLE void dbusSend(const QString &service, const QString &path, const QString &iface, const QString &method, const QVariantList &args = {});
    Q_INVOKABLE QVariant dbusCall(const QString &service, const QString &path, const QString &iface, const QString &method, const QVariantList &args = {});
    Q_INVOKABLE QVariantMap loadConfig() const;   // ~/.config/sirca-shell/config.json (may be absent)
    Q_INVOKABLE QString configPath() const;
    Q_INVOKABLE void setShowingDesktop(bool showing);   // via KWindowSystem (plasma window management); KWin's D-Bus showDesktop() is a no-op here
    Q_INVOKABLE QQuickItem *appletItem(const QString &plugin);   // a hosted applet's item by plugin id (null until loaded)
    Q_INVOKABLE void saveConfigKey(const QString &key, const QVariant &value);   // merge one key into config.json
    Q_INVOKABLE void removeConfigKey(const QString &key);                        // back to the built-in default
    // Settings page actions that are programs, not config keys (folder colour script, wallpaper). Detached, no shell.
    Q_INVOKABLE bool runDetached(const QString &program, const QStringList &arguments);
    Q_INVOKABLE QString homePath() const;
    Q_INVOKABLE QString picturesPath() const;                    // the user's Pictures folder (xdg-user-dirs), not a literal ~/Pictures
    Q_INVOKABLE QString toolPath(const QString &name) const;     // one of our scripts: on PATH, else in the installed checkout's scripts/, else ~/.local/bin; "" if nowhere
    // bumps whenever config.json changes on disk (from the settings window, an editor, anything): Config.qml re-reads, so
    // every design token is live
    // is Plasma's desktop shell on the bus? (our wallpaper layer shows by itself only when it is not)
    Q_PROPERTY(QString buildCommit READ buildCommit CONSTANT)     // the git commit this binary was built from (update check)
    QString buildCommit() const;
    Q_PROPERTY(bool plasmaRunning READ plasmaRunning NOTIFY plasmaRunningChanged)
    bool plasmaRunning() const { return m_plasmaRunning; }
    // "withoutPlasmashell": true in config.json (set by sirca-shell-switch): the shell serves org.kde.osdService itself
    Q_INVOKABLE void setWithoutPlasmashell(bool on);
    Q_PROPERTY(bool servesOsd READ servesOsd NOTIFY plasmaRunningChanged)
    bool servesOsd() const;
    Q_PROPERTY(int configRevision READ configRevision NOTIFY configRevisionChanged)
    int configRevision() const { return m_configRevision; }
    // Subscribe to a session-bus signal (empty service/path = any sender/any object); deliveries arrive as dbusSignal().
    Q_INVOKABLE void dbusListen(const QString &service, const QString &path, const QString &iface, const QString &signal);

public Q_SLOTS:
    void onDbusSignal(const QDBusMessage &msg);
    // D-Bus (service onur.SircaShell, path /SircaShell): KWin's Meta-key binding calls this, see sirca-shell-switch
    Q_SCRIPTABLE void toggleLauncher() { Q_EMIT launcherToggleRequested(); }
    // open/close a top-bar lobe by name ("clock", "gear", "media"); handy for scripts and for testing without a pointer
    Q_SCRIPTABLE void toggleLobe(const QString &name) { Q_EMIT lobeToggleRequested(name); }
    Q_SCRIPTABLE void openTrayMenu(int index) { Q_EMIT trayMenuRequested(index); }      // menu of the n-th visible tray icon (scripts, tests)
    Q_SCRIPTABLE void openSettings() { Q_EMIT settingsRequested(); }
    Q_SCRIPTABLE void openSettingsPage(int page) { Q_EMIT settingsPageRequested(page); }   // a bar widget sends you to its section
    Q_SCRIPTABLE void togglePowerMenu() { Q_EMIT shortcutActivated(QStringLiteral("power")); }
    Q_SCRIPTABLE void tileActive(double xFraction, double widthFraction) { tileActiveWindow(xFraction, widthFraction); }   // e.g. 0.25 0.5 = centred half
    Q_SCRIPTABLE void toggleTiles() { Q_EMIT shortcutActivated(QStringLiteral("tiles")); }
    Q_SCRIPTABLE void previewTiles() { Q_EMIT shortcutActivated(QStringLiteral("tiles-preview")); }   // dry run: zones only log
    Q_SCRIPTABLE void record() { Q_EMIT shortcutActivated(QStringLiteral("record")); }               // stop if recording, else the overlay in Record mode
    Q_SCRIPTABLE void recordRegion(int x, int y, int w, int h) { Q_EMIT recordRegionRequested(x, y, w, h); }   // scripted start (tests)
    Q_SCRIPTABLE void grabRegion(int x, int y, int w, int h) { Q_EMIT grabRegionRequested(x, y, w, h); }   // scripted screenshot of a rectangle, no overlay (saved + copied)
    Q_SCRIPTABLE void openThemePicker() { Q_EMIT shortcutActivated(QStringLiteral("theme-picker")); }   // quick settings with the colour popover open
    Q_INVOKABLE void raiseWallpaper();                             // a KWin script that keeps the shell's wallpaper above plasmashell's desktop (same layer; a desktop click raises Plasma's)
    // ---- update check (opt-in: config "updateCheck": true). Asks GitHub for the main branch's head once a day and, when it
    // differs from the commit this build came from, shows a notification with an "Update now" button that runs update.sh
    // from the installed folder (~/.local/state/<shell>/root.txt, written by install.sh) in a terminal.
    Q_INVOKABLE void checkForUpdate(bool announceUpToDate = false);
    Q_INVOKABLE void runUpdate();
    Q_SCRIPTABLE void checkUpdate() { checkForUpdate(true); }
    Q_SCRIPTABLE void remapWallpaper() { Q_EMIT remapWallpaperRequested(); }                  // put the shell's wallpaper back above plasmashell's desktop
    Q_SCRIPTABLE void desktopMenu(int x, int y) { Q_EMIT desktopMenuRequested(x, y); }     // the desktop's right-click menu at a point (tests, scripts)
    Q_SCRIPTABLE void toggleEditMode() { Q_EMIT shortcutActivated(QStringLiteral("edit")); }
    Q_SCRIPTABLE void screenshot() { Q_EMIT shortcutActivated(QStringLiteral("screenshot")); }
    Q_SCRIPTABLE void previewScreenshot() { Q_EMIT shortcutActivated(QStringLiteral("screenshot-preview")); }   // dry run on the wallpaper picture: nothing is captured, saved or copied
    Q_SCRIPTABLE void previewPowerMenu() { Q_EMIT shortcutActivated(QStringLiteral("power-preview")); }   // dry run: actions only log
    Q_SCRIPTABLE void toggleClipboard() { Q_EMIT shortcutActivated(QStringLiteral("clipboard")); }
    Q_SCRIPTABLE void showWelcome() { Q_EMIT shortcutActivated(QStringLiteral("welcome")); }          // the first-run card, again
    Q_SCRIPTABLE void toggleSearch() { Q_EMIT shortcutActivated(QStringLiteral("search")); }
    Q_SCRIPTABLE void previewSearch(const QString &query) { Q_EMIT searchPreviewRequested(query); }   // no keyboard grab, closes by itself
Q_SIGNALS:
    void primaryScreenChanged();
    void dbusSignal(const QString &iface, const QString &member, const QVariantList &args);
    void launcherToggleRequested();
    void lobeToggleRequested(const QString &name);
    void searchPreviewRequested(const QString &query);
    void settingsRequested();
    void settingsPageRequested(int page);
    void trayMenuRequested(int index);
    void configRevisionChanged();
    void plasmaRunningChanged();
    void recordRegionRequested(int x, int y, int w, int h);
    void grabRegionRequested(int x, int y, int w, int h);
    void desktopMenuRequested(int x, int y);
    void remapWallpaperRequested();
    void updateAvailable(const QString &commit);
    void switcherRequested(bool reverse);
    void shortcutActivated(const QString &id);   // one of the shell's own global shortcuts fired (see kShortcuts in shell.cpp)      // Alt+Tab / Alt+Shift+Tab (global shortcuts owned with --own-launcher-key)
private Q_SLOTS:
    void onNotificationAction(uint id, const QString &action);
    void onNotificationClosed(uint id, uint reason);
private:
    quint64 m_cpuIdle = 0, m_cpuTotal = 0;
    QHash<uint, QString> m_notifyPaths;                          // our notifications that open a folder when clicked
    bool m_notifyListening = false;
    void watchConfig();
    QJsonObject readConfigObject() const;
    void writeConfigObject(const QJsonObject &o);                   // atomic (QSaveFile); bumps configRevision itself
    QFileSystemWatcher m_configWatcher;
    QTimer m_configDebounce;
    QByteArray m_ownConfigBytes;                                    // what we last wrote: the watcher's echo of it is ignored
    int m_configRevision = 0;
    bool m_plasmaRunning = false;
    bool m_withoutPlasmashell = false;
    class OsdService *m_osd = nullptr;
    void updateOsdClaim();
    void initFakeInput();
    class QObject *m_fakeInput = nullptr;     // KWayland::Client::FakeInput
    bool m_fakeTried = false;
};
