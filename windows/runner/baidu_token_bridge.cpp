//  baidu_token_bridge.cpp
//  Runner
//
//  实现（设计见 baidu_token_bridge.h）。
//
//  取号链路（状态机，全在平台线程）：
//    GetBdstoken → [快速路径] webview 就绪且上次成功 → RunScript
//                → [完整链路] 隐藏窗口/环境/Controller → 种凭据 Cookie
//                  → 导航 disk/main → 沉降 800ms → 页面 fetch gettemplatevariable
//                  → 解析 → Jar Cookie 全量回传
//  失败语义：所有阶段有看门狗；errno!=0 时「种 Cookie + 重导航」仅补一次，
//  之后如实回传 errno 交 Dart 兜底链继续（保存值/重扫码提示）。

#include "baidu_token_bridge.h"

#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wrl/event.h>

#include <algorithm>
#include <utility>

namespace vbox {
namespace {

// ─────────────── 宽窄转换 ───────────────

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                                         static_cast<int>(text.size()),
                                         nullptr, 0);
  std::wstring out(static_cast<size_t>(std::max(size, 0)), L'\0');
  if (size > 0) {
    ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                          out.data(), size);
  }
  return out;
}

std::string WideToUtf8(const wchar_t* text) {
  if (text == nullptr || *text == L'\0') return std::string();
  const int bytes = ::WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0,
                                          nullptr, nullptr);
  if (bytes <= 1) return std::string();
  std::string out(static_cast<size_t>(bytes) - 1, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), bytes, nullptr,
                        nullptr);
  return out;
}

// ─────────────── 极简 JSON 工具（仅处理固定形状的响应） ───────────────

// 解码 ExecuteScript 返回的 JSON 字符串字面量（外层）→ 原始 JS 字符串。
std::string DecodeJsonStringLiteral(const std::string& encoded) {
  const size_t begin = encoded.find('"');
  if (begin == std::string::npos) return encoded;
  std::string out;
  out.reserve(encoded.size());
  for (size_t i = begin + 1; i < encoded.size(); ++i) {
    const char c = encoded[i];
    if (c == '"') break;
    if (c != '\\') {
      out.push_back(c);
      continue;
    }
    if (++i >= encoded.size()) break;
    switch (encoded[i]) {
      case '"': out.push_back('"'); break;
      case '\\': out.push_back('\\'); break;
      case '/': out.push_back('/'); break;
      case 'n': out.push_back('\n'); break;
      case 't': out.push_back('\t'); break;
      case 'r': out.push_back('\r'); break;
      case 'b': out.push_back('\b'); break;
      case 'f': out.push_back('\f'); break;
      case 'u': {
        // 响应字段均为 ASCII（bdstoken 为 32 位十六进制 / errno 数字），
        // 非 BMP 转义直接跳过 4 位十六进制（保底不崩）。
        i += std::min<size_t>(4, encoded.size() - i - 1);
        out.push_back('?');
        break;
      }
      default: out.push_back(encoded[i]); break;
    }
  }
  return out;
}

// 取 "key":"value"（仅 ASCII 值场景：bdstoken / pageToken）。
std::string FindJsonStringValue(const std::string& json, const char* key) {
  std::string needle = std::string("\"") + key + "\":";
  size_t pos = json.find(needle);
  if (pos == std::string::npos) {
    needle = std::string("\"") + key + "\" :";
    pos = json.find(needle);
  }
  if (pos == std::string::npos) return std::string();
  pos += needle.size();
  while (pos < json.size() && json[pos] == ' ') ++pos;
  if (pos >= json.size() || json[pos] != '"') return std::string();
  const std::string raw = DecodeJsonStringLiteral(json.substr(pos));
  return raw;
}

int FindJsonIntValue(const std::string& json, const char* key, int fallback) {
  std::string needle = std::string("\"") + key + "\":";
  size_t pos = json.find(needle);
  if (pos == std::string::npos) {
    needle = std::string("\"") + key + "\" :";
    pos = json.find(needle);
  }
  if (pos == std::string::npos) return fallback;
  pos += needle.size();
  const size_t digits_begin = json.find_first_of("-0123456789", pos);
  if (digits_begin == std::string::npos) return fallback;
  try {
    return std::stoi(json.substr(digits_begin));
  } catch (...) {
    return fallback;
  }
}

