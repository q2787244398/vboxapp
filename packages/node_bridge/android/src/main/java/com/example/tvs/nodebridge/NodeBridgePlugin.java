package com.example.tvs.nodebridge;

import android.system.Os;
import android.util.Log;

import androidx.annotation.NonNull;

import java.io.File;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * TVS 的 Android 侧 Node 桥。
 *
 * 与 Dart 侧 {@code NodeService} 的契约（MethodChannel com.example.tvs/node_bridge）：
 * <pre>
 *   startNode {nodeDir: String} -> int   成功返回端口(>0)，失败返回 0
 *   isRunning                   -> bool
 *   getNodePort                 -> int
 *   getDartPort                 -> int
 *   stopNode                    -> bool
 * </pre>
 *
 * 分工：**JS 工程铺设与模板占位符替换全部由 Dart 侧完成**（见 node_project.dart），
 * 原生侧只做三件事：设环境变量、在后台线程调用 {@code node::Start}、轮询端口。
 * 这样 Android / iOS 两端逻辑一致，且避免重复实现一遍 assets 复制。
 */
public class NodeBridgePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {

    private static final String TAG = "TVS-NodeBridge";
    private static final String CHANNEL = "com.example.tvs/node_bridge";
    private static final int DEFAULT_PORT = 9775;
    private static final int DEFAULT_DART_PORT = 9776;
    private static final long STARTUP_TIMEOUT_MS = 180_000L;

    /** Node 在进程内只能跑一份，且 node::Start 无法安全重启。 */
    private static final AtomicBoolean STARTED = new AtomicBoolean(false);
    private static final AtomicBoolean READY = new AtomicBoolean(false);

    private int port = DEFAULT_PORT;
    private int dartPort = DEFAULT_DART_PORT;

    // 由 libnode_bridge.so（src/main/cpp/node_bridge.cpp）实现，会阻塞到 Node 退出
    private native int nativeStartNode(String[] arguments);

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        MethodChannel channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "startNode": {
                final String nodeDir = call.argument("nodeDir");
                if (nodeDir == null || nodeDir.isEmpty()) {
                    result.error("INVALID_ARG", "nodeDir is required", null);
                    return;
                }
                startNode(nodeDir, result);
                break;
            }
            case "isRunning":
                result.success(READY.get() && isPortOpen());
                break;
            case "getNodePort":
                result.success(port);
                break;
            case "getDartPort":
                result.success(dartPort);
                break;
            case "stopNode":
                // 进程内嵌的 Node 没有安全停机接口（node::Start 阻塞在事件循环里），
                // 官方 nodejs-mobile 亦同。如实返回 false 表示未停机。
                Log.w(TAG, "stopNode: in-process Node cannot be stopped; restart the app");
                result.success(false);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void startNode(final String nodeDir, final MethodChannel.Result result) {
        if (READY.get() && isPortOpen()) {
            result.success(port);
            return;
        }
        if (!STARTED.compareAndSet(false, true)) {
            result.success(0); // 已在启动中
            return;
        }

        final File entry = new File(nodeDir, "node-main-template.js");
        if (!entry.isFile()) {
            Log.e(TAG, "entry not found: " + entry.getAbsolutePath());
            STARTED.set(false);
            result.success(0);
            return;
        }

        // node_start 阻塞 → 后台线程
        new Thread(() -> {
            try {
                System.loadLibrary("node");
                System.loadLibrary("node_bridge");

                Os.setenv("PORT", String.valueOf(port), true);
                Os.setenv("DEV_HTTP_PORT", String.valueOf(port), true);
                Os.setenv("DART_PORT", String.valueOf(dartPort), true);
                Os.setenv("NODE_PATH", nodeDir, true);
                Os.setenv("TVS_PARENT_PID", String.valueOf(android.os.Process.myPid()), true);

                Log.i(TAG, "starting node: " + entry.getAbsolutePath());
                final int code = nativeStartNode(new String[]{"node", entry.getAbsolutePath()});
                Log.i(TAG, "node exited with code " + code);
                READY.set(false);
            } catch (Throwable t) {
                Log.e(TAG, "node start failed", t);
                READY.set(false);
            }
        }, "tvs-nodejs").start();

        // 等端口起来再回报，避免 Dart 侧拿到端口却立刻调 API 失败。
        // 注意：iOS 无 JIT，bundle 解析可能耗时数十秒，超时给得较宽。
        new Thread(() -> {
            final long deadline = System.currentTimeMillis() + STARTUP_TIMEOUT_MS;
            while (System.currentTimeMillis() < deadline) {
                if (isPortOpen()) {
                    READY.set(true);
                    Log.i(TAG, "node http server ready on " + port);
                    postResult(result, port);
                    return;
                }
                try {
                    Thread.sleep(300);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
            Log.e(TAG, "node did not open port " + port + " within timeout");
            STARTED.set(false);
            postResult(result, 0);
        }, "tvs-nodejs-wait").start();
    }

    private void postResult(final MethodChannel.Result result, final int value) {
        new android.os.Handler(android.os.Looper.getMainLooper())
                .post(() -> result.success(value));
    }

    private boolean isPortOpen() {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress("127.0.0.1", port), 200);
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
