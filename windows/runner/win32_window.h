#ifndef TVS_WIN32_WINDOW_H_
#define TVS_WIN32_WINDOW_H_

#include <memory>
#include <string>

#include <windows.h>

#include <flutter/flutter_view_controller.h>

namespace flutter {
class FlutterTextureRegistrar;
}

/// A Win32 window that hosts a Flutter view.
class Win32Window {
 public:
  struct Point {
    int x;
    int y;
  };

  Win32Window(const Win32Window&) = delete;
  Win32Window& operator=(const Win32Window&) = delete;

  Win32Window() {}
  virtual ~Win32Window() {}

  // Returns the current window's frame.
  Rect GetFrame() const {
    RECT rect = {0, 0, 0, 0};
    GetWindowRect(window_, &rect);
    return rect;
  }

  // Returns the window's client area.
  Rect GetClientArea() const {
    RECT rect = {0, 0, 0, 0};
    GetClientRect(window_, &rect);
    return rect;
  }

  // Returns the Flutter view controller.
  flutter::FlutterViewController* controller() const {
    return controller_.get();
  }

  // Creates the window and returns true on success.
  bool CreateAndShow(const std::wstring& title,
                    const Point& origin,
                    const flutter::Size& size);

  // Runs the window's message loop.
  int Run();

  // Destroys the window.
  void Destroy();

 protected:
  // Called by CreateAndShow when the window is created.
  virtual bool OnCreate() = 0;

  // Called when the window is being destroyed.
  virtual void OnDestroy() = 0;

  // Called when the window receives a message.
  virtual LRESULT MessageHandler(
      HWND window, UINT const message, WPARAM const wparam,
      LPARAM const lparam) noexcept = 0;

 private:
  // The window handle.
  HWND window_ = nullptr;

  // The Flutter view controller.
  std::unique_ptr<flutter::FlutterViewController> controller_;
};

#endif  // TVS_WIN32_WINDOW_H_