cmake_minimum_required(VERSION 3.20)
project(sirca-shell VERSION 0.5.0 LANGUAGES C CXX)   # the released version: bump here, the public VERSION file and tag follow (see publish/make_public.sh)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus Widgets Concurrent Network)
# the commit this build comes from (the update check compares it with the repository's main branch)
execute_process(COMMAND git rev-parse HEAD WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} OUTPUT_VARIABLE GLASS_BUILD_COMMIT OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
if(NOT GLASS_BUILD_COMMIT)
    execute_process(COMMAND git -C ${CMAKE_SOURCE_DIR}/.. rev-parse HEAD OUTPUT_VARIABLE GLASS_BUILD_COMMIT OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
endif()
add_compile_definitions(GLASS_BUILD_COMMIT="${GLASS_BUILD_COMMIT}" GLASS_VERSION="${PROJECT_VERSION}")
find_package(LayerShellQt REQUIRED)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6 REQUIRED COMPONENTS Package Config I18n GlobalAccel Service GuiAddons)
find_package(Plasma REQUIRED)
find_package(PlasmaQuick REQUIRED)
find_package(KWayland REQUIRED)          # fake input: pass the click that dismissed a popup on to the window under it
# optional: camera / screen-share indicators watch PipeWire's registry (src/privacymonitor.cpp); without it they stay off
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(PipeWire IMPORTED_TARGET libpipewire-0.3)
endif()

qt_standard_project_setup(REQUIRES 6.6)

