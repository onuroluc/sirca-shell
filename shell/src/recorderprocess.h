// Screen recording through gpu-screen-recorder (NVENC, constant 60 fps, desktop sound). It reads the screen from the
// display hardware (KMS), so nothing is filtered out of the picture — a stream asked from KWin leaves the asking
// process's windows out, and KDE's own recorder library stalled on this 5120-wide NVIDIA set-up. With HDR on, the
// recording is an HDR master (HEVC 10 bit) that is tonemapped to an ordinary SDR H.264 .mp4 when you stop; with HDR off
// it is written as H.264 directly.
#pragma once
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <qqmlintegration.h>

class RecorderProcess : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)          // recording or converting
    Q_PROPERTY(bool converting READ converting NOTIFY runningChanged)
public:
    explicit RecorderProcess(QObject *parent = nullptr);
    ~RecorderProcess() override;
    bool running() const { return m_probing || m_rec.state() != QProcess::NotRunning || converting(); }
    bool converting() const { return m_conv.state() != QProcess::NotRunning; }
    Q_INVOKABLE bool start(int x, int y, int w, int h, const QString &file, bool sound);
    Q_INVOKABLE void stop();                                   // finishes the file; finished() follows (after converting)
Q_SIGNALS:
    void runningChanged();
    void finished(int code);                                   // 0 ok, -2 recorder missing, -3 ffmpeg missing, other: see the journal
private:
    void convert(bool gpu);
    void startRecording();                                     // after the HDR probe
    QProcess m_rec, m_conv, m_probe;
    QTimer m_probeLimit;
    QString m_file, m_master;
    bool m_hdr = false, m_triedGpu = false, m_probing = false, m_sound = false;
    int m_width = 0, m_x = 0, m_y = 0, m_h = 0;
};
