// System monitor readings for the bar's CPU / memory lobe (qml/SysMon.qml): per-core CPU, memory, GPU load and
// temperature, network rate and the busiest processes. All readers are here (/proc, /sys, nvidia-smi) and run on a
// worker thread; the GUI thread only gets the finished sample. Nothing is read while `active` is false: the lobe
// switches it on when it opens and off when it closes.
#pragma once
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <qqml.h>

class SysStats : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)   // ms between samples
    Q_PROPERTY(QVariantList cores READ cores NOTIFY updated)         // 0..1 per core, since the previous sample
    Q_PROPERTY(double cpu READ cpu NOTIFY updated)                   // 0..1 over all cores
    Q_PROPERTY(double memUsed READ memUsed NOTIFY updated)           // bytes (total - available)
    Q_PROPERTY(double memTotal READ memTotal NOTIFY updated)
    Q_PROPERTY(double swapUsed READ swapUsed NOTIFY updated)
    Q_PROPERTY(double swapTotal READ swapTotal NOTIFY updated)
    Q_PROPERTY(QVariantMap gpu READ gpu NOTIFY updated)              // {vendor, name, available, load 0..1, temp °C, memUsed, memTotal (bytes)}
    Q_PROPERTY(double netUp READ netUp NOTIFY updated)               // bytes per second, every interface but lo
    Q_PROPERTY(double netDown READ netDown NOTIFY updated)
    Q_PROPERTY(QVariantList procs READ procs NOTIFY updated)         // top 5 by CPU: {pid, name, cpu (% of one core), mem (bytes)}
    Q_PROPERTY(QString cpuName READ cpuName CONSTANT)
    Q_PROPERTY(int coreCount READ coreCount CONSTANT)
public:
    struct Prev {                                                    // what the next sample's deltas are taken against
        QList<quint64> coreTotal, coreIdle;
        quint64 total = 0;
        quint64 rx = 0, tx = 0;
        qint64 when = 0;                                             // ms, monotonic
        QHash<int, quint64> pidTicks;
    };
    struct Sample {
        QVariantList cores; double cpu = 0;
        double memUsed = 0, memTotal = 0, swapUsed = 0, swapTotal = 0;
        double netUp = 0, netDown = 0;
        QVariantList procs;
        QVariantMap gpu;
        Prev prev;
    };
    explicit SysStats(QObject *parent = nullptr);
    bool active() const { return m_active; }
    void setActive(bool on);
    int interval() const { return m_timer.interval(); }
    void setInterval(int ms) { if (ms == m_timer.interval()) return; m_timer.setInterval(qMax(500, ms)); Q_EMIT intervalChanged(); }
    QVariantList cores() const { return m_s.cores; }
    double cpu() const { return m_s.cpu; }
    double memUsed() const { return m_s.memUsed; }
    double memTotal() const { return m_s.memTotal; }
    double swapUsed() const { return m_s.swapUsed; }
    double swapTotal() const { return m_s.swapTotal; }
    QVariantMap gpu() const { return m_gpu; }
    double netUp() const { return m_s.netUp; }
    double netDown() const { return m_s.netDown; }
    QVariantList procs() const { return m_s.procs; }
    QString cpuName() const { return m_cpuName; }
    int coreCount() const { return m_coreCount; }
    Q_INVOKABLE void endProcess(int pid);                            // SIGTERM (the process may ignore it; nothing stronger from here)
    Q_INVOKABLE static QString human(double bytes, int decimals = 1);   // "1.2 GB"
Q_SIGNALS:
    void activeChanged();
    void intervalChanged();
    void updated();
private:
    void sample();
    void pollGpu();
    static Sample read(const Prev &prev, const QString &vendor, const QString &drmDevice);
    bool m_active = false, m_busy = false;
    QTimer m_timer, m_second;
    Sample m_s;
    QVariantMap m_gpu;
    QString m_cpuName, m_gpuVendor, m_drmDevice;                     // vendor: "nvidia" | "amd" | "intel" | ""
    int m_coreCount = 1;
    QProcess *m_smi = nullptr;                                       // nvidia-smi, one at a time
};
