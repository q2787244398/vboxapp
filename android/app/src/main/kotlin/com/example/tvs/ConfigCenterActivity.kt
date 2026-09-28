package com.example.tvs

import android.os.Bundle
import android.view.KeyEvent
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Configuration center activity for managing spider sites, API keys,
 * cloud storage accounts, and player settings.
 */
class ConfigCenterActivity : FlutterActivity() {
    private val CHANNEL = "com.example.tvs/config_center"
    private var methodChannel: MethodChannel? = null

    companion object {
        private const val TAG = "TVS-ConfigCenter"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveConfig" -> {
                    val config = call.argument<Map<String, Any>>("config")
                    if (config != null) {
                        saveConfig(config)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARG", "config is required", null)
                    }
                }
                "loadConfig" -> {
                    result.success(loadConfig())
                }
                "resetConfig" -> {
                    resetConfig()
                    result.success(true)
                }
                "exportConfig" -> {
                    result.success(exportConfig())
                }
                "importConfig" -> {
                    val configJson = call.argument<String>("configJson")
                    if (configJson != null) {
                        result.success(importConfig(configJson))
                    } else {
                        result.error("INVALID_ARG", "configJson is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Handle DPAD key events for TV navigation.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        return when (event.keyCode) {
            KeyEvent.KEYCODE_BACK -> {
                // Let Flutter handle back navigation
                super.dispatchKeyEvent(event)
            }
            else -> super.dispatchKeyEvent(event)
        }
    }

    private fun saveConfig(config: Map<String, Any>) {
        val prefs = getSharedPreferences("tvs_config", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        config.forEach { (key, value) ->
            when (value) {
                is String -> editor.putString(key, value)
                is Int -> editor.putInt(key, value)
                is Boolean -> editor.putBoolean(key, value)
                is Double -> editor.putFloat(key, value.toDouble().toFloat())
            }
        }
        editor.apply()
    }

    private fun loadConfig(): Map<String, Any> {
        val prefs = getSharedPreferences("tvs_config", Context.MODE_PRIVATE)
        val config = mutableMapOf<String, Any>()
        prefs.all.forEach { (key, value) ->
            config[key] = value
        }
        return config
    }

    private fun resetConfig() {
        val prefs = getSharedPreferences("tvs_config", Context.MODE_PRIVATE)
        prefs.edit().clear().apply()
    }

    private fun exportConfig(): String {
        val config = loadConfig()
        return org.json.JSONObject(config).toString()
    }

    private fun importConfig(configJson: String): Boolean {
        return try {
            val jsonObject = org.json.JSONObject(configJson)
            val config = mutableMapOf<String, Any>()
            jsonObject.keys().forEach { key ->
                config[key] = jsonObject.get(key)
            }
            saveConfig(config)
            true
        } catch (e: Exception) {
            false
        }
    }
}