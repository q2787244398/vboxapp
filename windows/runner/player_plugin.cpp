//
//  player_plugin.cpp
//  Runner
//
//  批次 C · C-11：Windows 播放器插件（libmpv 主后端）实现。
//  协议与架构说明见 player_plugin.h 文件头注释。

#include "player_plugin.h"

#include <windows.h>

#include <chrono>
#include <cstdint>
#include <utility>
#include <variant>

#include <flutter/event_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

namespace vbox {

namespace {

// ─────────────── EncodableValue 解析辅助（Dart 侧 open 参数） ───────────────

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  if (value == nullptr || !std::holds_alternative<flutter::EncodableMap>(*value)) {
    return nullptr;
  }
  return &std::get<flutter::EncodableMap>(*value);
}

std::string GetString(const flutter::EncodableMap& map, const std::string& key,
                      const std::string& fallback = "") {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<std::string>(it->second)) {
    return fallback;
  }
  return std::get<std::string>(it->second);
}

bool GetBool(const flutter::EncodableMap& map, const std::string& key,
             bool fallback = false) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<bool>(it->second)) {
    return fallback;
  }
  return std::get<bool>(it->second);
}

// headers（Dart Map<String,String>）→ mpv http-header-fields 选项串。
std::string JoinHeaders(const flutter::EncodableMap& map) {
  const auto it = map.find(flutter::EncodableValue("headers"));
  if (it == map.end() || !std::holds_alternative<flutter::EncodableMap>(it->second)) {
    return "";
  }
  const flutter::EncodableMap& headers =
      std::get<flutter::EncodableMap>(it->second);
  std::string joined;
  for (const auto& entry : headers) {
    if (!std::holds_alternative<std::string>(entry.first) ||
        !std::holds_alternative<std::string>(entry.second)) {
      continue;
    }
    if (!joined.empty()) {
      joined += ",";
    }
    joined += std::get<std::string>(entry.first) + ": " +
              std::get<std::string>(entry.second);
  }
  return joined;
}

}  // namespace

// ─────────────── MpvApi：动态加载 mpv-2.dll ───────────────

