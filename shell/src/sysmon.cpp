#include "sysmon.h"
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFutureWatcher>
#include <QStandardPaths>
#include <QtConcurrent>
#include <algorithm>
#include <csignal>
#include <unistd.h>

static QByteArray readAll(const QString &path, int max = 1 << 16)
{
    QFile f(path); if (!f.open(QIODevice::ReadOnly)) return {}; return f.read(max);
}

static qint64 nowMs() { static QElapsedTimer t; if (!t.isValid()) t.start(); return t.elapsed(); }

SysStats::SysStats(QObject *parent) : QObject(parent)
{
    m_timer.setInterval(2000);
    connect(&m_timer, &QTimer::timeout, this, &SysStats::sample);
    m_second.setSingleShot(true); m_second.setInterval(600);       // the first sample has nothing to diff against: a quick second one fills the lobe
    connect(&m_second, &QTimer::timeout, this, &SysStats::sample);
    // the CPU's name and core count, once
    const QList<QByteArray> lines = readAll(QStringLiteral("/proc/cpuinfo")).split('\n');
    int cores = 0;
    for (const QByteArray &l : lines) { if (l.startsWith("processor")) ++cores; else if (m_cpuName.isEmpty() && l.startsWith("model name")) m_cpuName = QString::fromUtf8(l.mid(l.indexOf(':') + 1)).simplified(); }
    m_coreCount = qMax(1, cores);
    // the GPU: the first DRM card with a PCI vendor; NVIDIA is asked through nvidia-smi (no sysfs load counter with the
    // proprietary/open driver), AMD through sysfs, Intel is left at "n/a"
    const QDir drm(QStringLiteral("/sys/class/drm"));
    for (const QString &card : drm.entryList({QStringLiteral("card[0-9]"), QStringLiteral("card[0-9][0-9]")}, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        const QString dev = drm.filePath(card) + QStringLiteral("/device");
        const QByteArray vendor = readAll(dev + QStringLiteral("/vendor")).trimmed();
        if (vendor == "0x10de") m_gpuVendor = QStringLiteral("nvidia"); else if (vendor == "0x1002") m_gpuVendor = QStringLiteral("amd"); else if (vendor == "0x8086") m_gpuVendor = QStringLiteral("intel"); else continue;
        m_drmDevice = dev; break;
    }
    if (m_gpuVendor == QLatin1String("nvidia") && QStandardPaths::findExecutable(QStringLiteral("nvidia-smi")).isEmpty()) m_gpuVendor.clear();   // driver without its tool: n/a
    m_gpu = {{QStringLiteral("vendor"), m_gpuVendor}, {QStringLiteral("available"), false}, {QStringLiteral("load"), 0.0}, {QStringLiteral("temp"), 0}, {QStringLiteral("memUsed"), 0.0}, {QStringLiteral("memTotal"), 0.0}, {QStringLiteral("name"), QString()}};
}

void SysStats::setActive(bool on)
{
    if (on == m_active) return;
    m_active = on; Q_EMIT activeChanged();
    if (on) { sample(); m_second.start(); m_timer.start(); }
    else { m_timer.stop(); m_second.stop(); m_s.prev = Prev(); }    // stale deltas would make the first reading after a reopen nonsense
}

void SysStats::sample()
{
    if (m_busy) return;
    m_busy = true;
    const Prev prev = m_s.prev; const QString vendor = m_gpuVendor, dev = m_drmDevice;
    auto *w = new QFutureWatcher<Sample>(this);
    connect(w, &QFutureWatcher<Sample>::finished, this, [this, w] {
        w->deleteLater(); m_busy = false;
        if (!m_active) return;
        m_s = w->result();
        if (m_gpuVendor == QLatin1String("amd")) m_gpu = m_s.gpu;
        Q_EMIT updated();
    });
    w->setFuture(QtConcurrent::run(read, prev, vendor, dev));
    if (m_gpuVendor == QLatin1String("nvidia")) pollGpu();
}

// nvidia-smi is a process, so it is asked asynchronously alongside the sample; its answer lands in the next updated()
void SysStats::pollGpu()
{
    if (m_smi) return;
    m_smi = new QProcess(this);
    connect(m_smi, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        const QList<QByteArray> p = m_smi->readAllStandardOutput().trimmed().split(',');
        m_smi->deleteLater(); m_smi = nullptr;
        if (code != 0 || p.size() < 4) { m_gpu[QStringLiteral("available")] = false; return; }
        m_gpu[QStringLiteral("available")] = true;
        m_gpu[QStringLiteral("load")] = p.at(0).trimmed().toDouble() / 100.0;
        m_gpu[QStringLiteral("temp")] = p.at(1).trimmed().toInt();
        m_gpu[QStringLiteral("memUsed")] = p.at(2).trimmed().toDouble() * 1024 * 1024;
        m_gpu[QStringLiteral("memTotal")] = p.at(3).trimmed().toDouble() * 1024 * 1024;
        if (p.size() > 4) m_gpu[QStringLiteral("name")] = QString::fromUtf8(p.at(4).trimmed());
        Q_EMIT updated();
    });
    connect(m_smi, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) { if (m_smi) { m_smi->deleteLater(); m_smi = nullptr; } m_gpu[QStringLiteral("available")] = false; });
    m_smi->start(QStringLiteral("nvidia-smi"), {QStringLiteral("--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,name"), QStringLiteral("--format=csv,noheader,nounits")});
}

