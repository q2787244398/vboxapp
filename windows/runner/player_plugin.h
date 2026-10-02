//
//  player_plugin.h
//  Runner
//
//  批次 C · C-11：Windows 播放器插件（libmpv 主后端）。
//
//  与 macOS `PlayerPlugin.swift` / Android `PlayerPlugin.kt` 共用同一 wire 协议
//  （Dart `ChannelPlayer._onEvent` 解析面）：
//    · MethodChannel `com.vbox.player/player`：open / play / pause / seekTo /
//      setVolume / setSpeed / dispose
//    · EventChannel `com.vbox.player/player/events`：state / progress / error
//
//  后端口径（D6）：Windows/macOS 主后端 libmpv。libmpv 运行时（mpv-2.dll）按
//  D28 分发决策随安装包同目录分发（不入 git，由 scripts/bundle-libmpv-windows.ps1
//  从 GitHub Release 资产拉取并改名 mpv-2.dll 拷入 runner 目录），插件运行期
//  LoadLibraryW + GetProcAddress 动态解析，构建期不依赖第三方导入库。
//
//  渲染口径：本插件为「控制面」实现（对齐 macOS AVPlayer / Android ExoPlayer
//  插件——wire 协议不携带纹理句柄），libmpv 以 vo=null 无窗口模式承载
//  open/play/pause/seek/volume/speed 控制与 state/progress/error 事件面；
//  视频纹理输出层（mpv_render_context + Flutter TextureRegistrar）属渲染层
//  后续任务（G-02-B 原生二进制分发后接入）。
//
//  事件面实现：专属事件线程轮询 mpv_wait_event，事件经 EventSink 上抛；
//  进度与状态由 mpv_observe_property 属性变更驱动（对齐契约 §2.5 能力矩阵）。

#ifndef RUNNER_PLAYER_PLUGIN_H_
#define RUNNER_PLAYER_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "libmpv/client.h"

namespace vbox {

// libmpv C API 函数指针表（mpv-2.dll 运行期动态解析）。
// 仅收录本插件用到的符号；签名与 libmpv/client.h 一一对应。
struct MpvApi {
  // 加载状态（首次 open 前尝试 LoadLibraryW）。
  bool loaded = false;

  // 句柄与生命周期。
  mpv_handle* (*create)(void) = nullptr;
  int (*initialize)(mpv_handle* ctx) = nullptr;
  void (*terminate_destroy)(mpv_handle* ctx) = nullptr;

  // 命令与选项。
  int (*command)(mpv_handle* ctx, const char** args) = nullptr;
  int (*set_option_string)(mpv_handle* ctx, const char* name,
                           const char* data) = nullptr;

  // 属性读写。
  int (*set_property)(mpv_handle* ctx, const char* name, mpv_format format,
                      void* data) = nullptr;
  int (*get_property)(mpv_handle* ctx, const char* name, mpv_format format,
                      void* data) = nullptr;

  // 事件面。
  int (*observe_property)(mpv_handle* ctx, uint64_t reply_userdata,
                          const char* name, mpv_format format) = nullptr;
  int (*unobserve_property)(mpv_handle* ctx,
                            uint64_t registered_reply_userdata) = nullptr;
  mpv_event* (*wait_event)(mpv_handle* ctx, double timeout) = nullptr;

  // 工具。
  const char* (*error_string)(int error) = nullptr;
  void (*free)(void* data) = nullptr;

  // 加载 mpv-2.dll 并解析全部符号；失败时 loaded=false。
  bool Load();
};

// Windows 播放器插件（libmpv 控制面，见文件头注释）。
class PlayerPlugin : public flutter::Plugin {
 public:
  // 手动注册入口（flutter_window.cpp OnCreate 调用，对齐 macOS
  // MainFlutterWindow 的 PlayerPlugin.register 模式）。
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit PlayerPlugin(flutter::PluginRegistrarWindows* registrar);
  virtual ~PlayerPlugin();

  PlayerPlugin(const PlayerPlugin&) = delete;
  PlayerPlugin& operator=(const PlayerPlugin&) = delete;

  // MethodChannel 分派入口（flutter::Plugin 无 HandleMethodCall 虚函数，
  // 由构造期 SetMethodCallHandler lambda 回调）。
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // ── 供 StreamHandler 调用的 sink 生命周期（事件线程安全） ──
  void SetSink(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);
  void ClearSink();

 private:
  // 事件流处理器（onListen/onCancel 挂接 sink）。
  class StreamHandler
      : public flutter::StreamHandler<flutter::EncodableValue> {
   public:
    explicit StreamHandler(PlayerPlugin* plugin) : plugin_(plugin) {}

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
    OnListenInternal(const flutter::EncodableValue* arguments,
                     std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                         events) override;

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
    OnCancelInternal(const flutter::EncodableValue* arguments) override;

   private:
    PlayerPlugin* plugin_;
  };

  // ── 通道 ──
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<StreamHandler> stream_handler_;
  std::mutex sink_mutex_;
  std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;

  // ── libmpv ──
  MpvApi api_;
  mpv_handle* mpv_ = nullptr;
  std::unique_ptr<std::thread> event_thread_;
  std::atomic<bool> running_{false};

  // ── 状态 ──
  std::string state_ = "idle";

  // ── 方法面 ──
  void Open(const flutter::EncodableValue* args,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                result);
  void Play(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                result);
  void Pause(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result);
  void SeekTo(const flutter::EncodableValue* args,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                  result);
  void SetVolume(
      const flutter::EncodableValue* args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetSpeed(const flutter::EncodableValue* args,
                std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                    result);
  void Dispose(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                   result);

  // ── libmpv 内部 ──
  bool InitializeMpv(bool auto_play);
  void ShutdownMpv();
  void RunEventLoop();
  void HandleMpvEvent(const mpv_event* event);

  // ── 事件面 ──
  std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> SinkSnapshot();
  void EmitState(const std::string& value);
  void EmitProgress();
  void EmitError(const std::string& message, bool fatal);

  // 读属性辅助（返回值 <0 表示不可用）。
  bool GetDoubleProperty(const char* name, double* out);
  bool GetFlagProperty(const char* name, int* out);
};

}  // namespace vbox

#endif  // RUNNER_PLAYER_PLUGIN_H_
