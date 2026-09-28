cmake_minimum_required(VERSION 3.13)

project(tvs LANGUAGES CXX)

# Flutter SDK path (set by `flutter build`).
set(FLUTTER_ROOT "$ENV{FLUTTER_ROOT}")
if(NOT FLUTTER_ROOT)
    message(FATAL_ERROR "Set FLUTTER_ROOT to the Flutter SDK directory")
endif()

# C++17 required for the Flutter Windows C++ API.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Flutter runner sources.
set(SOURCES
    main.cpp
    flutter_window.cpp
    win32_window.cpp
    node_process_bridge.cpp
    Runner.rc
)

add_executable(tvs WIN32 ${SOURCES})

# Flutter Windows SDK include / link.
include(${FLUTTER_ROOT}/build/windows/flutter_assemble.cmake)
flutter_assemble(tvs)

# TVS-specific: Node.js spider bridge + yl_player plugin.
target_link_libraries(tvs PRIVATE
    flutter_sdk/flutter
    flutter_sdk/flutter_plugin_windows
)

# Windows libs.
target_link_libraries(tvs PRIVATE
    kernel32
    user32
    gdi32
    shell32
    advapi32
    ws2_32
)

# Ensure the plugin dll is built and placed next to the exe.
set_target_properties(tvs PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)