bool MpvApi::Load() {
  if (loaded) {
    return true;
  }
  HMODULE mod = ::LoadLibraryW(L"mpv-2.dll");
  if (mod == nullptr) {
    // 按 GetLastError 分类（LoadLibraryW 失败 ≠ 一定是「文件缺失」：
    // 该 dll 导入 vulkan-1.dll 等非保证预装的系统组件，依赖解析失败
    // 同样返回 null）。
    const DWORD err = ::GetLastError();
    switch (err) {
      case ERROR_FILE_NOT_FOUND:
      case ERROR_PATH_NOT_FOUND:
        load_error =
            "mpv-2.dll 未随包分发（安装包不完整或被安全软件清理）";
        break;
      case ERROR_MOD_NOT_FOUND:
        load_error =
            "mpv-2.dll 依赖的运行库缺失（常见：系统缺 vulkan-1.dll，"
            "请安装显卡驱动或 Vulkan Runtime 后重试）";
        break;
      case ERROR_BAD_EXE_FORMAT:
        load_error = "mpv-2.dll 架构不匹配（需 64 位）";
        break;
      case ERROR_ACCESS_DENIED:
        load_error = "mpv-2.dll 访问被拒绝（可能被安全软件拦截）";
        break;
      default:
        load_error = "mpv-2.dll 加载失败（Win32 错误码 " +
                     std::to_string(err) + "）";
        break;
    }
    return false;
  }
  bool ok = true;
  // libmpv 导出符号统一带 `mpv_` 前缀（mpv_create / mpv_render_context_* 等）。
#define LOAD_MPV_SYM(Name)                                                 \
  do {                                                                     \
    Name = reinterpret_cast<decltype(Name)>(                               \
        ::GetProcAddress(mod, "mpv_" #Name));                              \
    if (Name == nullptr) {                                                 \
      ok = false;                                                          \
    }                                                                      \
  } while (0)
  LOAD_MPV_SYM(create);
  LOAD_MPV_SYM(initialize);
  LOAD_MPV_SYM(terminate_destroy);
  LOAD_MPV_SYM(command);
  LOAD_MPV_SYM(set_option_string);
  LOAD_MPV_SYM(set_property);
  LOAD_MPV_SYM(get_property);
  LOAD_MPV_SYM(observe_property);
  LOAD_MPV_SYM(unobserve_property);
  LOAD_MPV_SYM(wait_event);
  LOAD_MPV_SYM(error_string);
  LOAD_MPV_SYM(free);
#undef LOAD_MPV_SYM
  if (!ok) {
    ::OutputDebugStringW(
        L"vbox: mpv-2.dll 符号不完整，libmpv 后端不可用（D6 无降级，报错给 Dart）\n");
    return false;
  }
  // render API 为可选增强（R-渲1）：旧 dll 缺失时保持 nullptr → 控制面可用但无
  // 纹理输出，Dart 侧渲染深色占位（不误判为黑屏故障）。
#define LOAD_MPV_RENDER_SYM(Name)                                          \
  do {                                                                     \
    Name = reinterpret_cast<decltype(Name)>(                               \
        ::GetProcAddress(mod, "mpv_" #Name));                              \
  } while (0)
  LOAD_MPV_RENDER_SYM(render_context_create);
  LOAD_MPV_RENDER_SYM(render_context_render);
  LOAD_MPV_RENDER_SYM(render_context_set_update_callback);
  LOAD_MPV_RENDER_SYM(render_context_update);
  LOAD_MPV_RENDER_SYM(render_context_free);
#undef LOAD_MPV_RENDER_SYM
  loaded = true;
  return true;
}

// ─────────────── 注册 ───────────────

void PlayerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<PlayerPlugin>(registrar));
}

PlayerPlugin::PlayerPlugin(flutter::PluginRegistrarWindows* registrar)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.vbox.player/player",
          &flutter::StandardMethodCodec::GetInstance())),
      events_(std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.vbox.player/player/events",
          &flutter::StandardMethodCodec::GetInstance())) {
  // R-渲1：纹理注册表（open 建纹理、dispose 释放；纹理进程内唯一）。
  texture_registrar_ = registrar->texture_registrar();
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  stream_handler_ = std::make_unique<StreamHandler>(this);
  events_->SetStreamHandler(std::move(stream_handler_));
}

PlayerPlugin::~PlayerPlugin() {
  ShutdownMpv();
  ClearSink();
}

