#include "screenshot.h"
#include <KSystemClipboard>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QElapsedTimer>
#include <QFutureWatcher>
#include <QMimeData>
#include <QMutex>
#include <QStandardPaths>
#include <QtConcurrent>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

static QMutex s_lock;
static QImage s_frame;

QImage Screenshot::frame() { QMutexLocker l(&s_lock); return s_frame; }
bool Screenshot::ready() const { QMutexLocker l(&s_lock); return !s_frame.isNull(); }
Screenshot::Screenshot(QObject *parent) : QObject(parent) {}

QString Screenshot::folder() const
{
    return QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + QStringLiteral("/Screenshots");
}

// the window manager writes width*stride raw bytes into the pipe; read them off the GUI thread (a 5120x1440 frame is 29 MB)
static QImage readFrame(int fd, int width, int height, int stride, QImage::Format format)
{
    QImage img(width, height, format);
    if (img.isNull() || stride < img.bytesPerLine()) { close(fd); return {}; }
    for (int y = 0; y < height; ++y) {
        QByteArray line(stride, Qt::Uninitialized); int got = 0;
        while (got < stride) {
            pollfd p{fd, POLLIN, 0};
            if (poll(&p, 1, 4000) <= 0) { close(fd); return {}; }
            const ssize_t n = read(fd, line.data() + got, stride - got);
            if (n <= 0) { close(fd); return {}; }
            got += int(n);
        }
        memcpy(img.scanLine(y), line.constData(), img.bytesPerLine());
    }
    close(fd);
    return img;
}

void Screenshot::grab(const QString &screenName)
{
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) { Q_EMIT failed(QStringLiteral("pipe")); return; }
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin.ScreenShot2"), QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                    QStringLiteral("org.kde.KWin.ScreenShot2"), QStringLiteral("CaptureScreen"));
    // hide-caller-windows: KWin leaves the asking program's own windows out of the picture by default (meant for a screenshot
    // tool's own window). Our own windows are the bar and the dock, which belong in a picture of the desktop.
    const QVariantMap options{{QStringLiteral("native-resolution"), true}, {QStringLiteral("include-cursor"), false}, {QStringLiteral("hide-caller-windows"), false}};
    m.setArguments({screenName, options, QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]))});
    close(fds[1]);                                                       // the message holds its own copy
    const int readEnd = fds[0];
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(m, 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, readEnd](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<QVariantMap> reply = *w;
        if (reply.isError()) { close(readEnd); Q_EMIT failed(reply.error().message()); return; }
        const QVariantMap r = reply.value();
        const int width = r.value(QStringLiteral("width")).toInt(), height = r.value(QStringLiteral("height")).toInt(), stride = r.value(QStringLiteral("stride")).toInt();
        const auto format = QImage::Format(r.value(QStringLiteral("format")).toInt());
        if (r.value(QStringLiteral("type")).toString() != QLatin1String("raw") || width <= 0 || height <= 0) { close(readEnd); Q_EMIT failed(QStringLiteral("unexpected reply")); return; }
        auto *done = new QFutureWatcher<QImage>(this);
        connect(done, &QFutureWatcher<QImage>::finished, this, [this, done] {
            done->deleteLater();
            const QImage img = done->result();
            if (img.isNull()) { Q_EMIT failed(QStringLiteral("no picture data")); return; }
            { QMutexLocker l(&s_lock); s_frame = img; }
            ++m_revision; Q_EMIT frameChanged();
        });
        done->setFuture(QtConcurrent::run(readFrame, readEnd, width, height, stride, format));
    });
}

void Screenshot::useFile(const QString &path)
{
    const QImage img(path);
    if (img.isNull()) { Q_EMIT failed(QStringLiteral("cannot read ") + path); return; }
    { QMutexLocker l(&s_lock); s_frame = img; }
    ++m_revision; Q_EMIT frameChanged();
}

QString Screenshot::newVideoPath(const QString &extension) const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation) + QStringLiteral("/Screencasts");
    if (!QDir().mkpath(dir)) return {};
    return dir + QStringLiteral("/Recording_") + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss")) + QLatin1Char('.') + extension;
}

bool Screenshot::discardIfEmpty(const QString &path) const
{
    const QFileInfo fi(path);
    if (!fi.exists() || fi.size() >= 1024) return false;                // a header without frames is a few hundred bytes
    QFile::remove(path);
    return true;
}

void Screenshot::drop()
{
    { QMutexLocker l(&s_lock); s_frame = QImage(); }
    Q_EMIT frameChanged();
}

QString Screenshot::finish(qreal x, qreal y, qreal w, qreal h, qreal overlayWidth, bool clipboard, bool save)
{
    const QImage full = frame();
    if (full.isNull() || overlayWidth <= 0) return {};
    const qreal k = full.width() / overlayWidth;                        // overlay pixels -> frame pixels
    const QRect cut = QRectF(x * k, y * k, w * k, h * k).toAlignedRect().intersected(full.rect());
    if (cut.width() < 2 || cut.height() < 2) return {};
    const QImage out = full.copy(cut);
    QString path;
    if (clipboard) if (auto *c = KSystemClipboard::instance()) { auto *mime = new QMimeData; mime->setImageData(out); c->setMimeData(mime, QClipboard::Clipboard); }
    if (save) {
        QDir().mkpath(folder());
        const QString base = folder() + QStringLiteral("/Screenshot_") + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
        path = base + QStringLiteral(".png");
        // a second shot in the same second gets "-2", "-3", ...; the suffix goes on the file name only (cutting the whole
        // path at its first '-' mangled a folder name with a dash in it)
        for (int n = 2; QFile::exists(path); ++n) path = base + QStringLiteral("-%1.png").arg(n);
        // the PNG encode runs off the GUI thread: a 5120x1440 frame at zlib's default level took the desktop away for a
        // second or two ("full-screen screenshots take some time", 2026-09-23). Quality 60 = a light compression level:
        // a few times faster, files somewhat larger. saved() fires when the file is there.
        const int w = out.width(), h = out.height();
        auto *watcher = new QFutureWatcher<bool>(this);
        connect(watcher, &QFutureWatcher<bool>::finished, this, [this, watcher, path, w, h] { watcher->deleteLater();
            const bool ok = watcher->result(); qInfo("sirca-shell: screenshot %s %s", ok ? "written" : "FAILED", qPrintable(path));
            Q_EMIT saved(ok ? path : QString(), w, h); });
        watcher->setFuture(QtConcurrent::run([out, path] { QElapsedTimer t; t.start(); const bool ok = out.save(path, "PNG", 60); qInfo("sirca-shell: png encode %dx%d in %lld ms", out.width(), out.height(), t.elapsed()); return ok; }));
        return path;                                                  // the name it will have; the notification waits for saved()
    }
    Q_EMIT saved(path, out.width(), out.height());
    return path;
}
