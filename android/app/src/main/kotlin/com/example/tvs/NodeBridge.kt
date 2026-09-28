package com.example.tvs

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Native bridge to manage the embedded Node.js engine.
 * Starts Node.js as a child process, communicates via HTTP API.
 */
class NodeBridge(private val context: Context) {
    companion object {
        private const val TAG = "TVS-NodeBridge"
        private const val DEFAULT_PORT = 9775
        private const val DART_PORT = 9776
        private const val STARTUP_TIMEOUT_MS = 45000L
    }

    private var nodePid: Int = 0
    private var nodePort: Int = DEFAULT_PORT
    private var dartPort: Int = DART_PORT
    private var isRunning = AtomicBoolean(false)
    private var nodeProcess: Process? = null
    private var nodeDir: File? = null

    /**
     * Start the Node.js engine with the given bundle path.
     * Returns the HTTP port on success.
     */
    fun startNode(bundlePath: String, onReady: (Int) -> Unit) {
        if (isRunning.get()) {
            onReady(nodePort)
            return
        }

        nodeDir = File(context.filesDir, "node")
        if (!nodeDir!!.exists()) {
            nodeDir!!.mkdirs()
        }

        // Copy Node.js binary and assets to files dir
        val nodeBinary = File(nodeDir, "node")
        val bundleFile = File(bundlePath)

        try {
            // Extract native library if needed
            extractNodeBinary(nodeBinary)

            // Set up environment
            val env = mapOf(
                "PORT" to nodePort.toString(),
                "DART_PORT" to dartPort.toString(),
                "BUNDLE_PATH" to bundlePath,
                "NODE_PATH" to nodeDir!!.absolutePath,
                "TVS_PARENT_PID" to android.os.Process.myPid().toString()
            )

            // Start Node.js process
            val processBuilder = ProcessBuilder()
                .command(nodeBinary.absolutePath, bundlePath)
                .directory(nodeDir)
                .redirectErrorStream(true)

            // Set environment variables
            env.forEach { (key, value) ->
                processBuilder.environment()[key] = value
            }

            nodeProcess = processBuilder.start()
            nodePid = try {
                // Try to get PID (Android-specific)
                val pidField = nodeProcess.javaClass.getDeclaredField("pid")
                pidField.isAccessible = true
                pidField.getInt(nodeProcess)
            } catch (e: Exception) {
                -1
            }

            isRunning.set(true)

            // Wait for Node.js to be ready
            Thread {
                val startTime = System.currentTimeMillis()
                while (System.currentTimeMillis() - startTime < STARTUP_TIMEOUT_MS) {
                    if (isPortOpen("127.0.0.1", nodePort, 100)) {
                        Log.i(TAG, "Node.js server ready at port $nodePort")
                        onReady(nodePort)
                        return@Thread
                    }
                    Thread.sleep(500)
                }
                Log.e(TAG, "Node.js server did not start within ${STARTUP_TIMEOUT_MS}ms")
                stopNode()
            }.start()

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start Node.js: ${e.message}", e)
            stopNode()
        }
    }

    /**
     * Check if Node.js is running.
     */
    fun isRunning(): Boolean {
        if (!isRunning.get()) return false
        // Check if process is still alive
        nodeProcess?.let { proc ->
            try {
                proc.exitValue()
                // Process exited
                isRunning.set(false)
                return false
            } catch (e: IllegalThreadStateException) {
                // Still running
                return true
            }
        }
        return false
    }

    /**
     * Stop the Node.js process.
     */
    fun stopNode() {
        isRunning.set(false)
        nodeProcess?.let { proc ->
            try {
                if (Build.VERSION_CODES.O <= Build.VERSION_CODES.S) {
                    proc.destroyForced()
                } else {
                    proc.destroy()
                }
                proc.waitFor()
            } catch (e: Exception) {
                Log.w(TAG, "Error stopping Node.js: ${e.message}")
            }
        }
        nodeProcess = null
        nodePid = 0
    }

    /**
     * Extract the Node.js binary from APK assets.
     */
    private fun extractNodeBinary(target: File) {
        if (target.exists()) return
        try {
            context.assets.open("node").use { input ->
                target.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            target.setExecutable(true, false)
        } catch (e: Exception) {
            Log.w(TAG, "Could not extract node binary from assets: ${e.message}")
            // Try to use system node if available
        }
    }

    /**
     * Check if a port is open on localhost.
     */
    private fun isPortOpen(host: String, port: Int, timeout: Int): Boolean {
        return try {
            ServerSocket().use { socket ->
                socket.soTimeout = timeout
                socket.connect(java.net.InetSocketAddress(host, port), timeout)
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Restart Node.js with a new bundle path.
     */
    fun restart(bundlePath: String, onReady: (Int) -> Unit) {
        stopNode()
        startNode(bundlePath, onReady)
    }

    /**
     * Get the current Node.js port.
     */
    fun getNodePort(): Int = nodePort

    /**
     * Get the Dart communication port.
     */
    fun getDartPort(): Int = dartPort

    /**
     * Set the Dart port (used for relisten).
     */
    fun setDartPort(port: Int) {
        dartPort = port
    }
}