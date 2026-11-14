cmake_minimum_required(VERSION 3.25)
project(alice LANGUAGES C CXX OBJCXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(ALICE_LAUNCHER_ONLY "Build the distributable launcher without game-derived code" OFF)
option(ALICE_DEVELOPMENT_BUILD "Offer project-local data paths" ON)
set(ALICE_BUNDLE_IDENTIFIER "org.alice-recomp.macos")
if(ALICE_LAUNCHER_ONLY)
    set(ALICE_BUNDLE_IDENTIFIER "org.alice-recomp.macos.launcher")
endif()
if(ALICE_LAUNCHER_ONLY)
    find_package(rexglue REQUIRED CONFIG)
else()
    include(generated/rexglue.cmake)
endif()
# The SDK stages the MoltenVK ICD from the application scope.
set(REXGLUE_ROOT "${REXSDK_DIR}")
add_executable(alice MACOSX_BUNDLE
    src/macos_notifications.mm
    src/desktop_settings.mm
    src/macos_desktop.mm
    src/macos_localization.mm)
if(ALICE_LAUNCHER_ONLY)
    target_sources(alice PRIVATE src/launcher_main.cpp src/local_build.mm)
else()
    target_sources(alice PRIVATE src/main.cpp src/legacy_menu.cpp)
endif()
target_sources(alice PRIVATE macos/alice.icns)
foreach(language en ru)
    target_sources(alice PRIVATE "macos/${language}.lproj/InfoPlist.strings")
    set_source_files_properties("macos/${language}.lproj/InfoPlist.strings" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources/${language}.lproj")
endforeach()
target_sources(alice PRIVATE macos/en.lproj/Localizable.strings)
set_source_files_properties(macos/en.lproj/Localizable.strings PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources/en.lproj)
set_source_files_properties(macos/alice.icns PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
if(ALICE_LAUNCHER_ONLY)
    target_link_libraries(alice PRIVATE rex::runtime)
    rexglue_configure_target(alice GPU_PLUGINS xenos)
else()
    rexglue_setup_target(alice GPU_PLUGINS xenos)
    target_compile_options(alice_recomp PRIVATE -ffp-contract=off -fno-strict-aliasing)
    set_source_files_properties(generated/default/alice_register.cpp
        PROPERTIES COMPILE_OPTIONS "-O0" SKIP_PRECOMPILE_HEADERS ON)
endif()

set_target_properties(alice PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/macos/Info.plist.in"
    OUTPUT_NAME alice)

get_filename_component(ALICE_PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
target_compile_definitions(alice PRIVATE ALICE_PROJECT_ROOT="${ALICE_PROJECT_ROOT}")
target_compile_definitions(alice PRIVATE ALICE_DEVELOPMENT_BUILD=$<BOOL:${ALICE_DEVELOPMENT_BUILD}>)
if(ALICE_LAUNCHER_ONLY)
    target_compile_definitions(alice PRIVATE ALICE_LAUNCHER_ONLY=1)
endif()
# Restage the plugin whenever the runtime graphics implementation changes.
if(TARGET rexgpu-xenos)
    set_property(TARGET alice APPEND PROPERTY LINK_DEPENDS "$<TARGET_FILE:rexgpu-xenos>")
else()
    set_property(TARGET alice APPEND PROPERTY LINK_DEPENDS "$<TARGET_FILE:rex::gpu-xenos>")
endif()
# Resource-only edits must also run the post-link signing step, otherwise an
# incremental build leaves the bundle's resource seal stale.
set_property(TARGET alice APPEND PROPERTY LINK_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/macos/alice.icns"
    "${CMAKE_CURRENT_SOURCE_DIR}/macos/Info.plist.in"
    "${CMAKE_CURRENT_SOURCE_DIR}/macos/en.lproj/InfoPlist.strings"
    "${CMAKE_CURRENT_SOURCE_DIR}/macos/ru.lproj/InfoPlist.strings"
    "${CMAKE_CURRENT_SOURCE_DIR}/macos/en.lproj/Localizable.strings")

set_source_files_properties(src/macos_notifications.mm src/desktop_settings.mm src/macos_desktop.mm src/macos_localization.mm src/local_build.mm
    PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
target_link_libraries(alice PRIVATE "-framework UserNotifications" "-framework AppKit")
add_custom_command(TARGET alice POST_BUILD
    COMMAND "${CMAKE_COMMAND}" "-DAPP_BUNDLE=$<TARGET_BUNDLE_DIR:alice>"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/SignApp.cmake"
    VERBATIM)