// 解析凭据 Cookie 头（"k=v; k2=v2"）→ 名值对（k/v 为 UTF-8）。
std::vector<std::pair<std::string, std::string>> ParseCookieHeader(
    const std::string& header) {
  std::vector<std::pair<std::string, std::string>> pairs;
  size_t pos = 0;
  while (pos < header.size()) {
    const size_t semi = header.find(';', pos);
    const std::string piece = header.substr(
        pos, semi == std::string::npos ? std::string::npos : semi - pos);
    pos = semi == std::string::npos ? header.size() : semi + 1;
    const size_t eq = piece.find('=');
    if (eq == std::string::npos || eq == 0) continue;
    std::string name = piece.substr(0, eq);
    std::string value = piece.substr(eq + 1);
    const auto trim = [](std::string& s) {
      const auto not_space = [](unsigned char ch) { return ch > ' '; };
      s.erase(s.begin(), std::find_if(s.begin(), s.end(), not_space));
      s.erase(std::find_if(s.rbegin(), s.rend(), not_space).base(), s.end());
    };
    trim(name);
    trim(value);
    if (!name.empty()) pairs.emplace_back(std::move(name), std::move(value));
  }
  return pairs;
}

// 递归建目录（存在即成功）。
void EnsureDirectory(const std::wstring& dir) {
  std::wstring built;
  for (size_t i = 0; i < dir.size(); ++i) {
    built.push_back(dir[i]);
    if (dir[i] == L'\\' && built.size() > 3) {
      ::CreateDirectoryW(built.c_str(), nullptr);
    }
  }
  ::CreateDirectoryW(dir.c_str(), nullptr);
}

std::wstring WebView2UserDataDir() {
  PWSTR roaming = nullptr;
  std::wstring dir;
  if (SUCCEEDED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr,
                                       &roaming)) &&
      roaming != nullptr) {
    dir = std::wstring(roaming) + L"\\com.vbox\\vbox\\win_baidu_webview";
    ::CoTaskMemFree(roaming);
  }
  if (!dir.empty()) EnsureDirectory(dir);
  return dir;
}

// 页面上下文取号脚本：disk/main 同源 fetch（credentials 自动携带 Jar 全量
// Cookie，含服务端现场补种的指纹字段），返回 JSON 字符串交原生解析。
constexpr const char* kBdstokenJs = R"js((async function(){
  try {
    var r = await fetch('https://pan.baidu.com/api/gettemplatevariable?app_id=250528&clienttype=0&web=1&fields=%5B%22bdstoken%22%5D', {credentials:'include'});
    var t = await r.text();
    var pageToken = '';
    try { if (window.locals && window.locals.get) pageToken = window.locals.get('bdstoken') || ''; } catch (e) {}
    try { if (!pageToken && window.yunData && window.yunData.MYBDSTOKEN) pageToken = window.yunData.MYBDSTOKEN; } catch (e) {}
    var docCookie = '';
    try { docCookie = document.cookie || ''; } catch (e) {}
    return JSON.stringify({httpOk: r.ok, status: r.status, body: t, pageToken: pageToken, docCookie: docCookie});
  } catch (e) {
    return JSON.stringify({httpOk: false, err: String(e)});
  }
})())js";

std::string Excerpt(const std::string& text, size_t keep) {
  if (text.size() <= keep) return text;
  return text.substr(0, keep) + "…";
}

// 构造通道结果 EncodableValue（GetBdstoken 前置声明使用，置于匿名命名空间）。
flutter::EncodableValue BuildResult(int errno_code, const std::string& token,
                                    const std::string& cookie,
                                    const std::string& message) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("errno")] = flutter::EncodableValue(errno_code);
  map[flutter::EncodableValue("bdstoken")] = flutter::EncodableValue(token);
  map[flutter::EncodableValue("cookie")] = flutter::EncodableValue(cookie);
  map[flutter::EncodableValue("message")] = flutter::EncodableValue(message);
  return flutter::EncodableValue(std::move(map));
}

}  // namespace

// ─────────────── 生命周期 ───────────────

