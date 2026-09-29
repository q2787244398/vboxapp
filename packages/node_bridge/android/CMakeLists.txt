# TVS node_bridge —— JNI 桥
#
# 结构与 nodejs-mobile 官方示例一致：
#   1. 编译 libnode_bridge.so（我们的 JNI 封装）
#   2. 以 IMPORTED 方式引入预编译的 libnode.so
#   3. 链接 log 库用于日志
#
# libnode 的目录布局（由 _scripts/fetch_node_runtime.sh 生成）：
#   libnode/include/node/…            C++ 头文件
#   libnode/bin/<abi>/libnode.so      三个 ABI 的预编译库

cmake_minimum_required(VERSION 3.13)
project(node_bridge CXX)

add_library(node_bridge SHARED src/main/cpp/node_bridge.cpp)

include_directories(libnode/include/node)

add_library(libnode SHARED IMPORTED)
set_target_properties(
        libnode
        PROPERTIES IMPORTED_LOCATION
        ${CMAKE_CURRENT_SOURCE_DIR}/libnode/bin/${ANDROID_ABI}/libnode.so)

find_library(log-lib log)

target_link_libraries(node_bridge libnode ${log-lib})