// ─────────────── StreamHandler ───────────────

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
PlayerPlugin::StreamHandler::OnListenInternal(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
  plugin_->SetSink(std::move(events));
  // 已有播放器时补发一次当前进度，避免 Dart 侧错过中间态（对齐 macOS 插件）。
  plugin_->EmitProgress();
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
PlayerPlugin::StreamHandler::OnCancelInternal(
    const flutter::EncodableValue* arguments) {
  plugin_->ClearSink();
  return nullptr;
}

void PlayerPlugin::SetSink(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  sink_ =
      std::shared_ptr<flutter::EventSink<flutter::EncodableValue>>(sink.release());
}

void PlayerPlugin::ClearSink() {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  sink_.reset();
}

std::shared_ptr<flutter::EventSink<flutter::EncodableValue>>
PlayerPlugin::SinkSnapshot() {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  return sink_;
}

// ─────────────── 方法面 ───────────────

void PlayerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "open") {
    Open(call.arguments(), std::move(result));
  } else if (method == "play") {
    Play(std::move(result));
  } else if (method == "pause") {
    Pause(std::move(result));
  } else if (method == "seekTo") {
    SeekTo(call.arguments(), std::move(result));
  } else if (method == "setVolume") {
    SetVolume(call.arguments(), std::move(result));
  } else if (method == "setSpeed") {
    SetSpeed(call.arguments(), std::move(result));
  } else if (method == "dispose") {
    Dispose(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void PlayerPlugin::Open(
    const flutter::EncodableValue* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap* map = AsMap(args);
  if (map == nullptr) {
    result->Error("E_PARAM", "open 缺少参数");
    return;
  }
  const std::string url = GetString(*map, "url");
  if (url.empty()) {
    result->Error("E_INVALID_SOURCE", "无效的播放源");
    return;
  }

  // 后端口径：本插件仅实现 libmpv（D6 桌面主后端）。
  const std::string backend = GetString(*map, "backend", "libmpv");
  if (backend != "libmpv") {
    result->Error("E_BACKEND_UNAVAILABLE",
                  "该插件仅实现 libmpv 后端，收到 backend=" + backend);
    return;
  }

  // D28：mpv-2.dll 随包分发；加载失败（文件缺失 / 依赖缺失 / 拦截）按
  // Load() 分类原因上报 E_BACKEND_UNAVAILABLE 由 Dart 侧处理。
  if (!api_.Load()) {
    result->Error("E_BACKEND_UNAVAILABLE", api_.load_error + "，libmpv 不可用");
    return;
  }

  // 复用句柄时先释放旧实例。
  ShutdownMpv();

  const bool is_live = GetBool(*map, "isLive", false);
  if (!InitializeMpv(is_live)) {
    result->Error("E_BACKEND_UNAVAILABLE", "libmpv 初始化失败");
    return;
  }

  // 自定义请求头 → http-header-fields 选项（open 后由 loadfile 生效）。
  const std::string headers = JoinHeaders(*map);
  if (!headers.empty()) {
    api_.set_option_string(mpv_, "http-header-fields", headers.c_str());
  }

  // loadfile（replace：单文件播放，与 macOS/Android 语义一致）。
  const char* load_args[] = {"loadfile", url.c_str(), "replace", nullptr};
  if (api_.command(mpv_, load_args) < 0) {
    ShutdownMpv();
    result->Error("E_OPEN", "loadfile 命令失败");
    return;
  }

  EmitState("opening");
  // R-渲1：把纹理句柄交回 Dart（`Texture(textureId:)` 承载画面）。
  // 无渲染输出面（render API 缺失）时返回空 map → Dart textureId=null → 深色占位。
  flutter::EncodableMap payload;
  if (texture_id_ >= 0) {
    payload[flutter::EncodableValue("textureId")] =
        flutter::EncodableValue(texture_id_);
  }
  result->Success(flutter::EncodableValue(payload));
}

void PlayerPlugin::Play(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (mpv_ != nullptr) {
    int flag = 0;  // pause=false
    api_.set_property(mpv_, "pause", MPV_FORMAT_FLAG, &flag);
  }
  result->Success();
}

void PlayerPlugin::Pause(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (mpv_ != nullptr) {
    int flag = 1;  // pause=true
    api_.set_property(mpv_, "pause", MPV_FORMAT_FLAG, &flag);
  }
  result->Success();
}

void PlayerPlugin::SeekTo(
    const flutter::EncodableValue* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (mpv_ == nullptr) {
    result->Success();
    return;
  }
  int64_t position_ms = 0;
  if (args != nullptr) {
    if (std::holds_alternative<int32_t>(*args)) {
      position_ms = std::get<int32_t>(*args);
    } else if (std::holds_alternative<int64_t>(*args)) {
      position_ms = std::get<int64_t>(*args);
    } else {
      result->Error("E_BAD_ARGUMENT", "seekTo 需毫秒整数");
      return;
    }
  }
  double seconds = static_cast<double>(position_ms) / 1000.0;
  api_.set_property(mpv_, "time-pos", MPV_FORMAT_DOUBLE, &seconds);
  result->Success();
}

void PlayerPlugin::SetVolume(
    const flutter::EncodableValue* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (args == nullptr || !std::holds_alternative<double>(*args)) {
    result->Error("E_BAD_ARGUMENT", "setVolume 需浮点数");
    return;
  }
  const double volume = std::get<double>(*args);
  if (mpv_ != nullptr) {
    const double clamped = (volume < 0.0) ? 0.0 : ((volume > 1.0) ? 1.0 : volume);
    double mpv_volume = clamped * 100.0;  // mpv 音量域 0~100
    api_.set_property(mpv_, "volume", MPV_FORMAT_DOUBLE, &mpv_volume);
  }
  result->Success();
}

void PlayerPlugin::SetSpeed(
    const flutter::EncodableValue* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (args == nullptr || !std::holds_alternative<double>(*args)) {
    result->Error("E_BAD_ARGUMENT", "setSpeed 需浮点数");
    return;
  }
  const double speed = std::get<double>(*args);
  if (mpv_ != nullptr) {
    double clamped = (speed < 0.25) ? 0.25 : ((speed > 4.0) ? 4.0 : speed);
    api_.set_property(mpv_, "speed", MPV_FORMAT_DOUBLE, &clamped);
  }
  result->Success();
}

void PlayerPlugin::Dispose(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  ShutdownMpv();
  result->Success();
}

// ─────────────── libmpv 生命周期 ───────────────

bool PlayerPlugin::InitializeMpv(bool auto_play) {
  mpv_handle* handle = api_.create();
  if (handle == nullptr) {
    return false;
  }
  // R-渲1：有 render API 时走 `vo=libmpv`（mpv_render_context 前置），
  // 每帧软渲染为 BGRA 交 Flutter 纹理上屏；否则退回 `vo=null`（纯控制面）。
  // 注意：vo 属「初始化前生效」选项，必须早于 mpv_initialize 设置，
  // 否则默认 vo 会在 Windows 弹出独立 mpv 渲染窗口，破坏无窗口契约。
  const bool can_render = api_.render_context_create != nullptr;
  api_.set_option_string(handle, "vo", can_render ? "libmpv" : "null");
  if (api_.initialize(handle) < 0) {
    api_.terminate_destroy(handle);
    return false;
  }
  mpv_ = handle;

  // 直播流（isLive）open 后自动起播，对齐 Android ExoPlayer 行为；点播保持暂停待 play()。
  int pause = auto_play ? 0 : 1;
  api_.set_property(mpv_, "pause", MPV_FORMAT_FLAG, &pause);

  // 事件面：进度 / 状态由属性变更驱动。
  api_.observe_property(mpv_, 0, "time-pos", MPV_FORMAT_DOUBLE);
  api_.observe_property(mpv_, 0, "duration", MPV_FORMAT_DOUBLE);
  api_.observe_property(mpv_, 0, "pause", MPV_FORMAT_FLAG);
  api_.observe_property(mpv_, 0, "paused-for-cache", MPV_FORMAT_FLAG);
  api_.observe_property(mpv_, 0, "demuxer-cache-time", MPV_FORMAT_DOUBLE);

  // 渲染输出面（R-渲1）：建 render_context + 注册纹理 + 起渲染线程。
  if (can_render) {
    SetupRenderContext();
  }

  running_ = true;
  event_thread_ =
      std::make_unique<std::thread>(&PlayerPlugin::RunEventLoop, this);
  return true;
}

void PlayerPlugin::ShutdownMpv() {
  // 先停渲染线程（避免释放 render_context 时仍在渲染）。
  if (render_thread_ != nullptr) {
    render_running_ = false;
    render_cv_.notify_all();
    render_thread_->join();
    render_thread_.reset();
  }
  if (render_ctx_ != nullptr) {
    api_.render_context_set_update_callback(render_ctx_, nullptr, nullptr);
    api_.render_context_free(render_ctx_);
    render_ctx_ = nullptr;
  }
  UnregisterTexture();
  {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    frame_buffer_.clear();
    frame_width_ = 0;
    frame_height_ = 0;
    frame_locked_ = false;
  }
  last_video_width_ = 0;
  last_video_height_ = 0;

  if (event_thread_ != nullptr) {
    running_ = false;
    event_thread_->join();
    event_thread_.reset();
  }
  if (mpv_ != nullptr) {
    api_.terminate_destroy(mpv_);
    mpv_ = nullptr;
  }
  state_ = "idle";
}

// ─────────────── 渲染输出面（R-渲1）───────────────

bool PlayerPlugin::SetupRenderContext() {
  if (api_.render_context_create == nullptr || mpv_ == nullptr) {
    return false;
  }
  const char* api_type = kRenderApiSw;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(api_type)},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  mpv_render_context* ctx = nullptr;
  if (api_.render_context_create(&ctx, mpv_, params) < 0 || ctx == nullptr) {
    // 无纹理输出：Dart 侧深色占位，控制面（播放/进度）不受影响。
    return false;
  }
  render_ctx_ = ctx;
  api_.render_context_set_update_callback(render_ctx_, &PlayerPlugin::OnRenderUpdate,
                                          this);
  RegisterTexture();
  render_running_ = true;
  render_thread_ =
      std::make_unique<std::thread>(&PlayerPlugin::RunRenderLoop, this);
  return true;
}

void PlayerPlugin::RegisterTexture() {
  if (texture_registrar_ == nullptr || texture_ != nullptr) {
    return;
  }
  texture_ = std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
      [this](size_t width, size_t height) -> const FlutterDesktopPixelBuffer* {
        return CopyPixelBuffer(width, height);
      }));
  texture_id_ = texture_registrar_->RegisterTexture(texture_.get());
}

