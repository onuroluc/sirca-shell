#include "recorderprocess.h"
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTimer>
#include <signal.h>

RecorderProcess::RecorderProcess(QObject *parent) : QObject(parent)
{
    for (QProcess *p : {&m_rec, &m_conv}) {
        p->setProcessChannelMode(QProcess::MergedChannels);
        p->setStandardOutputFile(QProcess::nullDevice());                // gsr prints a line every second
        connect(p, &QProcess::stateChanged, this, &RecorderProcess::runningChanged);
    }
    connect(&m_rec, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) { if (e == QProcess::FailedToStart) Q_EMIT finished(-2); });
    // ffmpeg missing: QProcess::finished never comes for a process that did not start, so the recording would have hung in
    // "finishing" forever. The HDR master stays where it is.
    connect(&m_conv, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) { if (e == QProcess::FailedToStart) { qWarning("recording: ffmpeg could not be started, the HDR master is kept: %s", qPrintable(m_master)); Q_EMIT finished(-3); } });
    m_probe.setProcessChannelMode(QProcess::MergedChannels);
    connect(&m_probe, &QProcess::finished, this, [this](int, QProcess::ExitStatus) { if (!m_probing) return;   // killed by the limit: its output is not trusted
        const QByteArray out = m_probe.readAllStandardOutput(); const int i = out.indexOf("HDR:"); m_hdr = i >= 0 && out.mid(i, 40).contains("enabled"); startRecording(); });
    connect(&m_probe, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) { startRecording(); });   // no kscreen-doctor: the last known state
    m_probeLimit.setSingleShot(true); m_probeLimit.setInterval(1500);
    connect(&m_probeLimit, &QTimer::timeout, this, [this] { if (m_probe.state() != QProcess::NotRunning) { m_probe.kill(); startRecording(); } });
    connect(&m_rec, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        if (!QFileInfo::exists(m_master) || QFileInfo(m_master).size() < 1024) { QFile::remove(m_master); Q_EMIT finished(code ? code : 1); return; }
        if (!m_hdr) { Q_EMIT finished(0); return; }                      // SDR: the recording already is the final file
        m_triedGpu = true; convert(true);
    });
    connect(&m_conv, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        const bool ok = status == QProcess::NormalExit && code == 0 && QFileInfo(m_file).size() > 1024;
        if (!ok && m_triedGpu) { m_triedGpu = false; QFile::remove(m_file); convert(false); return; }   // CPU path as the fallback
        if (ok) QFile::remove(m_master); else qWarning("recording: tonemapping failed, the HDR master is kept: %s", qPrintable(m_master));
        Q_EMIT finished(ok ? 0 : 5);
    });
}

RecorderProcess::~RecorderProcess()
{
    if (m_rec.state() != QProcess::NotRunning) { ::kill(pid_t(m_rec.processId()), SIGINT); if (!m_rec.waitForFinished(4000)) m_rec.kill(); }
}

bool RecorderProcess::start(int x, int y, int w, int h, const QString &file, bool sound)
{
    if (running()) return false;
    if (QStandardPaths::findExecutable(QStringLiteral("gpu-screen-recorder")).isEmpty()) { Q_EMIT finished(-2); return false; }
    m_file = file; m_width = w; m_x = x; m_y = y; m_h = h; m_sound = sound;
    // whether the output is in HDR mode decides the codec, and only KWin knows: kscreen-doctor is asked without holding the
    // shell (it took up to 1.5 s here); the recording starts from its answer, or from the last one after that long
    m_probing = true; Q_EMIT runningChanged();
    m_probe.start(QStringLiteral("kscreen-doctor"), {QStringLiteral("-o")});
    m_probeLimit.start();
    return true;
}

void RecorderProcess::startRecording()
{
    if (!m_probing) return;                                                // the limit and the finish can both get here
    m_probing = false; m_probeLimit.stop();
    // the HDR master sits next to the final file under a hidden name until it has been converted
    m_master = m_hdr ? QFileInfo(m_file).absolutePath() + QStringLiteral("/.") + QFileInfo(m_file).completeBaseName() + QStringLiteral(".hdr.mkv") : m_file;
    QStringList args{QStringLiteral("-w"), QStringLiteral("region"), QStringLiteral("-region"), QStringLiteral("%1x%2+%3+%4").arg(m_width).arg(m_h).arg(m_x).arg(m_y),
                     QStringLiteral("-f"), QStringLiteral("60"), QStringLiteral("-fm"), QStringLiteral("cfr"), QStringLiteral("-q"), QStringLiteral("very_high"),
                     QStringLiteral("-k"), m_hdr ? QStringLiteral("hevc_hdr") : (m_width <= 4096 ? QStringLiteral("h264") : QStringLiteral("hevc")), QStringLiteral("-cursor"), QStringLiteral("yes")};
    if (m_sound) args << QStringLiteral("-a") << QStringLiteral("default_output");
    args << QStringLiteral("-o") << m_master;
    m_rec.start(QStringLiteral("gpu-screen-recorder"), args);
    Q_EMIT runningChanged();
}

void RecorderProcess::stop()
{
    if (m_rec.state() != QProcess::NotRunning) ::kill(pid_t(m_rec.processId()), SIGINT);   // gsr finishes the file on SIGINT
}

void RecorderProcess::convert(bool gpu)
{
    // same two tonemapping chains as the Vice fork uses on this machine (BT.2390 on the GPU through libplacebo; hable on the CPU)
    QStringList a{QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"), QStringLiteral("error"), QStringLiteral("-y")};
    if (gpu) a << QStringLiteral("-init_hw_device") << QStringLiteral("vulkan=vk:0") << QStringLiteral("-filter_hw_device") << QStringLiteral("vk");
    a << QStringLiteral("-i") << m_master << QStringLiteral("-vf")
      << (gpu ? QStringLiteral("format=p010,hwupload,libplacebo=tonemapping=bt.2390:colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv:format=yuv420p,hwdownload,format=yuv420p")
              : QStringLiteral("zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"))
      ;
    // NVENC's H.264 stops at 4096 px wide; the full 5120-wide screen goes through x264 (slower, same quality target). The
    // CPU fallback is all-software: it runs when the GPU chain failed, so NVENC must not be asked for again.
    if (gpu && m_width <= 4096) a << QStringLiteral("-c:v") << QStringLiteral("h264_nvenc") << QStringLiteral("-preset") << QStringLiteral("p6") << QStringLiteral("-cq") << QStringLiteral("19");
    else a << QStringLiteral("-c:v") << QStringLiteral("libx264") << QStringLiteral("-preset") << QStringLiteral("fast") << QStringLiteral("-crf") << QStringLiteral("18");
    a
      << QStringLiteral("-pix_fmt") << QStringLiteral("yuv420p") << QStringLiteral("-c:a") << QStringLiteral("aac") << QStringLiteral("-b:a") << QStringLiteral("192k")
      << QStringLiteral("-movflags") << QStringLiteral("+faststart") << m_file;
    m_conv.start(QStringLiteral("ffmpeg"), a);
}
