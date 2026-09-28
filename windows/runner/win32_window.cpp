#include "win32_window.h"

#include <windows.h>

#include <flutter/flutter_view_controller.h>

namespace {
// The window class name.
const wchar_t kWindowClassName[] = L"TVSFlutterWindow";

// The window procedure.
LRESULT CALLBACK WindowProc(
    HWND const window, UINT const message, WPARAM const wparam,
    LPARAM const lparam) noexcept {
  Win32Window* self = nullptr;
  if (message == WM_NCCREATE) {
    const CREATESTRUCTW* cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = static_cast<Win32Window*>(cs->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(self));
  } else {
    self = reinterpret_cast<Win32Window*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
  }

  if (self) {
    return self->MessageHandler(window, message, wparam, lparam);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

}  // namespace

bool Win32Window::CreateAndShow(const std::wstring& title,
                                const Point& origin,
                                const flutter::Size& size) {
  // Register the window class.
  WNDCLASSEXW wcex{};
  wcex.cbSize = sizeof(wcex);
  wcex.lpfnWndProc = WindowProc;
  wcex.hInstance = GetModuleHandle(nullptr);
  wcex.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wcex.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  wcex.lpszClassName = kWindowClassName;
  wcex.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  RegisterClassExW(&wcex);

  // Create the window.
  window_ = CreateWindowExW(
      WS_EX_OVERLAPPED | WS_EX_NOREDIRECTION,
      kWindowClassName, title.c_str(),
      WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME,
      origin.x, origin.y, size.width, size.height,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window_) {
    return false;
  }

  ShowWindow(window_, SW_SHOW);
  UpdateWindow(window_);
  return true;
}

int Win32Window::Run() {
  MSG msg{};
  while (GetMessage(&msg, nullptr, 0, 0)) {
    TranslateMessage(&msg);
    DispatchMessage(&msg);
  }
  return static_cast<int>(msg.wParam);
}

void Win32Window::Destroy() {
  if (window_) {
    DestroyWindow(window_);
    window_ = nullptr;
  }
}