void PlayerPlugin::UnregisterTexture() {
  if (texture_registrar_ != nullptr && texture_id_ >= 0) {
    texture_registrar_->UnregisterTexture(texture_id_);
  }
  texture_id_ = -1;
  texture_.reset();
}

void PlayerPlugin::OnRenderUpdate(void* callback_ctx) {
  auto* self = static_cast<PlayerPlugin*>(callback_ctx);
  if (self == nullptr) {
    return;
  }
  self->render_requested_ = true;
  self->render_cv_.notify_one();
}

void PlayerPlugin::RunRenderLoop() {
  while (render_running_.load()) {
    {
      std::unique_lock<std::mutex> lock(render_mutex_);
      render_cv_.wait_for(lock, std::chrono::milliseconds(100), [this] {
        return render_requested_.load() || !render_running_.load();
      });
      if (!render_running_.load()) {
        break;
      }
      render_requested_ = false;
    }
    if (render_ctx_ == nullptr) {
      continue;
    }
    // update 返回 kRenderUpdateFrame=有新帧；返回 0 也可能是重绘请求，均渲染一帧。
    api_.render_context_update(render_ctx_);
    RenderFrame();
  }
}

void PlayerPlugin::RenderFrame() {
  if (render_ctx_ == nullptr || api_.render_context_render == nullptr) {
    return;
  }
  // 视频目标尺寸：优先 coded 尺寸（width/height），回退 display 尺寸。
  int64_t width = 0;
  int64_t height = 0;
  if (!GetInt64Property("width", &width) || width <= 0 ||
      !GetInt64Property("height", &height) || height <= 0) {
    if (!GetInt64Property("dwidth", &width) || width <= 0 ||
        !GetInt64Property("dheight", &height) || height <= 0) {
      return;  // 尚未解出视频轨（纯音频 / 加载中）。
    }
  }

  const size_t pixel_width = static_cast<size_t>(width);
  const size_t pixel_height = static_cast<size_t>(height);
  // mpv SW 渲染参数 data 域为 void*（非 const），故 stride 需为可变左值。
  int stride = static_cast<int>(pixel_width * 4);
  std::vector<uint8_t> scratch(pixel_width * pixel_height * 4);

  int size[2] = {static_cast<int>(pixel_width), static_cast<int>(pixel_height)};
  const char* format = "bgra";
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_SW_SIZE, size},
      {MPV_RENDER_PARAM_SW_FORMAT, const_cast<char*>(format)},
      {MPV_RENDER_PARAM_SW_STRIDE, &stride},
      {MPV_RENDER_PARAM_SW_POINTER, scratch.data()},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  if (api_.render_context_render(render_ctx_, params) < 0) {
    return;
  }

  {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    if (frame_locked_.load()) {
      return;  // 引擎正采样前缓冲，丢弃本帧（下一帧回调再补）。
    }
    frame_buffer_.swap(scratch);
    frame_width_ = static_cast<int>(pixel_width);
    frame_height_ = static_cast<int>(pixel_height);
  }

  if (texture_registrar_ != nullptr && texture_id_ >= 0) {
    texture_registrar_->MarkTextureFrameAvailable(texture_id_);
  }

  // 视频尺寸变更上报（Dart 侧输出面纵横比自适应；去重避免抖动）。
  const int vw = static_cast<int>(pixel_width);
  const int vh = static_cast<int>(pixel_height);
  if (vw != last_video_width_ || vh != last_video_height_) {
    last_video_width_ = vw;
    last_video_height_ = vh;
    EmitVideoSize(vw, vh);
  }
}

