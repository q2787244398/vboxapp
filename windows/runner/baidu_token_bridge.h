//  baidu_token_bridge.h
//  Runner
//
//  百度 bdstoken 原生 WebView2 桥（Windows 专属）。
//
//  背景：普通百度网盘播放链需要用户态 bdstoken，Dart HttpClient 的 TLS/请求
//  指纹被百度风控（gettemplatevariable errno=-6）。iOS 端经 WKWebView（系统
//  网络栈）天然可信；Windows 端 Flutter 插件 WebView 曾先后引入闪退（无头
//  模式）与白屏（根 Overlay 宿主），均已下线。本桥在 runner 原生层直接承载
//  WebView2：隐藏子窗口 + 持久化 Jar + disk/main 页面上下文内 fetch
//  gettemplatevariable——与登录网关同源的浏览器信任路径，不经 Flutter 插件
//  WebView，结构上不会复现白屏/闪退。
//
//  Dart 侧：lib/platform/webview/baidu_native_token_bridge.dart
//  通道：MethodChannel `com.vbox.player/cloud_bridge` · getBdstoken
//
//  线程模型：全部工作在平台线程（方法调用线程，STA + 消息泵）；WebView2
//  异步完成回调也投递回该线程，无需跨线程同步。
//  生命周期：Controller 常驻复用（首次调用创建，进程退出随插件析构关闭）；
//  取号成功后走快速路径（免导航直接页面 fetch），errno!=0 时种 Cookie 重导航一次。

#ifndef RUNNER_BAIDU_TOKEN_BRIDGE_H_
#define RUNNER_BAIDU_TOKEN_BRIDGE_H_

#include <functional>
#include <string>
#include <vector>

#include <windows.h>

#include <wrl/client.h>

#include <flutter/encodable_value.h>

#include "webview2/include/WebView2.h"

namespace vbox {

class BaiduTokenBridge {
 public:
  /// 结果回调（平台线程调用一次）：EncodableMap
  /// {errno:int, bdstoken:string, cookie:string, message:string}。
  using Reply = std::function<void(const flutter::EncodableValue&)>;

  explicit BaiduTokenBridge(HWND parent_window);
  ~BaiduTokenBridge();

  BaiduTokenBridge(const BaiduTokenBridge&) = delete;
  BaiduTokenBridge& operator=(const BaiduTokenBridge&) = delete;

  /// 异步取 bdstoken。[cookie_header] 为凭据原始 Cookie 串（"k=v; k2=v2"），
  /// 会种入 WebView2 Jar 后再导航 disk/main。失败同样回调（errno<0）。
  void GetBdstoken(const std::string& cookie_header, Reply reply);

  /// 释放 WebView2 资源（PlayerPlugin 析构时调用；幂等）。
  void Shutdown();

 private:
  enum class Phase {
    kIdle,
    kCreatingEnv,
    kCreatingCtl,
    kNavigating,
    kSettle,
    kExecuting,
  };

  // WM_TIMER id：1 = 阶段看门狗，2 = 导航完成后 Set-Cookie 沉降。
  static constexpr UINT_PTR kWatchdogTimer = 1;
  static constexpr UINT_PTR kSettleTimer = 2;

  void EnsureHostWindow();
  void StartChain();
  void EnterPhase(Phase phase, const char* label, UINT watchdog_ms);
  void NavigateMain();
  void SeedCookies();
  void RunScript();
  void OnEnvironmentCreated(HRESULT result, ICoreWebView2Environment* created);
  void OnControllerCreated(HRESULT result, ICoreWebView2Controller* created);
  void OnNavigationCompleted(bool succeeded);
  void OnWatchdog();
  void OnSettle();
  void OnScriptResult(const std::string& js_return_json);
  void FetchJarCookiesThenComplete(const std::string& token);
  void CompleteAll(int errno_code, const std::string& token,
                   const std::string& cookie, const std::string& message);
  void FailAll(const std::string& message);
  static LRESULT CALLBACK HostWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                      LPARAM lparam);

  HWND parent_window_ = nullptr;
  HWND host_window_ = nullptr;
  Phase phase_ = Phase::kIdle;
  const char* phase_label_ = "";

  // 并发请求队列：CompleteAll / FailAll 逐个回复后清空。
  std::vector<Reply> pending_;
  // 本次链路使用的凭据 Cookie（首个待答复请求的入参）。
  std::string cookie_header_;
  // errno!=0 重试标记：种 Cookie + 重导航仅补一次，防止死循环。
  bool seed_retry_done_ = false;
  // 上次取号是否成功（成功 → 下次走免导航快速路径）。
  bool last_fetch_ok_ = false;
  bool com_initialized_ = false;
  bool shutting_down_ = false;

  Microsoft::WRL::ComPtr<ICoreWebView2Environment> env_;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> webview_;
  // 事件注册 token（webview_ 生命周期内常驻，无需反注册）。
  EventRegistrationToken nav_token_{};
  EventRegistrationToken proc_token_{};
  EventRegistrationToken win_token_{};
};

}  // namespace vbox

#endif  // RUNNER_BAIDU_TOKEN_BRIDGE_H_
