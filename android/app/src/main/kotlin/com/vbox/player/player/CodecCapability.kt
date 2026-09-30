package com.vbox.player.player

import android.media.MediaCodecInfo
import android.media.MediaCodecList

/**
 * 编解码能力探测（方案 A21.5 落地）。
 *
 * `selectBackend(url)`：复杂封装（MKV 等）或 HEVC 无硬解 → libVLC 回退，
 * 否则走 Media3（ExoPlayer）。纯 JVM 实现，无 NDK / 平台绑定。
 */
object CodecCapability {

    fun supportsHevcHardware(): Boolean {
        val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        return list.codecInfos.any { info ->
            !info.isEncoder && info.supportedTypes.any { it.equals("video/hevc", true) }
        }
    }

    fun selectBackend(url: String): PlayerBackend {
        val ext = url.substringAfterLast('.', "").lowercase()
        return when {
            ext == "mkv" -> PlayerBackend.LIBVLC // MKV 保守走 VLC
            isHevc(url) && !supportsHevcHardware() -> PlayerBackend.LIBVLC // 无硬解
            else -> PlayerBackend.MEDIA3
        }
    }

    private fun isHevc(url: String) = url.contains("hevc", true) || url.contains("h265", true)
}

/** 播放器后端（Android 侧，与 Dart `PlayerBackend` 的 media3 / libVLC 对齐）。 */
enum class PlayerBackend { MEDIA3, LIBVLC }
