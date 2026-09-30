package com.vbox.player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import com.vbox.player.player.CodecCapability
import com.vbox.player.player.PlayerBackend
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 播放器平台通道（G-02-A：Media3 主后端）。
 *
 * 对齐契约 §2.5 播放器能力矩阵 + A21.5 回退策略：
 *  - MethodChannel `com.vbox.player/player`：open / play / pause / seekTo /
 *    setVolume / setSpeed / dispose
 *  - EventChannel `com.vbox.player/player/events`：state / progress / error
 *
 * 后端策略：`backend=media3` 走 ExoPlayer；A21.5 `selectBackend` 判为 libVLC 的
 * 媒体（MKV / HEVC 无硬解）本批返回 `E_BACKEND_UNAVAILABLE`（libVLC 依赖已接线，
 * 回退实现在 G-02-B/C 真机验收阶段交付）。
 */
class PlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var appContext: Context? = null
    private var channel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null

    private var exoPlayer: ExoPlayer? = null
    private var currentBackend: String? = null

    private val handler = Handler(Looper.getMainLooper())
    private val progressTick = object : Runnable {
        override fun run() {
            emitProgress()
            handler.postDelayed(this, 500L)
        }
    }

    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_IDLE -> emitState("idle")
                Player.STATE_BUFFERING -> emitState("buffering")
                Player.STATE_READY ->
                    emitState(if (exoPlayer?.playWhenReady == true) "playing" else "paused")
                Player.STATE_ENDED -> emitState("ended")
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            emitError(error.errorCodeName + ": " + error.message, fatal = true)
            emitState("error")
        }
    }

    // ─────────────── FlutterPlugin ───────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        val c = MethodChannel(binding.binaryMessenger, CHANNEL)
        c.setMethodCallHandler(this)
        channel = c
        val ec = EventChannel(binding.binaryMessenger, EVENTS_CHANNEL)
        ec.setStreamHandler(this)
        eventChannel = ec
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        teardown()
        channel?.setMethodCallHandler(null)
        channel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        appContext = null
    }

    // ─────────────── MethodChannel ───────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> open(call, result)
            "play" -> {
                exoPlayer?.play()
                result.success(null)
            }
            "pause" -> {
                exoPlayer?.pause()
                result.success(null)
            }
            "seekTo" -> {
                exoPlayer?.seekTo((call.arguments as Number).toLong())
                result.success(null)
            }
            "setVolume" -> {
                exoPlayer?.volume = (call.arguments as Number).toFloat()
                result.success(null)
            }
            "setSpeed" -> {
                exoPlayer?.setPlaybackSpeed((call.arguments as Number).toFloat())
                result.success(null)
            }
            "dispose" -> {
                teardown()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ─────────────── EventChannel ───────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    // ─────────────── open / 内部 ───────────────

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val url = args?.get("url")?.toString()
        if (url.isNullOrEmpty()) {
            result.error("E_PARAM", "open 缺少 url", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val headers = (args["headers"] as? Map<String, String>) ?: emptyMap()
        val backend = args?.get("backend")?.toString() ?: "media3"
        val isLive = args?.get("isLive") as? Boolean ?: false

        // A21.5：复杂封装 / HEVC 无硬解 → libVLC（依赖已接线，实现在 G-02-B/C）
        val needed = CodecCapability.selectBackend(url)
        if (needed == PlayerBackend.LIBVLC || backend != "media3") {
            result.error(
                "E_BACKEND_UNAVAILABLE",
                "该媒体需 libVLC 回退（$url），待 G-02-B/C 交付",
                null,
            )
            return
        }

        teardown()
        val context = appContext ?: run {
            result.error("E_STATE", "插件未附着引擎", null)
            return
        }
        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(headers)
        val p = ExoPlayer.Builder(context)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(context).setDataSourceFactory(dataSourceFactory)
            )
            .build()
        p.setMediaItem(MediaItem.fromUri(Uri.parse(url)))
        p.prepare()
        p.addListener(listener)
        if (isLive) {
            // 直播流：直接起播（无 duration 边界）
            p.play()
        }
        exoPlayer = p
        currentBackend = backend
        emitState("opening")
        handler.post(progressTick)
        result.success(null)
    }

    private fun teardown() {
        handler.removeCallbacks(progressTick)
        exoPlayer?.removeListener(listener)
        exoPlayer?.release()
        exoPlayer = null
        currentBackend = null
    }

    private fun emitState(value: String) {
        sink?.success(mapOf("type" to "state", "value" to value))
    }

    private fun emitProgress() {
        val p = exoPlayer ?: return
        val duration = p.duration
        sink?.success(
            mapOf(
                "type" to "progress",
                "positionMs" to p.currentPosition,
                "durationMs" to if (duration == C.TIME_UNSET) 0L else duration,
                "bufferedMs" to p.bufferedPosition,
                "isLive" to (duration == C.TIME_UNSET),
            ),
        )
    }

    private fun emitError(message: String, fatal: Boolean) {
        sink?.success(mapOf("type" to "error", "message" to message, "fatal" to fatal))
    }

    companion object {
        private const val CHANNEL = "com.vbox.player/player"
        private const val EVENTS_CHANNEL = "com.vbox.player/player/events"

        /** 供 [MainActivity.configureFlutterEngine] 手动注册（非插件工程无 registrant）。 */
        @JvmStatic
        fun registerWith(engine: FlutterEngine) {
            engine.plugins.add(PlayerPlugin())
        }
    }
}