BaiduTokenBridge::BaiduTokenBridge(HWND parent_window)
    : parent_window_(parent_window) {}

BaiduTokenBridge::~BaiduTokenBridge() { Shutdown(); }

void BaiduTokenBridge::Shutdown() {
  shutting_down_ = true;
  if (host_window_ != nullptr) {
    ::KillTimer(host_window_, kWatchdogTimer);
    ::KillTimer(host_window_, kSettleTimer);
  }
  if (controller_ != nullptr) {
    controller_->Close();
  }
  webview_.Reset();
  controller_.Reset();
  env_.Reset();
  if (host_window_ != nullptr) {
    ::SetWindowLongPtrW(host_window_, GWLP_USERDATA, 0);
    ::DestroyWindow(host_window_);
    host_window_ = nullptr;
  }
  FailAll("桥已关闭");
}

void BaiduTokenBridge::EnsureHostWindow() {
  if (host_window_ != nullptr) return;

  static const wchar_t* kClass = L"VboxWebView2Host";
  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = HostWndProc;
    wc.hInstance = ::GetModuleHandleW(nullptr);
    wc.lpszClassName = kClass;
    if (::RegisterClassExW(&wc) == 0 && ::GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return;
    }
    class_registered = true;
  }
  // 隐藏的 owned 弹出窗口：不显示、不抢焦点、随主窗口销毁；仅承载 WebView2
  // Controller 与 WM_TIMER（看门狗 / 沉降）。
  host_window_ = ::CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kClass, L"vbox-webview2-host",
      WS_POPUP, 0, 0, 160, 120, parent_window_, nullptr,
      ::GetModuleHandleW(nullptr), nullptr);
  if (host_window_ != nullptr) {
    ::SetWindowLongPtrW(host_window_, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(this));
  }
}

