cmake_minimum_required(VERSION 3.13)
set(target_name "yl_player_plugin")

project(${target_name} LANGUAGES CXX)

add_library(${target_name} SHARED
  "yl_player_plugin.cpp"
)

target_compile_definitions(${target_name} PRIVATE
  YL_PLAYER_PLUGIN_DLL_EXPORT=__declspec(dllexport)
)

target_compile_features(${target_name} PUBLIC cxx_std_17)
target_compile_options(${target_name} PRIVATE /W4 /WX /GR-)

add_dependencies(${target_name} flutter_assemble)

find_package(FlutterSdk REQUIRED CONFIG)

target_link_libraries(${target_name} PRIVATE flutter_sdk/flutter
  flutter_sdk/flutter_plugin_android)

# In a full build, link the FFmpeg shared libraries here:
#   target_link_libraries(${target_name} PRIVATE ${FFMPEG_DIR}/libavcodec-*.dll ...)

# Ensure the plugin exports the plugin register function on Windows.
# The Flutter plugin registrar calls the C-ABI symbol below.
set_target_properties(${target_name} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_sources(${target_name} PRIVATE "yl_player_plugin.h")
