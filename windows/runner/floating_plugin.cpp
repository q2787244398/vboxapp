//
//  floating_plugin.cpp
//  Runner
//
//  批次 D · D2 —— 实现见头文件注释。
//

#include "floating_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>

#include <gdiplus.h>
#include <windowsx.h>

#include <algorithm>
#include <cstring>

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "ole32.lib")

namespace vbox {

namespace {

constexpr char kChannelName[] = "com.vbox.player/floating";
constexpr char kEventsChannelName[] = "com.vbox.player/floating/events";

constexpr int kCloseBoxSize = 28;   // 关闭按钮命中区（对齐 iOS closeBtn 28×28）。
constexpr int kEdgeMargin = 8;      // 吸附边缘留白（对齐 iOS x = w/2+8）。
constexpr int kYMargin = 50;        // y 上/下留白（对齐 iOS minY/maxY ±50）。

}  // namespace

// ─────────────── 事件面 ───────────────

namespace {

class StreamHandler : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit StreamHandler(
      flutter::EventSink<flutter::EncodableValue>** sink_ptr)
      : sink_ptr_(sink_ptr) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(const flutter::EncodableValue*,
                   std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
                       &&sink) override {
    *sink_ptr_ = sink.get();
    sink_ = std::move(sink);
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue*) override {
    *sink_ptr_ = nullptr;
    sink_ = nullptr;
    return nullptr;
  }

 private:
  flutter::EventSink<flutter::EncodableValue>** sink_ptr_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
};

}  // namespace

void FloatingPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar, HWND owner) {
  auto plugin = std::make_unique<FloatingPlugin>(registrar, owner);
  auto* raw = plugin.get();
  raw->channel_->SetMethodCallHandler(
      [raw](const auto& call, auto result) {
        raw->HandleMethodCall(call, std::move(result));
      });
  raw->events_->SetStreamHandler(
      std::make_unique<StreamHandler>(&raw->sink_));
  registrar->AddPlugin(std::move(plugin));
}

FloatingPlugin::FloatingPlugin(flutter::PluginRegistrarWindows* registrar,
                               HWND owner)
    : registrar_(registrar),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      events_(std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), kEventsChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      owner_(owner) {
  Gdiplus::GdiplusStartupInput input;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &input, nullptr);
}

FloatingPlugin::~FloatingPlugin() {
  DestroyWindow();
  if (gdiplus_token_ != 0) {
    Gdiplus::GdiplusShutdown(gdiplus_token_);
    gdiplus_token_ = 0;
  }
}

// ─────────────── MethodChannel ───────────────

void FloatingPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "isAvailable") {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (call.method_name() == "show") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    double width = 200, height = 112;
    const uint8_t* png = nullptr;
    size_t size = 0;
    if (args != nullptr) {
      if (const auto* w = std::get_if<double>(&args->at(std::string("width")))) {
        width = *w;
      }
      if (const auto* h = std::get_if<double>(&args->at(std::string("height")))) {
        height = *h;
      }
      if (const auto* bytes =
              std::get_if<flutter::EncodableValue>(
                  &args->at(std::string("bytes")))) {
        if (const auto* vector = std::get_if<std::vector<uint8_t>>(bytes)) {
          png = vector->data();
          size = vector->size();
        }
      }
    }
    result->Success(
        flutter::EncodableValue(ShowWindow(png, size, width, height)));
    return;
  }
  if (call.method_name() == "update") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args != nullptr) {
      if (const auto* vector = std::get_if<std::vector<uint8_t>>(
              &args->at(std::string("bytes")))) {
        UpdateSnapshot(vector->data(), vector->size());
      }
    }
    result->Success(flutter::EncodableValue(nullptr));
    return;
  }
  if (call.method_name() == "hide") {
    HideWindow();
    result->Success(flutter::EncodableValue(nullptr));
    return;
  }
  if (call.method_name() == "dispose") {
    DestroyWindow();
    result->Success(flutter::EncodableValue(nullptr));
    return;
  }
  if (call.method_name() == "setMedia" ||
      call.method_name() == "updateProgress") {
    result->Success(flutter::EncodableValue(nullptr));
    return;
  }
  result->NotImplemented();
}

// ─────────────── 浮窗承载 ───────────────

bool FloatingPlugin::ShowWindow(const uint8_t* png, size_t size, double width,
                                double height) {
  // 尺寸钳制（对齐 iOS container 200×112 上限屏内）。
  const int w = std::max(1, static_cast<int>(width));
  const int h = std::max(1, static_cast<int>(height));

  if (hwnd_ == nullptr) {
    WNDCLASSW wc = {};
    HINSTANCE instance = GetModuleHandleW(nullptr);
    // 类已注册（二次 show）：直接复用。
    if (!GetClassInfoW(instance, L"VBoxFloatingWindow", &wc)) {
      wc.lpfnWndProc = WndProcStatic;
      wc.hInstance = instance;
      wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
      wc.hbrBackground = CreateSolidBrush(RGB(0, 0, 0));
      wc.lpszClassName = L"VBoxFloatingWindow";
      RegisterClassW(&wc);
    }
    hwnd_ = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW, L"VBoxFloatingWindow", L"",
        WS_POPUP, 0, 0, w, h, owner_, nullptr, instance, nullptr);
    if (hwnd_ == nullptr) return false;
    SetWindowLongPtrW(hwnd_, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(this));
  }

  width_ = w;
  height_ = h;
  if (png != nullptr && size > 0) UpdateSnapshot(png, size);

  // 初始位：屏幕右侧偏上（对齐 iOS (screenW-220, 80)）。
  RECT work = {};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  const int x = work.right - w - 20;
  const int y = work.top + 80;
  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, w, h,
               SWP_SHOWWINDOW | SWP_NOACTIVATE);
  return true;
}

