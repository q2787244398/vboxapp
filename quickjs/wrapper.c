/*
 * vbox QuickJS FFI wrapper — 实现（G-03-B-1）。
 *
 * 纯 C（C99），无平台框架依赖：Android（NDK）/ Windows（MSVC/mingw）/
 * macOS（clang）三端可直接编译。编译产物为动态库 `libvbox_quickjs`，
 * Dart 侧经 `dart:ffi`（`lib/platform/runtime/quickjs_ffi.dart`）加载。
 *
 * 语义对齐 iOS `vbox/Libraries/QuickJSBridge.m`（去 Foundation 依赖版）：
 *   · createRuntime / createContext / freeRuntime / freeContext / eval / freeString
 *   · 上下文创建时注册 `console.log / console.error / print` no-op
 *     （对齐 iOS `QJSSpiderEngine.setupBridge()`，避免蜘蛛脚本 console 调用抛错）
 */
#include <stddef.h>
#include <string.h>

#include "quickjs.h"
#include "wrapper.h"

/* ── console / print no-op（对齐 iOS setupBridge）────────────────────────── */

static JSValue vq_console_noop(JSContext *ctx, JSValueConst this_val,
                               int argc, JSValueConst *argv) {
    return JS_UNDEFINED;
}

static void vq_register_console(JSContext *ctx) {
    JSValue global = JS_GetGlobalObject(ctx);
    JSValue console = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, console, "log",
                      JS_NewCFunction(ctx, vq_console_noop, "log", 1));
    JS_SetPropertyStr(ctx, console, "error",
                      JS_NewCFunction(ctx, vq_console_noop, "error", 1));
    JS_SetPropertyStr(ctx, global, "console", console);
    JS_SetPropertyStr(ctx, global, "print",
                      JS_NewCFunction(ctx, vq_console_noop, "print", 1));
    JS_FreeValue(ctx, global);
    /* console / print 已由 global 对象持有，不得再单独释放（避免 use-after-free） */
}

/* ── 运行时 / 上下文 ────────────────────────────────────────────────────── */

void *vq_create_runtime(void) {
    return JS_NewRuntime();
}

void *vq_create_context(void *rt) {
    JSContext *ctx = JS_NewContext((JSRuntime *)rt);
    if (ctx != NULL) {
        vq_register_console(ctx);
    }
    return ctx;
}

void vq_free_runtime(void *rt) {
    JSRuntime *runtime = (JSRuntime *)rt;
    if (runtime != NULL) {
        JS_RunGC(runtime);       /* 先手动 GC，清理所有悬空对象 */
        JS_FreeRuntime(runtime); /* 再安全释放 runtime */
    }
}

void vq_free_context(void *ctx) {
    if (ctx != NULL) {
        JS_FreeContext((JSContext *)ctx);
    }
}

/* ── 脚本执行 ───────────────────────────────────────────────────────────── */

const char *vq_eval(void *ctx, const char *script) {
    JSContext *js_ctx = (JSContext *)ctx;
    JSValue result = JS_Eval(js_ctx, script, strlen(script), "<vbox-eval>",
                             JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(result)) {
        JSValue exception = JS_GetException(js_ctx);
        const char *str = JS_ToCString(js_ctx, exception);
        JS_FreeValue(js_ctx, exception);
        JS_FreeValue(js_ctx, result);
        return str; /* 异常消息：Error / TypeError / ... 前缀 */
    }
    const char *str = JS_ToCString(js_ctx, result);
    JS_FreeValue(js_ctx, result);
    return str;
}

void vq_free_string(void *ctx, const char *str) {
    if (str != NULL) {
        JS_FreeCString((JSContext *)ctx, str);
    }
}
