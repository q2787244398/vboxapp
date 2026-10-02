//
//  player_plugin.cpp
//  Runner
//
//  批次 C · C-11：Windows 播放器插件（libmpv 主后端）实现。
//  协议与架构说明见 player_plugin.h 文件头注释。

#include "player_plugin.h"

#include <windows.h>

#include <cstdint>
#include <utility>

#include <flutter/event_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

namespace vbox {

namespace {

// ─────────────── EncodableValue 解析辅助（Dart 侧 open 参数） ───────────────

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  if (value == nullptr ||
      value->Type() != flutter::EncodableValue::Type::kMap) {
    return nullptr;
  }
  return &std::get<flutter::EncodableMap>(*value);
}

std::string GetString(const flutter::EncodableMap& map, const std::string& key,
                      const std::string& fallback = "") {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end() ||
      it->second.Type() != flutter::EncodableValue::Type::kString) {
    return fallback;
  }
  return std::get<std::string>(it->second);
}

bool GetBool(const flutter::EncodableMap& map, const std::string& key,
             bool fallback = false) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end() ||
      it->second.Type() != flutter::EncodableValue::Type::kBool) {
    return fallback;
  }
  return std::get<bool>(it->second);
}

// headers（Dart Map<String,String>）→ mpv http-header-fields 选项串。
std::string JoinHeaders(const flutter::EncodableMap& map) {
  const auto it = map.find(flutter::EncodableValue("headers"));
  if (it == map.end() ||
      it->second.Type() != flutter::EncodableValue::Type::kMap) {
    return "";
  }
  const flutter::EncodableMap& headers =
      std::get<flutter::EncodableMap>(it->second);
  std::string joined;
  for (const auto& entry : headers) {
    if (entry.first.Type() != flutter::EncodableValue::Type::kString ||
        entry.second.Type() != flutter::EncodableValue::Type::kString) {
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
    return false;
  }
  bool ok = true;
#define LOAD_MPV_SYM(Name)                                             \
  do {                                                                 \
    Name = reinterpret_cast<decltype(Name)>(::GetProcAddress(mod, #Name)); \
    if (Name == nullptr) {                                             \
      ok = false;                                                      \
    }                                                                  \
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
PlayerPlugin::StreamHandler::OnListen(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
  plugin_->SetSink(std::move(events));
  // 已有播放器时补发一次当前进度，避免 Dart 侧错过中间态（对齐 macOS 插件）。
  plugin_->EmitProgress();
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
PlayerPlugin::StreamHandler::OnCancel(
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
    result->Error("E_PARAM", "open 缺少参数", nullptr);
    return;
  }
  const std::string url = GetString(*map, "url");
  if (url.empty()) {
    result->Error("E_INVALID_SOURCE", "无效的播放源", nullptr);
    return;
  }

  // 后端口径：本插件仅实现 libmpv（D6 桌面主后端）。
  const std::string backend = GetString(*map, "backend", "libmpv");
  if (backend != "libmpv") {
    result->Error("E_BACKEND_UNAVAILABLE",
                  "该插件仅实现 libmpv 后端，收到 backend=" + backend, nullptr);
    return;
  }

  // D28：mpv-2.dll 随包分发，缺失时上报 E_BACKEND_UNAVAILABLE 由 Dart 侧处理。
  if (!api_.Load()) {
    result->Error("E_BACKEND_UNAVAILABLE",
                  "mpv-2.dll 加载失败（D28 分发缺失），libmpv 不可用", nullptr);
    return;
  }

  // 复用句柄时先释放旧实例。
  ShutdownMpv();

  const bool is_live = GetBool(*map, "isLive", false);
  if (!InitializeMpv(is_live)) {
    result->Error("E_BACKEND_UNAVAILABLE", "libmpv 初始化失败", nullptr);
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
    result->Error("E_OPEN", "loadfile 命令失败", nullptr);
    return;
  }

  EmitState("opening");
  result->Success(nullptr);
}

void PlayerPlugin::Play(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (mpv_ != nullptr) {
    const int flag = 0;  // pause=false
    api_.set_property(mpv_, "pause", MPV_FORMAT_FLAG, &flag);
  }
  result->Success(nullptr);
}

void PlayerPlugin::Pause(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (mpv_ != nullptr) {
    const int flag = 1;  // pause=true
    api_.set_property(mpv_, "pause", MPV_FORMAT_FLAG, &flag);
  }
  result->Success(nullptr);
}

void PlayerPlugin::SeekTo(
    const flutter::EncodableValue* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (mpv_ == nullptr) {
    result->Success(nullptr);
    return;
  }
  int64_t position_ms = 0;
  if (args != nullptr) {
    const flutter::EncodableValue::Type type = args->Type();
    if (type == flutter::EncodableValue::Type::kInt32) {
      position_ms = std::get<int32_t>(*args);
    } else if (type == flutter::EncodableValue::Type::kInt64) {
      position_ms = std::get<int64_t>(*args);
    } else {
      result->Error("E_BAD_ARGUMENT", "seekTo 需毫秒整数", nullptr);
      return;
    }
  }
  const double seconds = static_cast<double>(position_ms) / 1000.0;
  api_.set_property(mpv_, "time-pos", MPV_FORMAT_DOUBLE, &seconds);
  result->Success(nullptr);
}

void PlayerPlugin::SetVolume(
    const flutter::EncodableValue* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (args == nullptr ||
      args->Type() != flutter::EncodableValue::Type::kDouble) {
    result->Error("E_BAD_ARGUMENT", "setVolume 需浮点数", nullptr);
    return;
  }
  const double volume = std::get<double>(*args);
  if (mpv_ != nullptr) {
    const double clamped = (volume < 0.0) ? 0.0 : ((volume > 1.0) ? 1.0 : volume);
    const double mpv_volume = clamped * 100.0;  // mpv 音量域 0~100
    api_.set_property(mpv_, "volume", MPV_FORMAT_DOUBLE, &mpv_volume);
  }
  result->Success(nullptr);
}

void PlayerPlugin::SetSpeed(
    const flutter::EncodableValue* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (args == nullptr ||
      args->Type() != flutter::EncodableValue::Type::kDouble) {
    result->Error("E_BAD_ARGUMENT", "setSpeed 需浮点数", nullptr);
    return;
  }
  const double speed = std::get<double>(*args);
  if (mpv_ != nullptr) {
    const double clamped = (speed < 0.25) ? 0.25 : ((speed > 4.0) ? 4.0 : speed);
    api_.set_property(mpv_, "speed", MPV_FORMAT_DOUBLE, &clamped);
  }
  result->Success(nullptr);
}

void PlayerPlugin::Dispose(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  ShutdownMpv();
  result->Success(nullptr);
}

// ─────────────── libmpv 生命周期 ───────────────

bool PlayerPlugin::InitializeMpv(bool auto_play) {
  mpv_handle* handle = api_.create();
  if (handle == nullptr) {
    return false;
  }
  // 控制面语义：无窗口承载（视频纹理输出层为后续渲染任务，见文件头注释）。
  // 注意：vo 属「初始化前生效」选项，必须早于 mpv_initialize 设置，
  // 否则默认 vo 会在 Windows 弹出独立 mpv 渲染窗口，破坏无窗口控制面契约。
  api_.set_option_string(handle, "vo", "null");
  if (api_.initialize(handle) < 0) {
    api_.terminate_destroy(handle);
    return false;
  }
  mpv_ = handle;

  // 直播流（isLive）open 后自动起播，对齐 Android ExoPlayer 行为；点播保持暂停待 play()。
  const int pause = auto_play ? 0 : 1;
  api_.set_property(mpv_, "pause", MPV_FORMAT_FLAG, &pause);

  // 事件面：进度 / 状态由属性变更驱动。
  api_.observe_property(mpv_, 0, "time-pos", MPV_FORMAT_DOUBLE);
  api_.observe_property(mpv_, 0, "duration", MPV_FORMAT_DOUBLE);
  api_.observe_property(mpv_, 0, "pause", MPV_FORMAT_FLAG);
  api_.observe_property(mpv_, 0, "paused-for-cache", MPV_FORMAT_FLAG);
  api_.observe_property(mpv_, 0, "demuxer-cache-time", MPV_FORMAT_DOUBLE);

  running_ = true;
  event_thread_ =
      std::make_unique<std::thread>(&PlayerPlugin::RunEventLoop, this);
  return true;
}

void PlayerPlugin::ShutdownMpv() {
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

// ─────────────── 属性辅助 ───────────────

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

}  // namespace vbox