set_source_files_properties(qml/Config.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_executable(sirca-shell src/main.cpp src/shell.cpp src/shell.h src/shellcorona.cpp src/shellcorona.h src/applethost.cpp src/applethost.h src/appsmodel.cpp src/appsmodel.h src/trayhost.cpp src/trayhost.h src/osdservice.cpp src/osdservice.h src/clipboardmodel.cpp src/clipboardmodel.h src/screenshot.cpp src/screenshot.h src/recorderprocess.cpp src/recorderprocess.h src/powerinfo.cpp src/powerinfo.h src/keyboardinfo.cpp src/keyboardinfo.h src/privacymonitor.cpp src/privacymonitor.h src/calendarmodel.cpp src/calendarmodel.h src/weather.cpp src/weather.h src/removable.cpp src/removable.h src/lyrics.cpp src/lyrics.h src/spectrum.cpp src/spectrum.h src/shortcutsmodel.cpp src/shortcutsmodel.h src/emojimodel.cpp src/emojimodel.h src/sysmon.cpp src/sysmon.h src/palette.cpp src/palette.h src/userwidgets.cpp src/userwidgets.h src/kwinsnap.cpp src/kwinsnap.h)
qt_add_qml_module(sirca-shell
    URI SircaShell
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Config.qml
        qml/Surface.qml
        qml/ScreenSet.qml
        qml/TopBar.qml
        qml/Dock.qml
        qml/MediaIsland.qml
        qml/MediaSource.qml
        qml/LevelMeter.qml
        qml/MediaPanel.qml
        qml/DockAudio.qml
        qml/NetworkBackend.qml
        qml/BluetoothBackend.qml
        qml/BrightnessBackend.qml
        qml/VolumeBackend.qml
        qml/BarBattery.qml
        qml/BarMic.qml
        qml/BarPrivacy.qml
        qml/BarKeyboard.qml
        qml/QSCaffeine.qml
        qml/QSAutoMode.qml
        qml/Search.qml
        qml/SearchResults.qml
        qml/Launcher.qml
        qml/QuickSettings.qml
        qml/Tray.qml
        qml/TrayMenu.qml
        qml/CalendarPanel.qml
        qml/WeatherWidget.qml
        qml/RemovableMedia.qml
        qml/MediaSpectrum.qml
        qml/Wallpaper.qml
        qml/PowerMenu.qml
        qml/Welcome.qml
        qml/Capture.qml
        qml/Tiles.qml
        qml/DesktopMenu.qml
        qml/EditScene.qml
        qml/Recorder.qml
        qml/Workspaces.qml
        qml/ClipboardPanel.qml
        qml/ClipboardContent.qml
        qml/NotifCard.qml
        qml/NotificationCards.qml
        qml/NotificationCenter.qml
        qml/Settings.qml
        qml/Glass/GlassSlider.qml
        qml/Glass/GlassSwitch.qml
        qml/Glass/GlassMaterial.qml
        qml/Glass/GlowIcon.qml
        qml/Glass/Pills.qml
        qml/Glass/Spring.qml
        qml/Glass/LobeShape.qml
        qml/Glass/Spotlight.qml
        qml/Glass/IconHaze.qml
        qml/WindowPreview.qml
        qml/Switcher.qml
        qml/UserWidget.qml
        qml/SnapZones.qml
        qml/CheatSheet.qml
        qml/SysMon.qml
    # quick settings pages: plain files (they rely on the wrapper's `root` id, so they are not compiled ahead of time)
    RESOURCES
        qml/icons/palette-symbolic.svg
        scripts/kwin-snap-zones.js
        qml/data/emoji.json
        qml/control/Battery.qml
        qml/control/ControlPanel.qml
        qml/control/FullRepresentation.qml
        qml/control/NightLight.qml
        qml/control/UserInfo.qml
        qml/control/components/ConnectionItem.qml
        qml/control/components/Network.qml
        qml/control/components/SectionNetworks.qml
        qml/control/js/funcs.js
        qml/control/lib/Bubble.qml
        qml/control/lib/Card.qml
        qml/control/lib/DeviceRow.qml
        qml/control/lib/IconButton.qml
        qml/control/lib/LongButton.qml
        qml/control/lib/PillSlider.qml
        qml/control/lib/RowItem.qml
        qml/control/lib/Tile.qml
)
target_include_directories(sirca-shell PRIVATE src)
target_link_libraries(sirca-shell PRIVATE Qt6::Network Qt6::Concurrent Qt6::Quick Qt6::QuickControls2 Qt6::DBus Qt6::Widgets LayerShellQt::Interface KF6::WindowSystem KF6::GlobalAccel KF6::Package KF6::ConfigCore KF6::I18n Plasma::Plasma Plasma::PlasmaQuick Plasma::KWaylandClient KF6::Service KF6::GuiAddons)
if(PipeWire_FOUND)
    target_link_libraries(sirca-shell PRIVATE PkgConfig::PipeWire)
    target_compile_definitions(sirca-shell PRIVATE HAVE_PIPEWIRE)
endif()
install(TARGETS sirca-shell DESTINATION ${KDE_INSTALL_BINDIR})
# glass-palette IMAGE: the accent a wallpaper asks for, from the shell's own code (checks it against glass-desktop/tools/palette.py)
qt_add_executable(glass-palette src/palette-main.cpp src/palette.cpp src/palette.h)
target_include_directories(glass-palette PRIVATE src)
target_link_libraries(glass-palette PRIVATE Qt6::Gui Qt6::Qml Qt6::Concurrent)
install(TARGETS glass-palette DESTINATION ${KDE_INSTALL_BINDIR})
# KWin matches the desktop file by its Exec path, so it has to carry the path the binary is really installed to
set(SIRCA_SHELL_BINDIR "${CMAKE_INSTALL_PREFIX}/${KDE_INSTALL_BINDIR}")
if(IS_ABSOLUTE "${KDE_INSTALL_BINDIR}")
    set(SIRCA_SHELL_BINDIR "${KDE_INSTALL_BINDIR}")
endif()
set(SIRCA_SHELL_BIN "${SIRCA_SHELL_BINDIR}/sirca-shell")
configure_file(data/sirca-shell.desktop.in sirca-shell.desktop @ONLY)
configure_file(data/sirca-shell.service.in sirca-shell.service @ONLY)
configure_file(data/sirca-shell-fallback.service.in sirca-shell-fallback.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/sirca-shell.desktop scripts/sirca-settings.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/sirca-shell.service ${CMAKE_CURRENT_BINARY_DIR}/sirca-shell-fallback.service DESTINATION ${KDE_INSTALL_SYSTEMDUSERUNITDIR})
install(PROGRAMS scripts/sirca-shell-switch scripts/sirca-shell-reload scripts/sirca-shell-setup DESTINATION ${KDE_INSTALL_BINDIR})
install(PROGRAMS scripts/demo-notifications.sh DESTINATION ${KDE_INSTALL_BINDIR} RENAME sirca-demo-notifications)
install(FILES data/Osd.silent.qml DESTINATION ${KDE_INSTALL_DATADIR}/sirca-shell)
