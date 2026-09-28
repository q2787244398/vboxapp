package dev.ylplayer.yl_player_android

import android.content.Context
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaFormat.KEY_MIME
import android.net.Uri
import android.view.Surface
import androidx.annotation.NonNull
import androidx.media3.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * yl_player Android implementation.
 *
 * Pigeon Host API: load/play/pause/stop/seekTo/seekToLiveEdge/setVolume/
 * setPlaybackSpeed/selectAudioTrack/attach/assess/dispose
 * Pigeon Flutter API callbacks: onState/onStateDelta/onFirstFrame/
 * onPlaybackFailed/onRetryScheduled/onEngineChanged
 */
class YlPlayerPlugin : FlutterPlugin {
    private lateinit var channel: MethodChannel

    companion object {
        private const val CHANNEL = "dev.flutter.pigeon.yl_player"
    }

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> result.success(false)
                "play" -> result.success(null)
                "pause" -> result.success(null)
                "stop" -> result.success(null)
                "seekTo" -> result.success(null)
                "seekToLiveEdge" -> result.success(null)
                "setVolume" -> result.success(null)
                "setPlaybackSpeed" -> result.success(null)
                "selectAudioTrack" -> result.success(null)
                "attach" -> result.success(null)
                "assess" -> result.success(mapOf("tracks" to emptyList<Map<String, Any>>()))
                "dispose" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
