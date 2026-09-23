# Glass Key: a second, small KWin effect (see glasskey.h). Built with the Glass effect; installed under its own name.
# One shader source (#version 140, a core profile is required anyway: textureSize) is written out under both names KWin
# looks for: 6.6 appends "_core" to the file name on a core-profile context (glshadermanager.cpp), 6.7 does not.
file(READ glasskey.glsl GLASSKEY_SHADER)
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/generated/glasskey.frag" "${GLASSKEY_SHADER}")
file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/generated/glasskey_core.frag" "${GLASSKEY_SHADER}")

set(glasskey_SOURCES glasskey.cpp main.cpp glasskey.qrc)
add_library(glasskey MODULE ${glasskey_SOURCES})
target_link_libraries(glasskey PRIVATE Qt6::Core Qt6::Gui KF6::ConfigCore KF6::ConfigGui KWin::kwin)
install(TARGETS glasskey DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins)
if(GLASS_KWIN_67)
    target_compile_definitions(glasskey PRIVATE GLASS_KWIN_67)
endif()
