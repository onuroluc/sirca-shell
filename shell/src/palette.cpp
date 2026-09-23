// Accent from the wallpaper. Twin of glass-desktop/tools/palette.py: same steps, same constants, same tie rules.
//   1. box-average down to <= 128 px on the long side (integer factor, remainder dropped, integer rounding)
//   2. median cut to 16 boxes: split the box with the widest channel range (ties: lower box index, then r,g,b) at the
//      median of that channel, stable sort by that one channel
//   3. score each box by chroma^2 x population in OKLab (squared: a wallpaper is mostly background, and plain
//      chroma x population let a big near-black area beat the actual bloom); boxes under chroma 0.03 or 0.2 % of the
//      picture are grey or a splash and never win
//   4. hue = population-weighted mean over every coloured box within 30 degrees of the winner (one box is a slice of a
//      gradient; the family of boxes is the colour); source chroma = the strongest one in that family
//   5. accent: that hue, chroma = source + 0.06 clamped to 0.10..0.20 (an accent sits on small controls, which need more
//      saturation than a wallpaper area to read as coloured at all), lightness 0.62 (+ up to 0.10 around yellow, which
//      is olive at 0.62), pulled back into sRGB by lowering chroma. The seven hand-picked Bloom accents sit at
//      L 0.57-0.73, C 0.10-0.19, so a derived accent lands in the same family.
#include "palette.h"
#include <QFutureWatcher>
#include <QJSEngine>
#include <QQmlEngine>
#include <QtConcurrent>
#include <QtMath>
#include <algorithm>
#include <array>
#include <cmath>
#include <numeric>
#include <vector>

namespace {
constexpr int kTarget = 128;
constexpr int kBoxes = 16;
constexpr double kMinChroma = 0.03;
constexpr double kMinPopulation = 0.002;
const double kHueFamily = qDegreesToRadians(30.0);
constexpr double kChromaLift = 0.06;
constexpr double kChromaLo = 0.10, kChromaHi = 0.20;
constexpr double kLDark = 0.62, kLLight = 0.50;

// ---- OKLab (Björn Ottosson, https://bottosson.github.io/posts/oklab/); the constants are the reference ones ---------
double srgbToLinear(double c) { return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4); }
double linearToSrgb(double c) { return c <= 0.0031308 ? c * 12.92 : 1.055 * std::pow(c, 1 / 2.4) - 0.055; }

struct Lab { double L, a, b; };
Lab rgbToOklab(double r, double g, double b)
{
    r = srgbToLinear(r); g = srgbToLinear(g); b = srgbToLinear(b);
    double l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    double m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    double s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
    l = std::cbrt(l); m = std::cbrt(m); s = std::cbrt(s);
    return { 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
             1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
             0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s };
}
std::array<double, 3> oklabToLinear(double L, double a, double b)
{
    const double l = std::pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
    const double m = std::pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
    const double s = std::pow(L - 0.0894841775 * a - 1.2914855480 * b, 3);
    return { 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s };
}
// sRGB 0..1 for an OKLCH colour, false when it is outside the gamut
bool oklchToRgb(double L, double C, double h, std::array<double, 3> &out)
{
    const auto lin = oklabToLinear(L, C * std::cos(h), C * std::sin(h));
    for (double v : lin) if (v < -0.0005 || v > 1.0005) return false;
    for (int i = 0; i < 3; ++i) out[i] = linearToSrgb(std::min(1.0, std::max(0.0, lin[i])));
    return true;
}
QString hexOf(const std::array<double, 3> &rgb)
{
    return QStringLiteral("#%1%2%3").arg(int(std::floor(rgb[0] * 255 + 0.5)), 2, 16, QLatin1Char('0'))
                                    .arg(int(std::floor(rgb[1] * 255 + 0.5)), 2, 16, QLatin1Char('0'))
                                    .arg(int(std::floor(rgb[2] * 255 + 0.5)), 2, 16, QLatin1Char('0'));
}
// out of gamut: pull the chroma in until it fits (the hue and the lightness are what the eye keeps)
QString oklchToHex(double L, double C, double h)
{
    std::array<double, 3> rgb{};
    while (C > 0.0) {
        if (oklchToRgb(L, C, h, rgb)) return hexOf(rgb);
        C = std::max(0.0, C - 0.005);
    }
    if (!oklchToRgb(L, 0.0, h, rgb)) rgb = { L, L, L };
    return hexOf(rgb);
}

