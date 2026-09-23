// A 32-band spectrum for the bar's level meter (config levelMeterStyle: "spectrum"). The peak meter's source
// (VolumeMonitor) only gives one number per reading, so this captures the default sink's monitor through libpipewire
// itself: a mono 48 kHz F32 capture stream (PipeWire mixes and resamples), a ring of the newest samples filled from the
// realtime thread, and a 1024-point FFT on the GUI thread 25 times a second while `active`. Costs while something plays:
// one extra capture node linked to the sink (the sink stays awake while the stream runs; it runs only while music plays
// and the bar is on screen) and ~25 small FFTs a second. Nothing runs while inactive. Without libpipewire at build time
// the type exists but stays silent, and the meter's plain bars are the fallback.
#pragma once
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <array>
#include <mutex>
#include <qqml.h>

class Spectrum : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool available READ available CONSTANT)                    // built with libpipewire
    Q_PROPERTY(QVariantList bands READ bands NOTIFY bandsChanged)         // 32 values 0..1, low to high, quantised to 1/11 (whole meter pixels)
public:
    static constexpr int kBands = 32;
    static constexpr int kFft = 1024;
    explicit Spectrum(QObject *parent = nullptr);
    ~Spectrum() override;
    bool active() const { return m_active; }
    void setActive(bool on);
    bool available() const;
    QVariantList bands() const { return m_bands; }
Q_SIGNALS:
    void activeChanged();
    void bandsChanged();
private:
    void start();
    void stop();
    void tick();
    void pushSamples(const float *samples, int n);                     // realtime thread
    struct Pw;
    Pw *m_pw = nullptr;
    bool m_active = false;
    QTimer m_timer;
    std::mutex m_lock;
    std::array<float, 4096> m_ring{};
    int m_ringPos = 0;
    std::array<float, kBands> m_level{}, m_shown{};
    float m_ref = 0.02f;                                               // auto-range: the loudest recent band, so quiet players still move
    QVariantList m_bands;
    friend struct SpectrumPwHooks;
};
