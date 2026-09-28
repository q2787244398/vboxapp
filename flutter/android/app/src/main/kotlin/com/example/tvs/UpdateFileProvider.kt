package com.example.tvs

import androidx.core.content.FileProvider

/**
 * File provider for APK updates.
 * Provides secure file sharing for downloaded APKs.
 */
class UpdateFileProvider : FileProvider() {
    // FileProvider exposes the supported static getUriForFile(Context, ...)
    // API. No instance override is required here.
}