LRESULT CALLBACK BaiduTokenBridge::HostWndProc(HWND hwnd, UINT msg,
                                               WPARAM wparam, LPARAM lparam) {
  if (msg == WM_TIMER) {
    auto* bridge = reinterpret_cast<BaiduTokenBridge*>(
        ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (bridge != nullptr) {
      if (wparam == kWatchdogTimer) {
        bridge->OnWatchdog();
        return 0;
      }
      if (wparam == kSettleTimer) {
        bridge->OnSettle();
        return 0;
      }
    }
  }
  return ::DefWindowProcW(hwnd, msg, wparam, lparam);
}

// ─────────────── 取号入口 ───────────────

void BaiduTokenBridge::GetBdstoken(const std::string& cookie_header,
                                   Reply reply) {
  if (shutting_down_) {
    reply(BuildResult(-1, std::string(), std::string(), "桥已关闭"));
    return;
  }
  pending_.push_back(std::move(reply));
  if (phase_ != Phase::kIdle) {
    return;  // 已有链路在跑：结果出来后一并答复。
  }
  cookie_header_ = cookie_header;
  seed_retry_done_ = false;

  if (webview_ && last_fetch_ok_) {
    // 快速路径：页面会话已就绪（Jar/登录态都在），免导航直接 fetch。
    EnterPhase(Phase::kExecuting, "页面fetch", 15000);
    RunScript();
    return;
  }
  StartChain();
}

void BaiduTokenBridge::CompleteAll(int errno_code, const std::string& token,
                                   const std::string& cookie,
                                   const std::string& message) {
  if (host_window_ != nullptr) {
    ::KillTimer(host_window_, kWatchdogTimer);
    ::KillTimer(host_window_, kSettleTimer);
  }
  phase_ = Phase::kIdle;
  phase_label_ = "";
  flutter::EncodableValue value =
      BuildResult(errno_code, token, cookie, message);
  std::vector<Reply> replies;
  replies.swap(pending_);
  for (auto& reply : replies) {
    reply(value);
  }
}

void BaiduTokenBridge::FailAll(const std::string& message) {
  CompleteAll(-1, std::string(), std::string(), message);
}

void BaiduTokenBridge::EnterPhase(Phase phase, const char* label,
                                  UINT watchdog_ms) {
  phase_ = phase;
  phase_label_ = label;
  if (host_window_ != nullptr) {
    if (watchdog_ms > 0) {
      ::SetTimer(host_window_, kWatchdogTimer, watchdog_ms, nullptr);
    } else {
      ::KillTimer(host_window_, kWatchdogTimer);
    }
  }
}

void BaiduTokenBridge::OnWatchdog() {
  ::KillTimer(host_window_, kWatchdogTimer);
  FailAll(std::string("取号阶段超时（") + (phase_label_ ? phase_label_ : "?") +
          "）");
}

// ─────────────── 完整链路 ───────────────

void BaiduTokenBridge::StartChain() {
  EnsureHostWindow();
  if (host_window_ == nullptr) {
    FailAll("WebView2 宿主窗口创建失败");
    return;
  }
  if (!com_initialized_) {
    // Runner 主线程默认已是 STA（Flutter 模板 main.cpp），重复初始化返回
    // S_FALSE/RPC_E_CHANGED_MODE 均可接受。
    const HRESULT hr = ::CoInitializeEx(
        nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    com_initialized_ = SUCCEEDED(hr);
  }
  // WebView2 Evergreen 运行时检查（登录网关同款依赖，缺失则如实上报）。
  LPWSTR version = nullptr;
  const HRESULT vr = ::GetAvailableCoreWebView2BrowserVersionString(
      nullptr, &version);
  if (FAILED(vr) || version == nullptr) {
    FailAll("WebView2 运行时不可用（hr=0x" +
            std::to_string(static_cast<unsigned long>(vr)) + "）");
    return;
  }
  ::CoTaskMemFree(version);

  if (env_ == nullptr) {
    EnterPhase(Phase::kCreatingEnv, "创建WebView2环境", 20000);
    auto handler = Microsoft::WRL::Callback<
        ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [this](HRESULT result, ICoreWebView2Environment* created) -> HRESULT {
          OnEnvironmentCreated(result, created);
          return S_OK;
        });
    const HRESULT hr = ::CreateCoreWebView2EnvironmentWithOptions(
        nullptr, WebView2UserDataDir().c_str(), nullptr, handler.Get());
    if (FAILED(hr)) {
      FailAll("创建 WebView2 环境失败（hr=0x" +
              std::to_string(static_cast<unsigned long>(hr)) + "）");
    }
    return;
  }
  EnsureController();
}

void BaiduTokenBridge::OnEnvironmentCreated(HRESULT result,
                                            ICoreWebView2Environment* created) {
  if (phase_ != Phase::kCreatingEnv) return;
  if (FAILED(result) || created == nullptr) {
    FailAll("创建 WebView2 环境失败（回调 hr=0x" +
            std::to_string(static_cast<unsigned long>(result)) + "）");
    return;
  }
  env_ = created;
  EnsureController();
}

void BaiduTokenBridge::EnsureController() {
  if (controller_ != nullptr) {
    SeedCookies();
    NavigateMain();
    return;
  }
  EnterPhase(Phase::kCreatingCtl, "创建WebView2控制器", 20000);
  auto handler = Microsoft::WRL::Callback<
      ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
      [this](HRESULT result, ICoreWebView2Controller* created) -> HRESULT {
        OnControllerCreated(result, created);
        return S_OK;
      });
  const HRESULT hr = env_->CreateCoreWebView2Controller(host_window_,
                                                        handler.Get());
  if (FAILED(hr)) {
    FailAll("创建 WebView2 控制器失败（hr=0x" +
            std::to_string(static_cast<unsigned long>(hr)) + "）");
  }
}