const FlutterDesktopPixelBuffer* PlayerPlugin::CopyPixelBuffer(size_t width,
                                                               size_t height) {
  (void)width;
  (void)height;
  std::lock_guard<std::mutex> lock(frame_mutex_);
  if (frame_width_ <= 0 || frame_height_ <= 0 || frame_buffer_.empty()) {
    return nullptr;
  }
  pixel_buffer_.buffer = frame_buffer_.data();
  pixel_buffer_.width = static_cast<size_t>(frame_width_);
  pixel_buffer_.height = static_cast<size_t>(frame_height_);
  pixel_buffer_.release_callback = &PlayerPlugin::OnPixelBufferReleased;
  pixel_buffer_.release_context = this;
  frame_locked_ = true;
  return &pixel_buffer_;
}

void PlayerPlugin::OnPixelBufferReleased(void* release_context) {
  auto* self = static_cast<PlayerPlugin*>(release_context);
  if (self == nullptr) {
    return;
  }
  self->frame_locked_ = false;
}

void PlayerPlugin::RunEventLoop() {
  while (running_.load()) {
    // 短超时轮询：支持 running_ 标志及时退出。
    mpv_event* event = api_.wait_event(mpv_, 0.1);
    if (event == nullptr) {
      continue;
    }
    if (event->event_id == MPV_EVENT_SHUTDOWN) {
      break;
    }
    HandleMpvEvent(event);
  }
}

