#include "flutter_window.h"

#include <windows.h>

#include <flutter_windows_texture_registrar.h>

FlutterWindow::FlutterWindow(flutter::DartProject project)
    : project_(std::move(project)) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  Rect frame = GetFrame();
  controller_ =
      std::make_unique<flutter::FlutterViewController>(frame.right - frame.left,
                                                       frame.bottom - frame.top,
                                                       project_);
  RegisterPlugins(controller_);
  controller_->SetViewController();
  return true;
}

void FlutterWindow::OnDestroy() {
  if (controller_) {
    UnregisterPlugins(controller_);
    controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (controller_) {
    const LRESULT result =
        controller_->MessageHandler(window, message, wparam, lparam);
    if (result != 0) {
      return result;
    }
  }
  return Win32Window::MessageHandler(window, message, wparam, lparam);
}
