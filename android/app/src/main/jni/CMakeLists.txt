# 批次 Q · Q-02：Android JSC 集成（NDK 编译 jsc/wrapper.c → libvbox_jsc.so）。
#
# 结构：
#   libvbox_jsc.so ──DT_NEEDED──▶ libjsc.so（预编译，React Native 生态
#   `jsc-android` r250231 产物，由 scripts/fetch-jsc-android.sh 就位到
#   src/main/jniLibs/<abi>/，AGP 自动随 APK 打入 lib/<abi>/）
#
# 加载链（运行时）：MainActivity.onCreate → System.loadLibrary("vbox_jsc")
#   （linker 按 SONAME 自动解析同目录 libjsc.so）→ Dart FFI
#   `DynamicLibrary.open("libvbox_jsc.so")` 命中已加载实例。
# 加载失败（非四 ABI 设备等）不 crash：Dart 侧 isAvailable=false，
# 工厂按 D6 自动降级 QuickJS（降级可观测，见 spider_engine_factory.dart）。
#
# ABI 形状：与 quickjs/wrapper.c 的 vq_* 完全对齐（Q-05 三端同一 ABI）；
# 符号可见性 hidden + wrapper.h 的 VJ_EXPORT（default）→ 仅导出 vj_*。
cmake_minimum_required(VERSION 3.22)
project(vbox_jsc LANGUAGES C)

set(CMAKE_C_STANDARD 99)

# 项目根（android/app/src/main/jni 上溯 5 层）
get_filename_component(VBOX_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)

# JSC 预编译库（IMPORTED，按当前 ABI 分派）
set(JSC_PREBUILT "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libjsc.so")
if(NOT EXISTS "${JSC_PREBUILT}")
    message(FATAL_ERROR
        "libjsc.so(${ANDROID_ABI}) 缺失：请先运行 scripts/fetch-jsc-android.sh"
        "（原生二进制不入 git，见同脚本头注释）")
endif()

add_library(jsc SHARED IMPORTED)
set_target_properties(jsc PROPERTIES IMPORTED_LOCATION "${JSC_PREBUILT}")

add_library(vbox_jsc SHARED "${VBOX_ROOT}/jsc/wrapper.c")

target_include_directories(vbox_jsc PRIVATE "${VBOX_ROOT}/jsc/include")

set_target_properties(vbox_jsc PROPERTIES
    C_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN TRUE)

target_link_libraries(vbox_jsc PRIVATE jsc)
