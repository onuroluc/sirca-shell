// Camera and screen-sharing use, from PipeWire's registry (libpipewire, event-driven: no polling, no pw-dump). A camera
// read through PipeWire is a "Video/Source" node (device.api v4l2 / libcamera) in the RUNNING state, or a
// "Stream/Input/Video" consumer; a screen share is KWin's screencast stream ("kwin_screencast" nodes, made for every
// xdg-desktop-portal ScreenCast session and torn down with it) and the consumers linked to it. Links tell a screen
// consumer from a camera consumer. An app that opens /dev/video* with V4L2 directly, bypassing PipeWire, is not seen.
// Microphone use is not here: plasma-pa's SourceOutputModel already has it (VolumeBackend.qml).
// Built without libpipewire the type exists with `available` = false, so the QML never changes.
#pragma once
#include <QObject>
#include <QStringList>
#include <qqml.h>

class PrivacyMonitor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)   // built with PipeWire and connected to it
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)   // connect to PipeWire at all (off = no thread, no socket)
    Q_PROPERTY(bool camera READ camera NOTIFY stateChanged)
    Q_PROPERTY(bool screen READ screen NOTIFY stateChanged)
    Q_PROPERTY(QStringList cameraApps READ cameraApps NOTIFY stateChanged)   // application names, for the tooltip
    Q_PROPERTY(QStringList screenApps READ screenApps NOTIFY stateChanged)
public:
    explicit PrivacyMonitor(QObject *parent = nullptr);
    ~PrivacyMonitor() override;
    bool available() const { return m_available; }
    bool active() const { return m_active; }
    void setActive(bool on);
    bool camera() const { return !m_cameraApps.isEmpty(); }
    bool screen() const { return !m_screenApps.isEmpty(); }
    QStringList cameraApps() const { return m_cameraApps; }
    QStringList screenApps() const { return m_screenApps; }
Q_SIGNALS:
    void availableChanged();
    void activeChanged();
    void stateChanged();
private:
    void start();
    void stop();
    // called on the GUI thread with the loop thread's verdict
    Q_INVOKABLE void publish(bool available, const QStringList &cameraApps, const QStringList &screenApps);
    bool m_available = false, m_active = false;
    QStringList m_cameraApps, m_screenApps;
    struct Private;
    Private *d = nullptr;
};
