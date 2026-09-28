#ifndef TVS_FLUTTER_WINDOW_H_
#define TVS_FLUTTER_WINDOW_H_

#include <memory>
#include <string>

#include <flutter/flutter_view_controller.h>

#include "win32_window.h"

/// A window that creates and manages a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  /// Creates a FlutterWindow showing a Flutter view.
  ///
  /// @param project A Dart project to run in this window.
  explicit FlutterWindow(flutter::DartProject project);

  virtual ~FlutterWindow();

  // Do not copy.
  FlutterWindow(const FlutterWindow&) = delete;
  FlutterWindow& operator=(const FlutterWindow&) = delete;

  // Returns the Flutter view controller.
  flutter::FlutterViewController* controller() const {
    return controller_.get();
  }

 protected:
  // Win32Window overrides.
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window,
                         UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The FlutterViewController instance responsible for creating the
  // Flutter view.
  std::unique_ptr<flutter::FlutterViewController> controller_;
};

#endif  // TVS_FLUTTER_WINDOW_H_
