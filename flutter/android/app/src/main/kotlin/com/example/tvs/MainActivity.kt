package com.example.tvs

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageInfo
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.tvs/node_bridge"
    private var methodChannel: MethodChannel? = null

    companion object {
        private const val TAG = "TVS-MainActivity"
        var nodeBridge: NodeBridge? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nodeBridge = NodeBridge(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startNode" -> {
                    val bundlePath = call.argument<String>("bundlePath")
                    if (bundlePath != null) {
                        nodeBridge?.startNode(bundlePath) { port ->
                            result.success(port)
                        }
                    } else {
                        result.error("INVALID_ARG", "bundlePath is required", null)
                    }
                }
                "isRunning" -> {
                    result.success(nodeBridge?.isRunning() ?: false)
                }
                "stopNode" -> {
                    nodeBridge?.stopNode()
                    result.success(true)
                }
                "getVersion" -> {
                    result.success(getAppVersion())
                }
                "getPackageInfo" -> {
                    result.success(getPackageInfo())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getAppVersion(): String {
        return try {
            val packageInfo: PackageInfo = packageManager.getPackageInfo(packageName, 0)
            "${packageInfo.versionName} (${packageInfo.versionCode})"
        } catch (e: Exception) {
            "1.2.1 (4006)"
        }
    }

    private fun getPackageInfo(): Map<String, Any> {
        return try {
            val packageInfo: PackageInfo = packageManager.getPackageInfo(packageName, 0)
            mapOf(
                "packageName" to packageInfo.packageName,
                "versionName" to (packageInfo.versionName ?: "1.2.1"),
                "versionCode" to packageInfo.versionCode,
                "firstInstallTime" to packageInfo.firstInstallTime,
                "lastUpdateTime" to packageInfo.lastUpdateTime
            )
        } catch (e: Exception) {
            mapOf(
                "packageName" to "com.example.tvs",
                "versionName" to "1.2.1",
                "versionCode" to 4006
            )
        }
    }
}