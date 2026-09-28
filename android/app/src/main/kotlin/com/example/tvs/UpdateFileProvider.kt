package com.example.tvs

import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * File provider for APK updates.
 * Provides secure file sharing for downloaded APKs.
 */
class UpdateFileProvider : FileProvider() {
    companion object {
        private const val TAG = "TVS-UpdateFileProvider"
        private const val AUTHORITY = "com.example.tvs.update.fileprovider"
        private const val SHARE_DIR = "updates"
    }

    override fun getUriForFile(file: File): Uri {
        Log.d(TAG, "Providing URI for: ${file.absolutePath}")
        return super.getUriForFile(file)
    }
}