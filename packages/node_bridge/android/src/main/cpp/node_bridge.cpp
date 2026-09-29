// TVS node_bridge —— JNI 实现
//
// 参照 nodejs-mobile 官方示例（android/native-gradle/app/src/main/cpp/native-lib.cpp）：
// 唯一实质性工作是把 Java 的 String[] 展开成 libuv 要求的「连续内存」argv，然后调用
// node::Start(argc, argv)。
//
// 重要：node::Start() 会一直阻塞到 Node 事件循环退出，因此 **必须** 在工作线程上调用。
// Java 侧 NodeBridgePlugin 负责开线程；这里不做线程管理。

#include <jni.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <android/log.h>

#include "node.h"

#define LOG_TAG "TVS-NodeBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// 把 String[] 展平成连续内存，供 libuv 使用。
// 返回 argc；argv 由调用方负责释放（每个元素由 strdup 分配）。
int BuildArgv(JNIEnv* env, jobjectArray arguments, char*** out_argv) {
    const jsize argc = env->GetArrayLength(arguments);
    auto** argv = static_cast<char**>(calloc(static_cast<size_t>(argc) + 1, sizeof(char*)));
    if (argv == nullptr) {
        return 0;
    }
    for (jsize i = 0; i < argc; ++i) {
        auto jstr = static_cast<jstring>(env->GetObjectArrayElement(arguments, i));
        if (jstr == nullptr) {
            argv[i] = strdup("");
            continue;
        }
        const char* utf = env->GetStringUTFChars(jstr, nullptr);
        argv[i] = strdup(utf != nullptr ? utf : "");
        if (utf != nullptr) {
            env->ReleaseStringUTFChars(jstr, utf);
        }
        env->DeleteLocalRef(jstr);
    }
    *out_argv = argv;
    return static_cast<int>(argc);
}

void FreeArgv(char** argv, int argc) {
    if (argv == nullptr) return;
    for (int i = 0; i < argc; ++i) {
        free(argv[i]);
    }
    free(argv);
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_example_tvs_nodebridge_NodeBridgePlugin_nativeStartNode(
        JNIEnv* env,
        jobject /* this */,
        jobjectArray arguments) {
    char** argv = nullptr;
    const int argc = BuildArgv(env, arguments, &argv);
    if (argc == 0 || argv == nullptr) {
        LOGE("nativeStartNode: failed to build argv");
        return -1;
    }

    LOGI("node::Start argc=%d argv[1]=%s", argc, argv[1] != nullptr ? argv[1] : "(null)");

    // 阻塞直到 Node 退出
    const int exit_code = node::Start(argc, argv);

    LOGI("node::Start returned %d", exit_code);
    FreeArgv(argv, argc);
    return static_cast<jint>(exit_code);
}
