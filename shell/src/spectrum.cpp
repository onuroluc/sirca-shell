#include "spectrum.h"
#include <cmath>
#include <complex>
#include <cstring>
#include <vector>
#ifdef HAVE_PIPEWIRE
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#endif

static constexpr int kRate = 48000;

#ifdef HAVE_PIPEWIRE
struct Spectrum::Pw {
    pw_thread_loop *loop = nullptr;
    pw_context *context = nullptr;
    pw_core *core = nullptr;
    pw_stream *stream = nullptr;
    spa_hook listener{};
};

struct SpectrumPwHooks {
    // realtime thread: copy this cycle's samples into the ring, nothing else
    static void process(void *data) {
        auto *self = static_cast<Spectrum *>(data);
        pw_buffer *b = pw_stream_dequeue_buffer(self->m_pw->stream);
        if (!b) return;
        spa_buffer *buf = b->buffer;
        if (buf->datas[0].data) {
            const int stride = buf->datas[0].chunk->stride > 0 ? buf->datas[0].chunk->stride : int(sizeof(float));
            const int n = int(buf->datas[0].chunk->size) / stride;
            const float *s = reinterpret_cast<const float *>(static_cast<const char *>(buf->datas[0].data) + buf->datas[0].chunk->offset);
            self->pushSamples(s, n);
        }
        pw_stream_queue_buffer(self->m_pw->stream, b);
    }
};
static const pw_stream_events kEvents = { .version = PW_VERSION_STREAM_EVENTS, .process = SpectrumPwHooks::process };
#endif

Spectrum::Spectrum(QObject *parent) : QObject(parent)
{
    m_timer.setInterval(40);
    connect(&m_timer, &QTimer::timeout, this, &Spectrum::tick);
    for (int i = 0; i < kBands; ++i) m_bands << 0.0;
}

Spectrum::~Spectrum() { stop(); }

bool Spectrum::available() const
{
#ifdef HAVE_PIPEWIRE
    return true;
#else
    return false;
#endif
}

void Spectrum::setActive(bool on)
{
    if (on == m_active) return;
    m_active = on;
    if (on) start(); else stop();
    Q_EMIT activeChanged();
}

void Spectrum::pushSamples(const float *samples, int n)
{
    std::lock_guard<std::mutex> g(m_lock);
    for (int i = 0; i < n; ++i) { m_ring[m_ringPos] = samples[i]; m_ringPos = (m_ringPos + 1) % int(m_ring.size()); }
}

void Spectrum::start()
{
#ifdef HAVE_PIPEWIRE
    if (m_pw) return;
    static bool inited = false;
    if (!inited) { pw_init(nullptr, nullptr); inited = true; }
    m_pw = new Pw;
    m_pw->loop = pw_thread_loop_new("glass-spectrum", nullptr);
    if (!m_pw->loop) { delete m_pw; m_pw = nullptr; return; }
    m_pw->context = pw_context_new(pw_thread_loop_get_loop(m_pw->loop), nullptr, 0);
    m_pw->core = m_pw->context ? pw_context_connect(m_pw->context, nullptr, 0) : nullptr;
    if (!m_pw->core) { qWarning("sirca-shell: spectrum: cannot connect to PipeWire"); stop(); return; }
    // a capture stream on the default sink's monitor ("capture.sink"): PipeWire mixes to mono and resamples for us
    pw_properties *props = pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Capture", PW_KEY_MEDIA_ROLE, "Music",
                                             PW_KEY_STREAM_CAPTURE_SINK, "true", PW_KEY_NODE_NAME, "sirca-shell-spectrum", PW_KEY_APP_NAME, "Sirca Shell",
                                             PW_KEY_NODE_LATENCY, "1024/48000", nullptr);
    m_pw->stream = pw_stream_new(m_pw->core, "Sirca Shell spectrum", props);
    pw_stream_add_listener(m_pw->stream, &m_pw->listener, &kEvents, this);
    uint8_t buffer[1024];
    spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    spa_audio_info_raw info{};
    info.format = SPA_AUDIO_FORMAT_F32; info.rate = kRate; info.channels = 1;
    const spa_pod *params[1] = { spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info) };
    if (pw_stream_connect(m_pw->stream, PW_DIRECTION_INPUT, PW_ID_ANY, pw_stream_flags(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS), params, 1) < 0) { qWarning("sirca-shell: spectrum: stream connect failed"); stop(); return; }
    pw_thread_loop_start(m_pw->loop);
    m_timer.start();