using Px = std::array<int, 3>;

// box average with an integer factor: palette.py does the exact same sums
std::vector<Px> downscale(const QImage &src)
{
    const QImage im = src.convertToFormat(QImage::Format_RGB888);
    const int w = im.width(), h = im.height();
    const int f = std::max(1, (std::max(w, h) + kTarget - 1) / kTarget);
    const int ow = w / f, oh = h / f;
    const qint64 n = qint64(f) * f;
    std::vector<Px> out;
    out.reserve(size_t(ow) * oh);
    for (int oy = 0; oy < oh; ++oy) {
        for (int ox = 0; ox < ow; ++ox) {
            qint64 s[3] = {0, 0, 0};
            for (int y = oy * f; y < (oy + 1) * f; ++y) {
                const uchar *line = im.constScanLine(y) + 3 * ox * f;
                for (int x = 0; x < f; ++x) { s[0] += line[3 * x]; s[1] += line[3 * x + 1]; s[2] += line[3 * x + 2]; }
            }
            out.push_back({ int((s[0] * 2 + n) / (2 * n)), int((s[1] * 2 + n) / (2 * n)), int((s[2] * 2 + n) / (2 * n)) });   // round half up
        }
    }
    return out;
}

std::array<int, 3> rangesOf(const std::vector<Px> &px, const std::vector<int> &idx)
{
    Px lo = {255, 255, 255}, hi = {0, 0, 0};
    for (int i : idx) for (int c = 0; c < 3; ++c) { lo[c] = std::min(lo[c], px[i][c]); hi[c] = std::max(hi[c], px[i][c]); }
    return { hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2] };
}

std::vector<std::vector<int>> medianCut(const std::vector<Px> &px)
{
    std::vector<std::vector<int>> boxes;
    { std::vector<int> all(px.size()); std::iota(all.begin(), all.end(), 0); boxes.push_back(std::move(all)); }
    while (int(boxes.size()) < kBoxes) {
        int best = -1, bestRange = 0;
        for (size_t i = 0; i < boxes.size(); ++i) {
            if (boxes[i].size() < 2) continue;
            const auto r = rangesOf(px, boxes[i]);
            const int range = std::max({r[0], r[1], r[2]});
            if (range > bestRange) { best = int(i); bestRange = range; }     // strictly greater: ties keep the lower index
        }
        if (best < 0) break;
        std::vector<int> idx = std::move(boxes[best]);
        const auto r = rangesOf(px, idx);
        const int ch = r[0] >= r[1] && r[0] >= r[2] ? 0 : (r[1] >= r[2] ? 1 : 2);   // first maximum: r before g before b
        std::stable_sort(idx.begin(), idx.end(), [&](int a, int b) { return px[a][ch] < px[b][ch]; });
        const size_t half = idx.size() / 2;
        std::vector<int> lo(idx.begin(), idx.begin() + half), hi(idx.begin() + half, idx.end());
        boxes[best] = std::move(lo);
        boxes.insert(boxes.begin() + best + 1, std::move(hi));
    }
    return boxes;
}

struct Swatch { QString hex; double population, L, a, b, chroma, hue; };

std::vector<Swatch> swatchesOf(const std::vector<Px> &px, const std::vector<std::vector<int>> &boxes)
{
    std::vector<Swatch> out;
    const double total = double(px.size());
    for (const auto &idx : boxes) {
        qint64 s[3] = {0, 0, 0};
        for (int i : idx) for (int c = 0; c < 3; ++c) s[c] += px[i][c];
        const double mean[3] = { double(s[0]) / idx.size(), double(s[1]) / idx.size(), double(s[2]) / idx.size() };
        const Lab lab = rgbToOklab(mean[0] / 255, mean[1] / 255, mean[2] / 255);
        Swatch sw;
        sw.hex = hexOf({ mean[0] / 255, mean[1] / 255, mean[2] / 255 });
        sw.population = idx.size() / total;
        sw.L = lab.L; sw.a = lab.a; sw.b = lab.b;
        sw.chroma = std::hypot(lab.a, lab.b);
        sw.hue = std::atan2(lab.b, lab.a);
        out.push_back(sw);
    }
    return out;
}

