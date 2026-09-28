package com.example.tvs

import android.app.Application
import android.util.Log

/**
 * Application entry point for TVS.
 *
 * Node.js is deliberately started by [NodeBridge] on demand rather than in
 * Application.onCreate(), so app startup remains fast and the engine does
 * not consume resources when no spider request is active.
 */
class TVSApplication : Application() {
    companion object {
        private const val TAG = "TVS-Application"
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "TVS application initialized")
    }
}