void FloatingPlugin::UpdateSnapshot(const uint8_t* png, size_t size) {
  if (hwnd_ == nullptr || png == nullptr || size == 0) return;
  HGLOBAL global = GlobalAlloc(GMEM_MOVEABLE, size);
  if (global == nullptr) return;
  void* ptr = GlobalLock(global);
  memcpy(ptr, png, size);
  GlobalUnlock(global);
  IStream* stream = nullptr;
  if (SUCCEEDED(CreateStreamOnHGlobal(global, TRUE, &stream))) {
    std::unique_ptr<Gdiplus::Bitmap> bmp(
        Gdiplus::Bitmap::FromStream(stream));
    if (bmp != nullptr) {
      HBITMAP hbmp = nullptr;
      if (bmp->GetHBITMAP(Gdiplus::Color(0, 0, 0, 0), &hbmp) == Gdiplus::Ok) {
        if (bitmap_ != nullptr) DeleteObject(bitmap_);
        bitmap_ = hbmp;
        SendMessageW(hwnd_, STM_SETIMAGE, IMAGE_BITMAP,
                     reinterpret_cast<LPARAM>(bitmap_));
      }
      delete bmp.release();
    }
    stream->Release();  // 连同 HGLOBAL 释放（fRelease=TRUE）。
  } else {
    GlobalFree(global);
  }
}

void FloatingPlugin::HideWindow() {
  if (hwnd_ != nullptr) ShowWindow(hwnd_, SW_HIDE);
}

void FloatingPlugin::DestroyWindow() {
  if (hwnd_ != nullptr) {
    ::DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  if (bitmap_ != nullptr) {
    DeleteObject(bitmap_);
    bitmap_ = nullptr;
  }
}

// ─────────────── 手势（对齐 iOS tap/doubleTap/pan/close）───────────────

LRESULT CALLBACK FloatingPlugin::WndProcStatic(HWND hwnd, UINT message,
                                               WPARAM wparam, LPARAM lparam) {
  auto* self =
      reinterpret_cast<FloatingPlugin*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self != nullptr) {
    return self->WndProc(hwnd, message, wparam, lparam);
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT FloatingPlugin::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                LPARAM lparam) {
  switch (message) {
    case WM_NCHITTEST: {
      // 关闭按钮区域不交给系统拖动；其余区域 HTCAPTION 系统拖动
      // （对齐 iOS UIPanGestureRecognizer 自由拖动）。
      const POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(hwnd, &pt);
      if (pt.x >= width_ - kCloseBoxSize && pt.y <= kCloseBoxSize) {
        return HTCLIENT;
      }
      return HTCAPTION;
    }
    case WM_LBUTTONDOWN: {
      const POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (pt.x >= width_ - kCloseBoxSize && pt.y <= kCloseBoxSize) {
        Emit("close");
        return 0;
      }
      // 单击：延迟 250ms 无第二击才上报（对齐 iOS tap require(toFail: doubleTap)）。
      SetTimer(hwnd, 1, 250, nullptr);
      return 0;
    }
    case WM_LBUTTONDBLCLK:
      KillTimer(hwnd, 1);
      Emit("doubleTap");
      return 0;
    case WM_TIMER:
      if (wparam == 1) {
        KillTimer(hwnd, 1);
        Emit("tap");
      }
      return 0;
    case WM_EXITSIZEMOVE:
      // 系统拖动结束 → 吸附最近左右边缘（对齐 iOS handlePan ended）。
      SnapToEdge();
      return 0;
    case WM_DESTROY:
      return 0;
    default:
      return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

void FloatingPlugin::SnapToEdge() {
  if (hwnd_ == nullptr) return;
  RECT work = {};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  RECT rect = {};
  GetWindowRect(hwnd_, &rect);
  const int centerX = (rect.left + rect.right) / 2;
  const int screenCenter = (work.left + work.right) / 2;
  int x = (centerX < screenCenter)
              ? work.left + kEdgeMargin
              : work.right - width_ - kEdgeMargin;
  int y = rect.top;
  y = std::max(work.top + kYMargin, y);
  y = std::min(y, work.bottom - height_ - kYMargin);
  y = std::max(y, work.top + kYMargin);
  SetWindowPos(hwnd_, nullptr, x, y, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void FloatingPlugin::Emit(const char* type) {
  if (sink_ == nullptr) return;
  flutter::EncodableMap event;
  event[flutter::EncodableValue("type")] = flutter::EncodableValue(type);
  sink_->Success(flutter::EncodableValue(event));
}

}  // namespace vbox