void PlayerPlugin::HandleMpvEvent(const mpv_event* event) {
  switch (event->event_id) {
    case MPV_EVENT_START_FILE:
      EmitState("opening");
      break;
    case MPV_EVENT_FILE_LOADED: {
      // 文件加载完成：是否起播取决于 pause 属性。
      int paused = 0;
      const bool has_pause = GetFlagProperty("pause", &paused);
      EmitState(has_pause && paused ? "paused" : "playing");
      EmitProgress();
      break;
    }
    case MPV_EVENT_PLAYBACK_RESTART: {
      int paused = 0;
      const bool has_pause = GetFlagProperty("pause", &paused);
      EmitState(has_pause && paused ? "paused" : "playing");
      break;
    }
    case MPV_EVENT_END_FILE: {
      const auto* end_file =
          static_cast<const mpv_event_end_file*>(event->data);
      if (end_file != nullptr &&
          end_file->reason == MPV_END_FILE_REASON_ERROR) {
        const char* detail = api_.error_string(end_file->error);
        EmitError(detail != nullptr ? detail : "播放失败", true);
        EmitState("error");
      } else if (end_file != nullptr &&
                 end_file->reason == MPV_END_FILE_REASON_EOF) {
        EmitState("ended");
      }
      break;
    }
    case MPV_EVENT_PROPERTY_CHANGE: {
      const auto* prop = static_cast<const mpv_event_property*>(event->data);
      if (prop == nullptr) {
        break;
      }
      const std::string name = prop->name != nullptr ? prop->name : "";
      if (name == "time-pos" || name == "duration") {
        EmitProgress();
      } else if (name == "pause") {
        int paused = 0;
        if (prop->format == MPV_FORMAT_FLAG && prop->data != nullptr) {
          paused = *static_cast<const int*>(prop->data);
        }
        EmitState(paused ? "paused" : "playing");
      } else if (name == "paused-for-cache") {
        int caching = 0;
        if (prop->format == MPV_FORMAT_FLAG && prop->data != nullptr) {
          caching = *static_cast<const int*>(prop->data);
        }
        if (caching) {
          EmitState("buffering");
        } else {
          int paused = 0;
          const bool has_pause = GetFlagProperty("pause", &paused);
          EmitState(has_pause && paused ? "paused" : "playing");
        }
      }
      break;
    }
    default:
      // MPV_EVENT_NONE / LOG_MESSAGE / QUEUE_OVERFLOW 等：控制面忽略。
      break;
  }
}

