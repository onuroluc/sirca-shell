// glass-palette [--json] IMAGE…: the accent a wallpaper asks for, from the shell's own Palette code. Prints one line per
// picture ("#rrggbb  path", or the whole analysis as JSON with --json). Exists so the C++ and the Python twin
// (glass-desktop/tools/palette.py) can be compared without starting the shell.
#include "palette.h"
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");   // QImage needs a QGuiApplication for the image plugins, not a display
    QGuiApplication app(argc, argv);
    QTextStream out(stdout), err(stderr);
    const QStringList args = app.arguments().mid(1);
    const bool json = args.contains(QStringLiteral("--json"));
    QStringList files;
    for (const QString &a : args) if (!a.startsWith(QLatin1String("--"))) files << a;
    if (files.isEmpty()) { err << "usage: glass-palette [--json] IMAGE...\n"; return 2; }
    Palette palette;
    int bad = 0;
    for (const QString &f : files) {
        const QVariantMap r = palette.fromImage(f);
        if (r.isEmpty()) { err << "glass-palette: cannot read " << f << "\n"; ++bad; continue; }
        if (json) out << QJsonDocument(QJsonObject::fromVariantMap(r)).toJson(QJsonDocument::Indented);
        else out << r.value(QStringLiteral("accent")).toString() << "  " << f << "\n";
    }
    return bad ? 1 : 0;
}