SysStats::Sample SysStats::read(const Prev &prev, const QString &vendor, const QString &dev)
{
    Sample s; s.prev.when = nowMs();
    const double dt = prev.when > 0 ? qMax(1, s.prev.when - prev.when) / 1000.0 : 0;
    // ---- CPU: /proc/stat's aggregate line and one per core
    for (const QByteArray &l : readAll(QStringLiteral("/proc/stat")).split('\n')) {
        if (!l.startsWith("cpu")) break;
        const QList<QByteArray> p = l.simplified().split(' ');
        quint64 total = 0, idle = 0; for (int i = 1; i < p.size() && i <= 8; ++i) { const quint64 v = p.at(i).toULongLong(); total += v; if (i == 4 || i == 5) idle += v; }
        if (p.first() == "cpu") { s.prev.total = total; continue; }
        const int core = s.prev.coreTotal.size(); s.prev.coreTotal << total; s.prev.coreIdle << idle;
        double load = 0;
        if (core < prev.coreTotal.size() && total > prev.coreTotal.at(core)) load = 1.0 - double(idle - prev.coreIdle.at(core)) / double(total - prev.coreTotal.at(core));
        s.cores << qBound(0.0, load, 1.0);
    }
    if (!s.cores.isEmpty()) { double sum = 0; for (const QVariant &v : s.cores) sum += v.toDouble(); s.cpu = sum / s.cores.size(); }
    // ---- memory
    for (const QByteArray &l : readAll(QStringLiteral("/proc/meminfo"), 4096).split('\n')) {
        const auto kb = [&l] { return l.mid(l.indexOf(':') + 1).simplified().split(' ').first().toDouble() * 1024; };
        if (l.startsWith("MemTotal:")) s.memTotal = kb(); else if (l.startsWith("MemAvailable:")) s.memUsed = s.memTotal - kb();
        else if (l.startsWith("SwapTotal:")) s.swapTotal = kb(); else if (l.startsWith("SwapFree:")) s.swapUsed = s.swapTotal - kb();
    }
    // ---- network: every interface but lo, bytes received / transmitted
    quint64 rx = 0, tx = 0;
    for (const QByteArray &l : readAll(QStringLiteral("/proc/net/dev")).split('\n')) {
        const int c = l.indexOf(':'); if (c < 0) continue;
        const QByteArray name = l.left(c).trimmed(); if (name == "lo") continue;
        const QList<QByteArray> p = l.mid(c + 1).simplified().split(' '); if (p.size() < 9) continue;
        rx += p.at(0).toULongLong(); tx += p.at(8).toULongLong();
    }
    s.prev.rx = rx; s.prev.tx = tx;
    if (dt > 0 && rx >= prev.rx && tx >= prev.tx) { s.netDown = (rx - prev.rx) / dt; s.netUp = (tx - prev.tx) / dt; }
    // ---- processes: user + system ticks per pid; the busiest five since the previous sample, as a share of one core
    struct P { int pid; QString name; double cpu, mem; };
    QList<P> procs;
    const long page = sysconf(_SC_PAGESIZE);
    const int ncores = qMax(1, int(s.cores.size()));
    const double dTotal = (prev.total > 0 && s.prev.total > prev.total) ? double(s.prev.total - prev.total) / ncores : 0;   // ticks one core had
    const QDir proc(QStringLiteral("/proc"));
    for (const QString &d : proc.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool isPid = false; const int pid = d.toInt(&isPid); if (!isPid) continue;
        const QByteArray stat = readAll(QStringLiteral("/proc/") + d + QStringLiteral("/stat"), 2048); if (stat.isEmpty()) continue;
        const int close = stat.lastIndexOf(')'); if (close < 0) continue;   // the name is in parentheses and may contain spaces
        const QList<QByteArray> f = stat.mid(close + 2).simplified().split(' '); if (f.size() < 22) continue;   // f[0] = state (field 3)
        const quint64 ticks = f.at(11).toULongLong() + f.at(12).toULongLong();   // utime + stime (fields 14, 15)
        const double rss = f.at(21).toDouble() * page;                      // field 24
        s.prev.pidTicks.insert(pid, ticks);
        if (rss <= 0) continue;                                              // kernel threads
        double cpu = 0; const auto it = prev.pidTicks.constFind(pid);
        if (dTotal > 0 && it != prev.pidTicks.constEnd() && ticks >= it.value()) cpu = 100.0 * double(ticks - it.value()) / dTotal;
        if (cpu <= 0 && procs.size() >= 5) continue;                         // idle ones only matter while there is nothing busier
        procs.append({pid, QString::fromUtf8(stat.mid(stat.indexOf('(') + 1, close - stat.indexOf('(') - 1)), cpu, rss});
    }
    std::sort(procs.begin(), procs.end(), [](const P &a, const P &b) { return a.cpu != b.cpu ? a.cpu > b.cpu : a.mem > b.mem; });
    for (int i = 0; i < procs.size() && i < 5; ++i) s.procs << QVariantMap{{QStringLiteral("pid"), procs.at(i).pid}, {QStringLiteral("name"), procs.at(i).name}, {QStringLiteral("cpu"), procs.at(i).cpu}, {QStringLiteral("mem"), procs.at(i).mem}};
    // ---- AMD GPU from sysfs (NVIDIA is polled separately, Intel has no load counter here)
    if (vendor == QLatin1String("amd") && !dev.isEmpty()) {
        QVariantMap g{{QStringLiteral("vendor"), vendor}, {QStringLiteral("available"), false}, {QStringLiteral("load"), 0.0}, {QStringLiteral("temp"), 0}, {QStringLiteral("memUsed"), 0.0}, {QStringLiteral("memTotal"), 0.0}, {QStringLiteral("name"), QString()}};
        const QByteArray busy = readAll(dev + QStringLiteral("/gpu_busy_percent")).trimmed();
        if (!busy.isEmpty()) { g[QStringLiteral("available")] = true; g[QStringLiteral("load")] = busy.toDouble() / 100.0; }
        g[QStringLiteral("memUsed")] = readAll(dev + QStringLiteral("/mem_info_vram_used")).trimmed().toDouble();
        g[QStringLiteral("memTotal")] = readAll(dev + QStringLiteral("/mem_info_vram_total")).trimmed().toDouble();
        const QDir hw(dev + QStringLiteral("/hwmon"));
        for (const QString &h : hw.entryList({QStringLiteral("hwmon*")}, QDir::Dirs | QDir::NoDotAndDotDot)) {
            const QByteArray t = readAll(hw.filePath(h) + QStringLiteral("/temp1_input")).trimmed();   // edge temperature, millidegrees
            if (!t.isEmpty()) { g[QStringLiteral("temp")] = int(t.toDouble() / 1000); break; }
        }
        s.gpu = g;
    }
    return s;
}

void SysStats::endProcess(int pid)
{
    if (pid <= 1 || pid == getpid()) return;
    ::kill(pid, SIGTERM);
}

QString SysStats::human(double bytes, int decimals)
{
    static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    int i = 0; while (bytes >= 1000 && i < 4) { bytes /= 1000; ++i; }
    return QString::number(bytes, 'f', i == 0 ? 0 : decimals) + QLatin1Char(' ') + QLatin1String(units[i]);
}
