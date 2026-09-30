/*
 * vbox QuickJS FFI wrapper — 头文件（G-03-B-1）。
 *
 * 对齐 iOS `vbox/Libraries/QuickJSBridge.h` 的语义，但为**纯 C 实现**（无
 * Foundation / 平台框架依赖），Android / Windows / macOS 三端可编译；
 * Dart 侧经 `dart:ffi` 加载 `libvbox_quickjs`（.so / .dll / .dylib）调用。
 *
 * 生命周期约定（与 iOS QJSSpiderEngine.deinit 相同）：
 *   1. 先 `vq_free_context` 释放 context（级联释放 global 及其属性）
 *   2. 再 `vq_free_runtime` 释放 runtime（内部先 JS_RunGC）
 * 顺序颠倒会导致 JS_FreeRuntime 断言失败。
 */
#ifndef VBOX_QUICKJS_WRAPPER_H
#define VBOX_QUICKJS_WRAPPER_H

#if defined(_WIN32)
#define VQ_EXPORT __declspec(dllexport)
#else
#define VQ_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* 创建 / 释放运行时与上下文（不透明指针，Dart 侧以 int 句柄持有地址）。 */
VQ_EXPORT void *vq_create_runtime(void);
VQ_EXPORT void *vq_create_context(void *rt);
VQ_EXPORT void vq_free_runtime(void *rt);
VQ_EXPORT void vq_free_context(void *ctx);

/*
 * 执行脚本（JS_EVAL_TYPE_GLOBAL）。
 * - 返回 `JS_ToCString` 的结果（如 JSON 字符串）；
 * - 异常时返回异常消息（Error / TypeError / ReferenceError / SyntaxError 前缀，
 *   与契约 §5 错误检测规则一致）；
 * - 返回值由本库持有，Dart 侧复制后必须调用 `vq_free_string` 释放。
 */
VQ_EXPORT const char *vq_eval(void *ctx, const char *script);
VQ_EXPORT void vq_free_string(void *ctx, const char *str);

#ifdef __cplusplus
}
#endif

#endif /* VBOX_QUICKJS_WRAPPER_H */