void BaiduTokenBridge::OnControllerCreated(
    HRESULT result, ICoreWebView2Controller* created) {
  if (phase_ != Phase::kCreatingCtl) return;
  if (FAILED(result) || created == nullptr) {
    FailAll("创建 WebView2 控制器失败（回调 hr=0x" +
            std::to_string(static_cast<unsigned long>(result)) + "）");
    return;
  }
  controller_ = created;
  // 隐藏 + 极小边界：不渲染、不抢焦点，JS/网络照常运行。
  controller_->put_IsVisible(FALSE);
  RECT bounds{0, 0, 160, 120};
  controller_->put_Bounds(bounds);
  if (FAILED(controller_->get_CoreWebView2(&webview_)) ||
      webview_ == nullptr) {
    FailAll("WebView2 内核对象获取失败");
    return;
  }
  // 导航完成事件（常驻，按 phase 过滤）。
  auto nav = Microsoft::WRL::Callback<
      ICoreWebView2NavigationCompletedEventHandler>(
      [this](ICoreWebView2* sender,
             ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
        BOOL ok = FALSE;
        if (args != nullptr) args->get_IsSuccess(&ok);
        OnNavigationCompleted(ok == TRUE);
        return S_OK;
      });
  webview_->add_NavigationCompleted(nav.Get(), &nav_token_);
  // 渲染进程崩溃：如实终止本次链路（下次调用重建）。
  auto proc = Microsoft::WRL::Callback<ICoreWebView2ProcessFailedEventHandler>(
      [this](ICoreWebView2* sender,
             ICoreWebView2ProcessFailedEventArgs* args) -> HRESULT {
        if (phase_ != Phase::kIdle) {
          last_fetch_ok_ = false;
          FailAll("WebView2 进程异常退出");
        }
        return S_OK;
      });
  webview_->add_ProcessFailed(proc.Get(), &proc_token_);
  // 屏蔽新窗口（disk/main 可能弹窗）。
  auto win = Microsoft::WRL::Callback<
      ICoreWebView2NewWindowRequestedEventHandler>(
      [](ICoreWebView2* sender,
         ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
        if (args != nullptr) args->put_Handled(TRUE);
        return S_OK;
      });
  webview_->add_NewWindowRequested(win.Get(), &win_token_);

  SeedCookies();
  NavigateMain();
}

void BaiduTokenBridge::SeedCookies() {
  if (webview_ == nullptr || cookie_header_.empty()) return;
  Microsoft::WRL::ComPtr<ICoreWebView2_2> web2;
  if (FAILED(webview_.As(&web2)) || web2 == nullptr) return;
  Microsoft::WRL::ComPtr<ICoreWebView2CookieManager> manager;
  if (FAILED(web2->get_CookieManager(&manager)) || manager == nullptr) return;
  for (const auto& pair : ParseCookieHeader(cookie_header_)) {
    Microsoft::WRL::ComPtr<ICoreWebView2Cookie> cookie;
    if (FAILED(manager->CreateCookie(
            Utf8ToWide(pair.first).c_str(), Utf8ToWide(pair.second).c_str(),
            L".baidu.com", L"/", &cookie)) ||
        cookie == nullptr) {
      continue;
    }
    cookie->put_IsSecure(FALSE);
    cookie->put_IsHttpOnly(FALSE);
    manager->AddOrUpdateCookie(cookie.Get());
  }
}

void BaiduTokenBridge::NavigateMain() {
  if (webview_ == nullptr) {
    FailAll("WebView2 内核不可用");
    return;
  }
  EnterPhase(Phase::kNavigating, "导航disk/main", 25000);
  const HRESULT hr = webview_->Navigate(L"https://pan.baidu.com/disk/main");
  if (FAILED(hr)) {
    FailAll("disk/main 导航启动失败（hr=0x" +
            std::to_string(static_cast<unsigned long>(hr)) + "）");
  }
}

void BaiduTokenBridge::OnNavigationCompleted(bool succeeded) {
  if (phase_ != Phase::kNavigating) return;
  if (!succeeded) {
    FailAll("disk/main 导航失败（网络/风控页）");
    return;
  }
  // 沉降 800ms：等服务端 Set-Cookie（指纹字段）落 Jar 后再取号。
  EnterPhase(Phase::kSettle, "Set-Cookie沉降", 0);
  ::SetTimer(host_window_, kSettleTimer, 800, nullptr);
}

void BaiduTokenBridge::OnSettle() {
  ::KillTimer(host_window_, kSettleTimer);
  if (phase_ != Phase::kSettle) return;
  EnterPhase(Phase::kExecuting, "页面fetch", 15000);
  RunScript();
}

// ─────────────── 页面取号 ───────────────

