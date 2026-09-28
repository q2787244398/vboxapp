// TVS Windows 主入口（Flutter desktop runner）。
//
// 官方尚未发布 Windows 版；本文件为按 TVS 架构重建的 Windows 壳：
//   - 标准 Flutter Windows runner（Win32 + FlutterEngine）
//   - NodeProcessBridge：spawn 系统/随包的 node.exe 作为子进程，按
//     node-main-template.js 协议注入 PORT / DART_PORT / BUNDLE_PATH /
//     NODE_PATH / TVS_PARENT_PID，轮询 .startup.ack 确认 spider 就绪
//   - yl_player Windows 后端（Pigeon 通道已注册，FFmpeg 解码渲染管线
//     留 TODO，见 packages/yl_player/windows/）

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <windows.h>

#include "flutter_window.h"
#include "node_process_bridge.h"
#include "yl_player_plugin.h"

int APIENTRY WinMain(_In_ HINSTANCE instance, _In_opt_ PWSTR pCmdLine,
                     _In_ int nCmdShow) {
  // Attach to engine and start the standard Flutter window.
  flutter::DartProject project(L"data");

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  if (!window.CreateAndShow(L"TVS", origin, flutter::Size(1280, 800))) {
    return EXIT_FAILURE;
  }

  // Node.js spider bridge: spawn node.exe as a child process.
  NodeProcessBridge nodeBridge(L"node", L"spider.js",
                               /*port=*/9775, /*dartPort=*/9776);
  nodeBridge.Start();

  // Register the Windows yl_player plugin (Pigeon channel).
  // Note: in a full build, the Flutter windows plugin registrar wires
  // this through Flutter::GetFlutter() on window create.
  auto* flutter_controller = window.controller();
  if (flutter_controller) {
    yl_player::RegisterWithRegistrar(
        flutter::PluginRegistrarWindows::GetCurrent());
  }

  const int result = window.Run();
  nodeBridge.Stop();

  ::CoUninitialize();
  return result;
}
