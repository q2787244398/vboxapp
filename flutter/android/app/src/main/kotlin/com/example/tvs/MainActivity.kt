package com.example.tvs

import android.content.pm.PackageInfo
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * TVS 的 Android 入口 Activity。
 *
 * 注意：Node 引擎的 MethodChannel（com.example.tvs/node_bridge）**已移到
 * packages/node_bridge 插件** 里注册。这里绝不能再次注册同名 channel ——
 * configureFlutterEngine 在 super 调用之后执行，会把插件的 handler 覆盖掉，
 * 导致引擎永远起不来。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.example.tvs/app_info"
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersion" -> result.success("${appVersionName()} (${appVersionCode()})")
                "getPackageInfo" -> result.success(packageInfoMap())
                else -> result.notImplemented()
            }
        }
    }

    private fun appVersionName(): String = try {
        packageManager.getPackageInfo(packageName, 0).versionName ?: "1.0.0"
    } catch (e: Exception) {
        "1.0.0"
    }

    private fun appVersionCode(): Long = try {
        val info: PackageInfo = packageManager.getPackageInfo(packageName, 0)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    } catch (e: Exception) {
        0L
    }

    private fun packageInfoMap(): Map<String, Any> = try {
        val info: PackageInfo = packageManager.getPackageInfo(packageName, 0)
        mapOf(
            "packageName" to info.packageName,
            "versionName" to (info.versionName ?: "1.0.0"),
            "versionCode" to appVersionCode(),
            "firstInstallTime" to info.firstInstallTime,
            "lastUpdateTime" to info.lastUpdateTime
        )
    } catch (e: Exception) {
        mapOf(
            "packageName" to "com.example.tvs",
            "versionName" to "1.0.0",
            "versionCode" to 0L
        )
    }
}
