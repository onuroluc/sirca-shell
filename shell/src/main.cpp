#include "shell.h"
#include "shellcorona.h"
#include "trayhost.h"
#include "screenshot.h"
#include <KLocalizedString>
#include <KLocalizedContext>
#include <QQmlContext>
#include <QApplication>
#include <QDir>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QDirIterator>
#include <QElapsedTimer>
#include <QFile>
#include <QQmlComponent>
#include <QTextStream>

int main(int argc, char **argv)
{
    // No Shell::useLayerShell(): that turns EVERY window of the process into a layer surface (tooltips, menus and
    // notification popups then land top-left or fullscreen). Qt >= 6.5 picks layer-shell per window via Window::get().
    // Qt falls back to the single-threaded 'basic' loop here (two windows then share one blocking swap: ~120 fps and
    // long hitches on a 240 Hz display); the threaded loop renders each surface on its own thread.
    // QtWayland pins every toplevel's position to 0,0 unless told otherwise; hosted applets position their tooltips and
    // notification popups through org_kde_plasma_surface.set_position from the QWindow position (plasmashell sets this too)
    Shell::markStart();
    qputenv("QT_WAYLAND_DISABLE_FIXED_POSITIONS", "1");
    if (!qEnvironmentVariableIsSet("QSG_RENDER_LOOP")) qputenv("QSG_RENDER_LOOP", "threaded");
    QQuickWindow::setDefaultAlphaBuffer(true);
    QApplication app(argc, argv);   // hosted Plasma applets use QMenu & co.
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("sirca-shell"));
    app.setApplicationName(QStringLiteral("sirca-shell"));
    app.setOrganizationDomain(QStringLiteral("onur"));
    app.setDesktopFileName(QStringLiteral("sirca-shell"));
    app.setQuitOnLastWindowClosed(false);
    if (app.arguments().contains(QStringLiteral("--release-launcher-key"))) { Shell::releaseLauncherKey(); QCoreApplication::processEvents(); return 0; }
    // The KDE desktop style, not "Basic": hosted applets and their settings windows are written for it (with Basic the tray's
    // settings page came up with bare, square, unthemed controls).
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    QCoreApplication::addLibraryPath(QDir::homePath() + QStringLiteral("/.local/lib/qt6/plugins"));   // applet forks that ride on a symlinked stock plugin
    // --check [dir ...]: compile every QML file of the shell (from the module's qmldir) and of the given applet folders,
    // WITHOUT creating anything. Catches what took the bar down on 2026-09-18: a bad property value in one file makes
    // the whole shell fail to load, and systemd then falls back to the Plasma panels. sirca-shell-reload runs this first
    // and refuses to restart a working shell with a broken build. Run with QT_QPA_PLATFORM=offscreen.
    if (app.arguments().contains(QStringLiteral("--version"))) { printf("%s %s (build %s)\n", qPrintable(QCoreApplication::applicationName()), GLASS_VERSION, GLASS_BUILD_COMMIT); return 0; }
    if (const int ci = app.arguments().indexOf(QStringLiteral("--check")); ci >= 0) {
        QQmlEngine engine;
        engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
        QTextStream out(stdout);
        QStringList urls;
        QFile qmldir(QStringLiteral(":/qt/qml/SircaShell/qmldir"));
        if (qmldir.open(QIODevice::ReadOnly)) {
            const QStringList lines = QString::fromUtf8(qmldir.readAll()).split(QLatin1Char('\n'));
            for (const QString &line : lines) {
                const QStringList parts = line.simplified().split(QLatin1Char(' '));
                if (!parts.isEmpty() && parts.last().endsWith(QStringLiteral(".qml"))) urls << QStringLiteral("qrc:/qt/qml/SircaShell/") + parts.last();
            }
        }
        { QDirIterator rit(QStringLiteral(":/qt/qml/SircaShell/qml/control"), {QStringLiteral("*.qml")}, QDir::Files, QDirIterator::Subdirectories);
          while (rit.hasNext()) urls << QStringLiteral("qrc") + rit.next(); }
        urls.removeDuplicates();
        for (int i = ci + 1; i < app.arguments().size(); ++i) {
            QDirIterator it(app.arguments().at(i), {QStringLiteral("*.qml")}, QDir::Files, QDirIterator::Subdirectories | QDirIterator::FollowSymlinks);
            while (it.hasNext()) urls << QUrl::fromLocalFile(it.next()).toString();
        }
        int bad = 0;
        for (const QString &u : std::as_const(urls)) {
            QQmlComponent c(&engine, QUrl(u));
            if (!c.isError()) continue;
            // Not checkable outside Plasma: `import plasma.applet.<id>` modules exist only once Plasma has loaded that applet's
            // plugin. Such a line, and the "Type X unavailable" that merely follows from another file's error, do not count;
            // the file with the real mistake always reports it itself.
            bool hard = false;
            const auto errors = c.errors();
            for (const QQmlError &e : errors) {
                const QString t = e.toString();
                const bool soft = t.contains(QStringLiteral("module \"plasma.applet.")) || t.endsWith(QStringLiteral(" unavailable"));
                if (!soft) { hard = true; out << "ERROR " << t << "\n"; }
            }
            if (hard) ++bad;
        }
        out << "sirca-shell --check: " << urls.size() << " files, " << bad << " with errors\n";
        return urls.isEmpty() ? 2 : (bad ? 1 : 0);
    }
    // --qml-test <file>: load one QML file and nothing else (no corona, no surfaces). With QT_QPA_PLATFORM=offscreen this
    // renders component previews to PNG without touching the screen — the way to check looks while a game is running.
    if (const int i = app.arguments().indexOf(QStringLiteral("--qml-test")); i >= 0 && i + 1 < app.arguments().size()) {
        QQmlApplicationEngine test;
        test.rootContext()->setContextObject(new KLocalizedContext(&test));
        test.addImageProvider(QStringLiteral("shot"), new ShotImageProvider);
        test.addImageProvider(QStringLiteral("tray"), new TrayImageProvider);
        test.load(QUrl::fromLocalFile(app.arguments().at(i + 1)));
        return test.rootObjects().isEmpty() ? 1 : app.exec();
    }
    // (no ShellCorona::self() here any more: the Plasma hosting layer starts only when an AppletHost is created, i.e. when
    // one of the "native … off" fallback switches is used)
    QQmlApplicationEngine engine;
    // i18n() for the native quick settings pages (they came from a Plasma applet, where Plasma provides it)
    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
    engine.addImageProvider(QStringLiteral("shot"), new ShotImageProvider);      // the frozen frame of the screenshot overlay
    engine.addImageProvider(QStringLiteral("tray"), new TrayImageProvider);      // pixmap icons of tray items (the engine owns it)
    const qint64 appReady = Shell::msSinceStart();
    QElapsedTimer loadTimer; loadTimer.start();
    engine.loadFromModule("SircaShell", "Main");
    qInfo("sirca-shell: start-up: app ready after %lld ms, QML loaded in %lld ms", appReady, loadTimer.elapsed());
    if (engine.rootObjects().isEmpty()) return 1;
    return app.exec();
}
