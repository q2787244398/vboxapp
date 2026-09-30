package com.vbox.player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // G-02-A：注册播放器平台通道（Media3 主后端 + 事件流）
        PlayerPlugin.registerWith(flutterEngine)
    }
}
