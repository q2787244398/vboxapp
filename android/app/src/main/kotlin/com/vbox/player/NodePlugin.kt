package com.vbox.player

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Node 常驻系统宿主通道（批次 I · ND-01 —— Android 侧 nodejs-mobile 接入）。
 *
 * ## 背景
 * Dart 侧 [NodeRuntimeManager] 负责「部署运行时文件 → 完整性校验 → 拉起宿主 →
 * HTTP 探活 → 30s 心跳 → 崩溃重启」全套编排；**Android 无 `node` 可执行文件**，
 * 故宿主改由 nodejs-mobile 把 Node 引擎随 APK 打包，经本插件在**进程内**启动
 * （与 `PythonPlugin` 的 Chaquopy 同级方案；桌面端则由 `ProcessNodeHost` 起子进程）。
 *
 * ## 协议（MethodChannel `com.vbox.node/host`）
 *  - `start`（`runtimeDir` / `mainScript` / `bundlePath` / `lxPluginsDir` /
 *    `lxAckPath` / `environment`）→ `null`
 *  - `stop` → `null`
 *  - `isRunning` → `bool`
 *
 * ## 引擎绑定（未接入时明确报错，不 crash）
 * Node 引擎（nodejs-mobile 的 `NodeJS` 类）**不在默认依赖内**——需按 `ND-01-native`
 * 步骤引入 AAR 与 `libnode.so`（四 ABI）后本插件才会真正拉起引擎；未接入时
 * 统一回 `E_NODE_UNAVAILABLE`，由 Dart 侧映射为 `node-failed` 降级（Node 站点暂不可用），
 * 不影响其余功能。引擎以**反射**方式绑定，故不引入编译期依赖、缺包也不影响构建。
 */
class NodePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    /** 已启动的引擎实例（nodejs-mobile 单实例；停止需重启进程，对齐 iOS 语义）。 */
    @Volatile
    private var engine: Any? = null

    // ─────────────── FlutterPlugin ───────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        val c = MethodChannel(binding.binaryMessenger, CHANNEL)
        c.setMethodCallHandler(this)
        channel = c
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        engine = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                try {
                    startEngine(
                        runtimeDir = call.argument<String>("runtimeDir").orEmpty(),
                        mainScript = call.argument<String>("mainScript").orEmpty(),
                        environment = call.argument<Map<String, String>>("environment")
                            ?: emptyMap()
                    )
                    result.success(null)
                } catch (t: Throwable) {
                    result.error("E_NODE_UNAVAILABLE", t.message ?: "Node 引擎启动失败", null)
                }
            }

            "stop" -> {
                engine = null
                result.success(null)
            }

            "isRunning" -> result.success(engine != null)

            else -> result.notImplemented()
        }
    }

    // ─────────────── 引擎启动 ───────────────

    /**
     * 在后台线程启动 nodejs-mobile 引擎（官方要求独立线程 + 大栈）。
     *
     * 环境变量矩阵由 Dart 侧组装（`PORT` / `HEALTH_PORT` / `BUNDLE_PATH` / `LX_*`），
     * 与 iOS `NodeRuntimeManager.launchNodeEngine` 的 `setenv` 1:1；Node 侧经
     * `process.env` 读取，故此处保持不解释、原样透传。
     */
    private fun startEngine(
        runtimeDir: String,
        mainScript: String,
        environment: Map<String, String>
    ) {
        val ctx = appContext ?: throw IllegalStateException("Node 插件未附着引擎")
        if (runtimeDir.isEmpty()) throw IllegalStateException("Node 运行时目录为空")
        val script = File(runtimeDir, "main.js")
        if (!script.exists()) {
            throw IllegalStateException("Node 入口脚本缺失：${script.absolutePath}")
        }
        for ((k, v) in environment) {
            setEnv(k, v)
        }

        val clazz = findEngineClass()
            ?: throw IllegalStateException(
                "Node 引擎未集成（缺 nodejs-mobile AAR + libnode.so 四 ABI）。" +
                    "请按 ND-01-native 步骤引入后重试；入口脚本：$mainScript"
            )

        val instance = clazz.getDeclaredConstructor().newInstance()
        val engineArgs = arrayOf(script.absolutePath)
        try {
            clazz.getMethod("start", Context::class.java, Array<String>::class.java)
                .invoke(instance, ctx, engineArgs)
        } catch (_: NoSuchMethodException) {
            clazz.getMethod("start", Array<String>::class.java).invoke(instance, engineArgs)
        }
        engine = instance
        Log.i(TAG, "Node 引擎已启动：$mainScript")
    }

    /** 反射查找 nodejs-mobile 引擎类（未集成返回 null）。 */
    private fun findEngineClass(): Class<*>? {
        for (name in ENGINE_CLASS_CANDIDATES) {
            try {
                return Class.forName(name)
            } catch (_: ClassNotFoundException) {
                // 继续尝试下一个候选
            }
        }
        return null
    }

    /** `setenv` 反射调用（Android 上 `System.getenv` 只读，Node 侧读 process.env）。 */
    private fun setEnv(key: String, value: String) {
        try {
            val method = Class.forName("android.system.Os")
                .getMethod("setenv", String::class.java, String::class.java, Boolean::class.javaPrimitiveType)
            method.invoke(null, key, value, true)
        } catch (t: Throwable) {
            Log.w(TAG, "环境变量注入失败（$key）：${t.message}")
        }
    }

    companion object {
        const val CHANNEL = "com.vbox.node/host"

        private const val TAG = "vbox"

        /** nodejs-mobile 引擎类候选（按版本差异依次尝试）。 */
        private val ENGINE_CLASS_CANDIDATES = listOf(
            "com.janeasystems.nodejsmobile.NodeJS",
            "com.janeasystems.nodejs.NodeJS"
        )

        /** 注册到引擎（MainActivity 调用，与 PlayerPlugin/GoProxyPlugin/PythonPlugin 同模式）。 */
        @JvmStatic
        fun registerWith(engine: FlutterEngine) {
            engine.plugins.add(NodePlugin())
        }
    }
}