// Keyboard state for the bar: the current layout (KWin's org.kde.keyboard /Layouts, session bus; the list comes back as
// a(sss), which Shell.dbusCall cannot hand to QML) and the Caps / Num lock state (KModifierKeyInfo, which on Wayland
// speaks org_kde_kwin_keystate: KWin hands that interface out only to a binary whose desktop file asks for it, see
// data/sirca-shell.desktop.in). A plain QML type of the shell's own module: nothing to fail to load.
#pragma once
#include <QObject>
#include <QStringList>
#include <QVariantMap>
#include <qqml.h>

class KModifierKeyInfo;

class KeyboardInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int layoutCount READ layoutCount NOTIFY layoutsChanged)
    Q_PROPERTY(int layoutIndex READ layoutIndex NOTIFY layoutsChanged)
    Q_PROPERTY(QString layoutShort READ layoutShort NOTIFY layoutsChanged)   // "us", "de" … (the short name KWin reports)
    Q_PROPERTY(QString layoutName READ layoutName NOTIFY layoutsChanged)     // "English (US)"
    Q_PROPERTY(QVariantList layouts READ layouts NOTIFY layoutsChanged)      // [{short, display, name}]
    Q_PROPERTY(bool capsLock READ capsLock NOTIFY locksChanged)
    Q_PROPERTY(bool numLock READ numLock NOTIFY locksChanged)
    Q_PROPERTY(bool locksKnown READ locksKnown NOTIFY locksChanged)          // the compositor told us about these keys at all
public:
    explicit KeyboardInfo(QObject *parent = nullptr);
    int layoutCount() const { return m_layouts.size(); }
    int layoutIndex() const { return m_index; }
    QString layoutShort() const;
    QString layoutName() const;
    QVariantList layouts() const;
    bool capsLock() const { return m_caps; }
    bool numLock() const { return m_num; }
    bool locksKnown() const { return m_locksKnown; }
    Q_INVOKABLE void nextLayout();
    Q_INVOKABLE void setLayout(int index);
Q_SIGNALS:
    void layoutsChanged();
    void locksChanged();
private Q_SLOTS:
    void onLayoutChanged(uint index);
    void onLayoutListChanged();
private:
    struct Layout { QString shortName, displayName, longName; };
    void refreshLayouts();
    void refreshLocks();
    QList<Layout> m_layouts;
    int m_index = 0;
    KModifierKeyInfo *m_keys = nullptr;
    bool m_caps = false, m_num = false, m_locksKnown = false;
};