// ─────────────── 事件面 ───────────────

void PlayerPlugin::EmitState(const std::string& value) {
  state_ = value;
  std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> sink =
      SinkSnapshot();
  if (sink == nullptr) {
    return;
  }
  sink->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue(std::string("type")),
       flutter::EncodableValue(std::string("state"))},
      {flutter::EncodableValue(std::string("value")),
       flutter::EncodableValue(value)},
  }));
}

void PlayerPlugin::EmitProgress() {
  if (mpv_ == nullptr) {
    return;
  }
  double position_seconds = -1.0;
  double duration_seconds = -1.0;
  double buffered_seconds = -1.0;
  GetDoubleProperty("time-pos", &position_seconds);
  GetDoubleProperty("duration", &duration_seconds);
  GetDoubleProperty("demuxer-cache-time", &buffered_seconds);

  const bool is_live = duration_seconds < 0.0;
  const int64_t position_ms =
      position_seconds < 0.0 ? 0 : static_cast<int64_t>(position_seconds * 1000.0);
  const int64_t duration_ms =
      is_live ? 0 : static_cast<int64_t>(duration_seconds * 1000.0);
  const int64_t buffered_ms =
      buffered_seconds < 0.0 ? 0 : static_cast<int64_t>(buffered_seconds * 1000.0);

  std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> sink =
      SinkSnapshot();
  if (sink == nullptr) {
    return;
  }
  sink->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue(std::string("type")),
       flutter::EncodableValue(std::string("progress"))},
      {flutter::EncodableValue(std::string("positionMs")),
       flutter::EncodableValue(position_ms)},
      {flutter::EncodableValue(std::string("durationMs")),
       flutter::EncodableValue(duration_ms)},
      {flutter::EncodableValue(std::string("bufferedMs")),
       flutter::EncodableValue(buffered_ms)},
      {flutter::EncodableValue(std::string("isLive")),
       flutter::EncodableValue(is_live)},
  }));
}

void PlayerPlugin::EmitVideoSize(int width, int height) {
  std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> sink =
      SinkSnapshot();
  if (sink == nullptr) {
    return;
  }
  sink->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue(std::string("type")),
       flutter::EncodableValue(std::string("videoSize"))},
      {flutter::EncodableValue(std::string("width")),
       flutter::EncodableValue(width)},
      {flutter::EncodableValue(std::string("height")),
       flutter::EncodableValue(height)},
  }));
}

void PlayerPlugin::EmitError(const std::string& message, bool fatal) {
  std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> sink =
      SinkSnapshot();
  if (sink == nullptr) {
    return;
  }
  sink->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue(std::string("type")),
       flutter::EncodableValue(std::string("error"))},
      {flutter::EncodableValue(std::string("message")),
       flutter::EncodableValue(message)},
      {flutter::EncodableValue(std::string("fatal")),
       flutter::EncodableValue(fatal)},
  }));
}

bool PlayerPlugin::GetDoubleProperty(const char* name, double* out) {
  if (mpv_ == nullptr) {
    return false;
  }
  double value = -1.0;
  const int rc = api_.get_property(mpv_, name, MPV_FORMAT_DOUBLE, &value);
  if (rc < 0) {
    return false;
  }
  *out = value;
  return true;
}

bool PlayerPlugin::GetFlagProperty(const char* name, int* out) {
  if (mpv_ == nullptr) {
    return false;
  }
  int value = 0;
  const int rc = api_.get_property(mpv_, name, MPV_FORMAT_FLAG, &value);
  if (rc < 0) {
    return false;
  }
  *out = value;
  return true;
}

bool PlayerPlugin::GetInt64Property(const char* name, int64_t* out) {
  if (mpv_ == nullptr) {
    return false;
  }
  int64_t value = 0;
  const int rc = api_.get_property(mpv_, name, MPV_FORMAT_INT64, &value);
  if (rc < 0) {
    return false;
  }
  *out = value;
  return true;
}

}  // namespace vbox
