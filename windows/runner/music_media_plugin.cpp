//
//  music_media_plugin.cpp
//  Runner
//
//  批次 D · D3：Windows SMTC 媒体会话实现（见 music_media_plugin.h）。
//
//  C++/WinRT：Windows SDK 自带 cppwinrt 头（%WindowsSdkDir%Include\<ver>\cppwinrt），
//  仅本翻译单元 include，头文件保持 winrt-free（PIMPL）。
//  ISystemMediaTransportControlsInterop 未随 cppwinrt 生成，按 SDK idl 手动声明
//  （GUID 见 media.idl）。
//

#include "music_media_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <map>

namespace winrt {
using namespace Windows::Foundation;
using namespace Windows::Media;
}  // namespace winrt

namespace vbox {
namespace {

// SDK media.idl：ISystemMediaTransportControlsInterop。
struct __declspec(uuid("0a7e0e3e-7795-4f04-9c57-a83c7f0df82a"))
    ISystemMediaTransportControlsInterop : ::IInspectable {
  virtual HRESULT STDMETHODCALLTYPE GetForWindow(HWND appWindow, REFIID riid,
                                                 void** result) = 0;
};

flutter::EncodableMap CommandMap(const std::string& command, int position_ms) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("command")] = flutter::EncodableValue(command);
  if (position_ms >= 0) {
    map[flutter::EncodableValue("positionMs")] =
        flutter::EncodableValue(static_cast<int64_t>(position_ms));
  }
  return map;
}

const std::string GetString(const flutter::EncodableMap& map,
                            const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return {};
  const auto* s = std::get_if<std::string>(&it->second);
  return s != nullptr ? *s : std::string();
}

int64_t GetInt(const flutter::EncodableMap& map, const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  const auto* n = std::get_if<int64_t>(&it->second);
  return n != nullptr ? *n : 0;
}

bool GetBool(const flutter::EncodableMap& map, const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return false;
  const auto* b = std::get_if<bool>(&it->second);
  return b != nullptr && *b;
}

}  // namespace

// ─────────────── SMTC 状态体 ───────────────

// 事件 token：插件销毁时 revoke，避免悬垂回调。
struct SmtcState {
  winrt::SystemMediaTransportControls controls{nullptr};
  winrt::event_token button_token{};
  winrt::event_token position_token{};
  bool has_button_token = false;
  bool has_position_token = false;
};

// ─────────────── EventChannel StreamHandler（与 FloatingPlugin 同模式）───────

namespace {

class SinkStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit SinkStreamHandler(MusicMediaPlugin* plugin) : plugin_(plugin) {}

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue*,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
      override {
    // 事件回调来自 SMTC 线程：以 shared_ptr 快照持有（player_plugin 同模式）。
    plugin_->SetSink(std::move(events));
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue*) override {
    plugin_->ClearSink();
    return nullptr;
  }

 private:
  MusicMediaPlugin* plugin_;
};

}  // namespace

// ─────────────── 注册 ───────────────

void MusicMediaPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar, HWND owner) {
  auto plugin = std::make_unique<MusicMediaPlugin>(registrar, owner);
  auto* raw = plugin.get();
  raw->channel_->SetMethodCallHandler(
      [raw](const auto& call, auto result) {
        raw->HandleMethodCall(call, std::move(result));
      });
  raw->events_->SetStreamHandler(std::make_unique<SinkStreamHandler>(raw));
  registrar->AddPlugin(std::move(plugin));
}

// ─────────────── sink 管理（player_plugin 同模式，mutex 全保护）───────

void MusicMediaPlugin::SetSink(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  sink_ =
      std::shared_ptr<flutter::EventSink<flutter::EncodableValue>>(sink.release());
}

void MusicMediaPlugin::ClearSink() {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  sink_.reset();
}

MusicMediaPlugin::MusicMediaPlugin(flutter::PluginRegistrarWindows* registrar,
                                   HWND owner)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.vbox.player/music_media",
          &flutter::StandardMethodCodec::GetInstance())),
      events_(std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.vbox.player/music_media/events",
          &flutter::StandardMethodCodec::GetInstance())),
      owner_(owner) {}

MusicMediaPlugin::~MusicMediaPlugin() { ReleaseSmtc(); }

// ─────────────── 方法面 ───────────────

void MusicMediaPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "update") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args != nullptr) {
      Update(*args);
      result->Success();
    } else {
      result->Error("E_PARAM", "update 缺少参数");
    }
    return;
  }
  if (call.method_name() == "clear") {
    Clear();
    result->Success();
    return;
  }
  result->NotImplemented();
}