#endif
}

void Spectrum::stop()
{
    m_timer.stop();
#ifdef HAVE_PIPEWIRE
    if (!m_pw) return;
    if (m_pw->loop) pw_thread_loop_stop(m_pw->loop);
    if (m_pw->stream) pw_stream_destroy(m_pw->stream);
    if (m_pw->core) pw_core_disconnect(m_pw->core);
    if (m_pw->context) pw_context_destroy(m_pw->context);
    if (m_pw->loop) pw_thread_loop_destroy(m_pw->loop);
    delete m_pw; m_pw = nullptr;
#endif
    m_shown.fill(0); m_level.fill(0);
    bool any = false; for (const QVariant &v : std::as_const(m_bands)) if (v.toDouble() > 0) { any = true; break; }
    if (any) { for (int i = 0; i < kBands; ++i) m_bands[i] = 0.0; Q_EMIT bandsChanged(); }
}

// in-place radix-2 FFT
static void fft(std::vector<std::complex<float>> &a)
{
    const int n = int(a.size());
    for (int i = 1, j = 0; i < n; ++i) { int bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) std::swap(a[i], a[j]); }
    for (int len = 2; len <= n; len <<= 1) {
        const float ang = -2.0f * float(M_PI) / float(len);
        const std::complex<float> wl(std::cos(ang), std::sin(ang));
        for (int i = 0; i < n; i += len) { std::complex<float> w(1, 0); for (int j = 0; j < len / 2; ++j) { const auto u = a[i + j], v = a[i + j + len / 2] * w; a[i + j] = u + v; a[i + j + len / 2] = u - v; w *= wl; } }
    }
}

// GUI thread, 25x a second: window the newest 1024 samples, FFT, 32 log-spaced bands from 50 Hz to 16 kHz, dB scaled
// against the loudest recent band (rise at once, fall slowly), quantised to whole meter pixels; announced only on change
void Spectrum::tick()
{
    static std::vector<std::complex<float>> buf(kFft);
    static std::vector<float> window;
    if (window.empty()) { window.resize(kFft); for (int i = 0; i < kFft; ++i) window[i] = 0.5f * (1.0f - std::cos(2.0f * float(M_PI) * float(i) / float(kFft - 1))); }
    {
        std::lock_guard<std::mutex> g(m_lock);
        int p = (m_ringPos - kFft + int(m_ring.size())) % int(m_ring.size());
        for (int i = 0; i < kFft; ++i) { buf[i] = std::complex<float>(m_ring[p] * window[i], 0); p = (p + 1) % int(m_ring.size()); }
    }
    fft(buf);
    const float binHz = float(kRate) / float(kFft);
    float loudest = 0;
    for (int k = 0; k < kBands; ++k) {
        const float lo = 50.0f * std::pow(320.0f, float(k) / kBands), hi = 50.0f * std::pow(320.0f, float(k + 1) / kBands);
        int b0 = std::max(1, int(lo / binHz)), b1 = std::max(b0, int(hi / binHz));
        float m = 0; for (int b = b0; b <= b1 && b < kFft / 2; ++b) m = std::max(m, std::abs(buf[b]));
        m = m * 2.0f / float(kFft);                                       // amplitude, 0..1 for a full-scale sine
        m_level[k] = m; loudest = std::max(loudest, m);
    }
    m_ref = std::max(0.002f, std::max(loudest, m_ref * 0.9965f));         // like the peak meter: the reference decays by half in ~8 s
    bool changed = false;
    for (int k = 0; k < kBands; ++k) {
        const float rel = m_level[k] / m_ref;
        const float db = rel > 1e-5f ? 20.0f * std::log10(rel) : -100.0f;
        float v = std::clamp((db + 42.0f) / 42.0f, 0.0f, 1.0f);           // 42 dB of range under the reference
        v = v > m_shown[k] ? v : std::max(v, m_shown[k] * 0.78f);
        m_shown[k] = v;
        const double q = std::round(v * 11.0) / 11.0;
        if (std::abs(q - m_bands[k].toDouble()) > 1e-6) { m_bands[k] = q; changed = true; }
    }
    if (changed) Q_EMIT bandsChanged();
}