void BaiduTokenBridge::RunScript() {
  if (webview_ == nullptr) {
    FailAll("WebView2 内核不可用");
    return;
  }
  auto handler = Microsoft::WRL::Callback<
      ICoreWebView2ExecuteScriptCompletedHandler>(
      [this](HRESULT result, LPWSTR json) -> HRESULT {
        if (FAILED(result) || json == nullptr) {
          FailAll("页面脚本执行失败（hr=0x" +
                  std::to_string(static_cast<unsigned long>(result)) + "）");
          return S_OK;
        }
        OnScriptResult(WideToUtf8(json));
        return S_OK;
      });
  const HRESULT hr =
      webview_->ExecuteScript(Utf8ToWide(kBdstokenJs).c_str(), handler.Get());
  if (FAILED(hr)) {
    FailAll("页面脚本提交失败（hr=0x" +
            std::to_string(static_cast<unsigned long>(hr)) + "）");
  }
}

void BaiduTokenBridge::OnScriptResult(const std::string& js_return_json) {
  const std::string inner = DecodeJsonStringLiteral(js_return_json);
  const bool http_ok = inner.find("\"httpOk\":true") != std::string::npos;
  const int errno_code =
      FindJsonIntValue(inner, "errno", http_ok ? -2 : -1);
  std::string token = FindJsonStringValue(inner, "bdstoken");
  if (token.empty()) {
    token = FindJsonStringValue(inner, "pageToken");
  }
  const std::string js_err = FindJsonStringValue(inner, "err");

  if (errno_code == 0 && !token.empty()) {
    last_fetch_ok_ = true;
    FetchJarCookiesThenComplete(token);
    return;
  }

  // 失败 → 种 Cookie + 重导航补一次（覆盖「凭据 Cookie 未生效 / 被清」场景）。
  if (!seed_retry_done_ && errno_code != -100) {
    seed_retry_done_ = true;
    SeedCookies();
    NavigateMain();
    return;
  }

  last_fetch_ok_ = false;
  std::string message;
  if (errno_code == -6) {
    message = "百度登录态被风控（errno=-6）——请到授权中心重新扫码登录";
  } else if (!js_err.empty()) {
    message = "页面取号异常：" + js_err;
  } else if (!http_ok) {
    message = "gettemplatevariable 请求未成功（疑似风控页）";
  } else {
    message = "响应未含 bdstoken：" + Excerpt(inner, 160);
  }
  CompleteAll(errno_code, std::string(), std::string(), message);
}

void BaiduTokenBridge::FetchJarCookiesThenComplete(const std::string& token) {
  Microsoft::WRL::ComPtr<ICoreWebView2_2> web2;
  Microsoft::WRL::ComPtr<ICoreWebView2CookieManager> manager;
  if (webview_ == nullptr || FAILED(webview_.As(&web2)) || web2 == nullptr ||
      FAILED(web2->get_CookieManager(&manager)) || manager == nullptr) {
    CompleteAll(0, token, std::string(), "Jar Cookie 读取失败（token 已取得）");
    return;
  }
  auto handler = Microsoft::WRL::Callback<
      ICoreWebView2GetCookiesCompletedHandler>(
      [this, token](HRESULT result, ICoreWebView2CookieList* list) -> HRESULT {
        std::string joined;
        if (SUCCEEDED(result) && list != nullptr) {
          UINT32 count = 0;
          list->get_Count(&count);
          for (UINT32 i = 0; i < count; ++i) {
            Microsoft::WRL::ComPtr<ICoreWebView2Cookie> cookie;
            if (FAILED(list->GetValueAtIndex(i, &cookie)) || cookie == nullptr) {
              continue;
            }
            LPWSTR name = nullptr;
            LPWSTR value = nullptr;
            if (FAILED(cookie->get_Name(&name)) || name == nullptr) continue;
            cookie->get_Value(&value);
            if (!joined.empty()) joined += "; ";
            joined += WideToUtf8(name) + "=" +
                      (value != nullptr ? WideToUtf8(value) : std::string());
            ::CoTaskMemFree(name);
            if (value != nullptr) ::CoTaskMemFree(value);
          }
        }
        CompleteAll(0, token, joined, std::string());
        return S_OK;
      });
  const HRESULT hr = manager->GetCookies(L".baidu.com", handler.Get());
  if (FAILED(hr)) {
    CompleteAll(0, token, std::string(), "Jar Cookie 读取失败（token 已取得）");
  }
}

}  // namespace vbox
