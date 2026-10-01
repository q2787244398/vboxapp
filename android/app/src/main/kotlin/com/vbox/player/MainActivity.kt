package com.vbox.player

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 批次 Q · Q-02：预加载 JSC 引擎模块（libvbox_jsc.so，DT_NEEDED→libjsc.so）。
        // 必须先于 Dart 侧 DynamicLibrary.open 触发（本回调先于 Dart 入口执行）。
        // 失败不 crash：Dart 侧 jsc_ffi 的 isAvailable=false，
        // 工厂按 D6 自动降级 QuickJS（降级可观测）。
        try {
            System.loadLibrary("vbox_jsc")
        } catch (e: UnsatisfiedLinkError) {
            Log.w("vbox", "libvbox_jsc 加载失败，JSC 将按 D6 降级 QuickJS: ${e.message}")
        }
        // G-02-A：注册播放器平台通道（Media3 主后端 + 事件流）
        PlayerPlugin.registerWith(flutterEngine)
        // G-02-C：注册系统信息平台通道（UiMode 三重判定）
        SystemPlugin.registerWith(flutterEngine)
    }
}
