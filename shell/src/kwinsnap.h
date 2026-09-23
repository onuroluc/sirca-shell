// Snap zones, the shell half of scripts/kwin-snap-zones.js. `KwinSnap` (a QML singleton) loads that KWin script while
// `enabled` (config key snapZones) and is the D-Bus object it reports to: /SnapZones on the shell's own service
// (onur.SircaShell), interface onur.SircaShell.SnapZones. Nothing here touches the Shell singleton or /SircaShell: the
// object is registered on the same connection, next to it. qml/SnapZones.qml listens to the signals.
#pragma once
#include <QObject>
#include <functional>
#include <qqml.h>

class KwinSnap : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "onur.SircaShell.SnapZones")
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)   // loads / unloads the KWin script
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)                       // KWin has the script (for the settings page / self-test)
public:
    explicit KwinSnap(QObject *parent = nullptr);
    bool enabled() const { return m_enabled; }
    void setEnabled(bool on);
    bool loaded() const { return m_loaded; }
    Q_INVOKABLE void reload();                    // unload + load (a fresh shell build carries a fresh script)

public Q_SLOTS:
    // called by the KWin script. KWin's callDBus hands an integral JS number over as int32 and a fractional one as double,
    // so both spellings are accepted (QtDBus picks the overload by the message signature)
    Q_SCRIPTABLE void dragStarted() { Q_EMIT started(); }
    Q_SCRIPTABLE void dragMoved(int x, int y) { Q_EMIT moved(x, y); }
    Q_SCRIPTABLE void dragMoved(double x, double y) { Q_EMIT moved(int(x), int(y)); }
    Q_SCRIPTABLE void dragFinished(int x, int y) { Q_EMIT finished(x, y); }
    Q_SCRIPTABLE void dragFinished(double x, double y) { Q_EMIT finished(int(x), int(y)); }

Q_SIGNALS:
    void enabledChanged();
    void loadedChanged();
    void started();                 // a window move began (cursor positions follow)
    void moved(int x, int y);       // global screen coordinates, ~30 a second
    void finished(int x, int y);    // the window was dropped with the cursor here

private:
    void unload(std::function<void()> then);
    void load();
    void setLoaded(bool on);
    bool m_enabled = false, m_loaded = false;
};
