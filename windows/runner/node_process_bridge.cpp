#include "node_process_bridge.h"

#include <chrono>
#include <filesystem>
#include <thread>

#include <flutter/plugin_registrar_windows.h>

NodeProcessBridge::NodeProcessBridge(
    const FlutterWindow& window,
    const std::wstring& nodePath,
    const std::wstring& bundlePath,
    int port,
    int dartPort)
    : window_(window),
      nodePath_(nodePath),
      bundlePath_(bundlePath),
      port_(port),
      dartPort_(dartPort) {}

NodeProcessBridge::~NodeProcessBridge() { Stop(); }

void NodeProcessBridge::Start() {
  if (running_) return;

  // 1. Locate the node binary (bundle-embedded first, then system PATH).
  const std::wstring nodeExe = nodePath_ + L".exe";
  const std::wstring nodePathResolved =
      std::filesystem::exists(nodeExe) ? nodeExe : L"node.exe";

  // 2. Command line: node <bundle>.
  const std::wstring cmdLine =
      L"\"" + nodePathResolved + L"\" \"" + bundlePath_ + L"\"";

  // 3. Set the five TVS bootstrap env vars in the current process so the
  //    child inherits them (node-main-template.js reads process.env).
  SetEnvironmentVariableW(
      L"PORT", std::to_wstring(port_).c_str());
  SetEnvironmentVariableW(
      L"DART_PORT", std::to_wstring(dartPort_).c_str());
  SetEnvironmentVariableW(
      L"BUNDLE_PATH", bundlePath_.c_str());
  SetEnvironmentVariableW(
      L"NODE_PATH", window_.ExeDirectoryW().c_str());
  SetEnvironmentVariableW(
      L"TVS_PARENT_PID",
      std::to_wstring(GetCurrentProcessId()).c_str());

  // 4. Spawn the child process.
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  const BOOL ok = CreateProcessW(
      nodePathResolved.c_str(),
      const_cast<LPWSTR>(cmdLine.c_str()),
      nullptr, nullptr, FALSE,
      0,                       // default env: inherits the vars above
      nullptr,
      const_cast<LPWSTR>(window_.ExeDirectoryW().c_str()),
      &si, &pi);

  if (!ok) {
    // The Dart NodeService surfaces the failure via its ack polling.
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return;
  }
  CloseHandle(pi.hThread);
  process_ = pi.hProcess;
  running_ = true;

  // 5. Poll for .startup.ack (the JS bootstrap writes it once the
  //    CatVod spider HTTP server is listening on kNodePort).
  const auto ack =
      std::filesystem::path(window_.ExeDirectoryW()) / ".startup.ack";
  const auto start = std::chrono::steady_clock::now();
  while (std::chrono::steady_clock::now() - start <
         std::chrono::seconds(45)) {
    if (std::filesystem::exists(ack)) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
  }
}

void NodeProcessBridge::Stop() {
  if (!running_) return;
  running_ = false;
  if (process_) {
    TerminateProcess(process_, 0);
    CloseHandle(process_);
    process_ = nullptr;
  }
  // Clear the TVS env vars.
  SetEnvironmentVariableW(L"PORT", nullptr);
  SetEnvironmentVariableW(L"DART_PORT", nullptr);
  SetEnvironmentVariableW(L"BUNDLE_PATH", nullptr);
  SetEnvironmentVariableW(L"NODE_PATH", nullptr);
  SetEnvironmentVariableW(L"TVS_PARENT_PID", nullptr);
}