double hueDistance(double h1, double h2)
{
    const double d = std::fmod(std::abs(h1 - h2), 2 * M_PI);
    return std::min(d, 2 * M_PI - d);
}

double accentLightness(double hue)
{
    // yellows at L 0.62 are olive / mustard (the eye wants yellow light): up to +0.10 around hue 90, nothing by 0 / 180
    const double y = std::max(0.0, std::cos(hue - qDegreesToRadians(90.0)));
    return kLDark + 0.10 * y * y;
}
} // namespace

Palette::Palette(QObject *parent) : QObject(parent) {}

QVariantMap Palette::analyse(const QImage &image)
{
    if (image.isNull()) return {};
    const std::vector<Px> px = downscale(image);
    if (px.empty()) return {};
    const std::vector<Swatch> sw = swatchesOf(px, medianCut(px));
    std::vector<const Swatch *> coloured, cand;
    for (const Swatch &s : sw) if (s.chroma >= kMinChroma) { coloured.push_back(&s); if (s.population >= kMinPopulation) cand.push_back(&s); }
    double hue, csrc;
    const Swatch *win;
    if (cand.empty()) {                       // a grey picture: the most common shade, and (nearly) no colour at all
        win = &sw[0];
        for (const Swatch &s : sw) if (s.population > win->population) win = &s;
        hue = win->hue; csrc = 0.0;
    } else {
        win = cand[0];
        for (const Swatch *s : cand) if (s->chroma * s->chroma * s->population > win->chroma * win->chroma * win->population) win = s;   // first strict maximum, like the Python
        double a = 0, b = 0; csrc = 0;
        for (const Swatch *s : coloured) {
            if (hueDistance(s->hue, win->hue) > kHueFamily) continue;
            a += s->population * s->a; b += s->population * s->b;
            if (s->population >= kMinPopulation) csrc = std::max(csrc, s->chroma);
        }
        hue = (a != 0.0 || b != 0.0) ? std::atan2(b, a) : win->hue;
    }
    const double C = csrc == 0.0 ? 0.02 : std::min(kChromaHi, std::max(kChromaLo, csrc + kChromaLift));
    const double L = accentLightness(hue);
    QVariantList swatches;
    std::vector<const Swatch *> byPop; for (const Swatch &s : sw) byPop.push_back(&s);
    std::stable_sort(byPop.begin(), byPop.end(), [](const Swatch *x, const Swatch *y) { return x->population > y->population; });
    for (const Swatch *s : byPop) swatches << QVariantMap{ {QStringLiteral("hex"), s->hex}, {QStringLiteral("population"), s->population}, {QStringLiteral("chroma"), s->chroma} };
    double deg = std::fmod(qRadiansToDegrees(hue), 360.0); if (deg < 0) deg += 360.0;
    return { {QStringLiteral("accent"), oklchToHex(L, C, hue)}, {QStringLiteral("accentLight"), oklchToHex(L - (kLDark - kLLight), C, hue)},
             {QStringLiteral("hue"), deg}, {QStringLiteral("chroma"), C}, {QStringLiteral("sourceChroma"), csrc}, {QStringLiteral("source"), win->hex},
             {QStringLiteral("swatches"), swatches} };
}

QVariantMap Palette::fromImage(const QString &path) const
{
    QString p = path;
    if (p.startsWith(QLatin1String("file://"))) p = QUrl(p).toLocalFile();
    return analyse(QImage(p));
}

QVariantMap Palette::themeForWallpaper(const QString &path, const QString &lightPath) const
{
    const QVariantMap r = fromImage(path);
    if (r.isEmpty()) return {};
    return { {QStringLiteral("accent"), r.value(QStringLiteral("accent"))}, {QStringLiteral("dark"), path}, {QStringLiteral("light"), lightPath.isEmpty() ? path : lightPath} };
}

void Palette::themeForWallpaperAsync(const QString &path, const QString &lightPath, const QJSValue &callback)
{
    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcher<QVariantMap>::finished, this, [this, watcher, callback]() mutable {
        watcher->deleteLater();
        if (callback.isCallable()) {
            QJSEngine *engine = qjsEngine(this);
            callback.call({ engine ? engine->toScriptValue(watcher->result()) : QJSValue() });
        }
    });
    watcher->setFuture(QtConcurrent::run([this, path, lightPath] { return themeForWallpaper(path, lightPath); }));
}
