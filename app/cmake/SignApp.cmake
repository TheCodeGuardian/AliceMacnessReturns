if(NOT IS_DIRECTORY "${APP_BUNDLE}/Contents")
    message(FATAL_ERROR "Expected an application bundle: ${APP_BUNDLE}")
endif()
file(GLOB libraries "${APP_BUNDLE}/Contents/MacOS/*.dylib"
    "${APP_BUNDLE}/Contents/Resources/vulkan/lib/*.dylib")
foreach(library IN LISTS libraries)
    execute_process(COMMAND /usr/bin/codesign --force --sign - "${library}"
        COMMAND_ERROR_IS_FATAL ANY)
endforeach()
execute_process(COMMAND /usr/bin/codesign --force --sign - "${APP_BUNDLE}"
    COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND /usr/bin/codesign --verify --deep --strict "${APP_BUNDLE}"
    COMMAND_ERROR_IS_FATAL ANY)