void MusicMediaPlugin::EnsureSmtc() {
  if (smtc_ != nullptr || owner_ == nullptr) return;
  try {
    auto interop = winrt::get_activation_factory<
        winrt::SystemMediaTransportControls,
        ISystemMediaTransportControlsInterop>();
    auto state = std::make_unique<SmtcState>();
    winrt::check_hresult(interop->GetForWindow(
        owner_, winrt::guid_of<winrt::SystemMediaTransportControls>(),
        winrt::put_abi(state->controls)));
    if (!state->controls) return;

    state->controls.IsEnabled(true);
    state->controls.IsPlayEnabled(true);
    state->controls.IsPauseEnabled(true);
    state->controls.IsPlayPauseToggleEnabled(true);
    state->controls.IsNextEnabled(true);
    state->controls.IsPreviousEnabled(true);

    // 线控命令 → EventChannel 回派（SMTC 回调线程，sink 快照发送）。
    MusicMediaPlugin* self = this;
    state->button_token = state->controls.ButtonPressed([self](
        const winrt::SystemMediaTransportControls&,
        const winrt::SystemMediaTransportControlsButtonPressedEventArgs&
            args) {
      try {
        switch (args.Button()) {
          case winrt::SystemMediaTransportControlsButton::Play:
            self->EmitCommand("play");
            break;
          case winrt::SystemMediaTransportControlsButton::Pause:
            self->EmitCommand("pause");
            break;
          case winrt::SystemMediaTransportControlsButton::PlayPauseToggle:
            self->EmitCommand("toggle");
            break;
          case winrt::SystemMediaTransportControlsButton::Next:
            self->EmitCommand("next");
            break;
          case winrt::SystemMediaTransportControlsButton::Previous:
            self->EmitCommand("previous");
            break;
          default:
            break;
        }
      } catch (...) {
      }
    });
    state->has_button_token = true;

    // 进度条拖动 → seek（TimeSpan 100ns → ms）。
    state->position_token =
        state->controls.PlaybackPositionChangeRequested([self](
            const winrt::SystemMediaTransportControls&,
            const winrt::SystemMediaTransportControlsPositionChangedEventArgs&
                args) {
          try {
            const int64_t ms = args.RequestedPlaybackPosition().count() / 10000;
            self->EmitCommand("seek", static_cast<int>(ms));
          } catch (...) {
          }
        });
    state->has_position_token = true;

    smtc_ = std::move(state);
  } catch (...) {
    // SMTC 不可用（旧系统 / 窗口异常）：静默降级，D28 口径。
    smtc_ = nullptr;
  }
}

void MusicMediaPlugin::ReleaseSmtc() {
  if (smtc_ == nullptr) return;
  try {
    if (smtc_->has_button_token) {
      smtc_->controls.ButtonPressed(smtc_->button_token);
    }
    if (smtc_->has_position_token) {
      smtc_->controls.PlaybackPositionChangeRequested(smtc_->position_token);
    }
    smtc_->controls.IsEnabled(false);
  } catch (...) {
  }
  smtc_ = nullptr;
}

void MusicMediaPlugin::Update(const flutter::EncodableMap& args) {
  EnsureSmtc();
  if (smtc_ == nullptr) return;
  try {
    auto& controls = smtc_->controls;

    // 播放状态（对齐 iOS MPNowPlayingInfoCenter + playbackState）。
    controls.PlaybackStatus(GetBool(args, "playing")
                                ? winrt::MediaPlaybackStatus::Playing
                                : winrt::MediaPlaybackStatus::Paused);

    // 元数据（title / artist / album）。
    auto updater = controls.DisplayUpdater();
    updater.Type(winrt::MediaPlaybackType::Music);
    auto properties = updater.MusicProperties();
    properties.Title(winrt::to_hstring(GetString(args, "title")));
    properties.Artist(winrt::to_hstring(GetString(args, "artist")));
    properties.AlbumTitle(winrt::to_hstring(GetString(args, "album")));
    updater.Update();

    // 时间线（进度 / 时长；TimeSpan 100ns 单位）。
    winrt::SystemMediaTransportControlsTimelineProperties timeline;
    timeline.StartTime(winrt::TimeSpan{0});
    timeline.MinTime(winrt::TimeSpan{0});
    timeline.EndTime(
        winrt::TimeSpan{std::max<int64_t>(GetInt(args, "durationMs"), 0) *
                        10000});
    timeline.MaxTime(timeline.EndTime());
    timeline.Position(
        winrt::TimeSpan{std::max<int64_t>(GetInt(args, "positionMs"), 0) *
                        10000});
    timeline.PlaybackRate(1.0);
    controls.UpdateTimelineProperties(timeline);

    // 封面：URL 异步加载（失败静默；WinRT 对象引用计数，插件销毁后仍安全）。
    const std::string cover = GetString(args, "coverURL");
    if (!cover.empty()) {
      winrt::SystemMediaTransportControls controls_ref = controls;
      winrt::fire_and_forget([controls_ref, cover]() -> winrt::fire_and_forget {
        try {
          auto ref = winrt::Windows::Storage::Streams::
              RandomAccessStreamReference::CreateFromUri(
                  winrt::Uri(winrt::to_hstring(cover)));
          auto stream = co_await ref.OpenReadAsync();
          auto updater = controls_ref.DisplayUpdater();
          updater.Thumbnail(stream);
          updater.Update();
        } catch (...) {
        }
        co_return;
      }());
    }
  } catch (...) {
    // SMTC 更新失败不阻断播放编排。
  }
}

void MusicMediaPlugin::Clear() {
  if (smtc_ == nullptr) return;
  try {
    auto& controls = smtc_->controls;
    controls.PlaybackStatus(winrt::MediaPlaybackStatus::Closed);
    controls.IsPlayEnabled(false);
    controls.IsPauseEnabled(false);
    controls.IsPlayPauseToggleEnabled(false);
    controls.IsNextEnabled(false);
    controls.IsPreviousEnabled(false);
    auto updater = controls.DisplayUpdater();
    updater.ClearAll();
    updater.Update();
  } catch (...) {
  }
}

void MusicMediaPlugin::EmitCommand(const std::string& command,
                                   int position_ms) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (sink_ == nullptr) return;
  sink_->Success(flutter::EncodableValue(
      CommandMap(command, position_ms)));
}

}  // namespace vbox
