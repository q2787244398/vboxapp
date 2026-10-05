//
//  player_plugin.h
//  Runner
//
//  批次 C · C-11：Windows 播放器插件（libmpv 主后端）。
//  Wave A · R-渲1：补视频纹理输出面（mpv_render_context SW + Flutter TextureRegistrar）。
//
//  与 macOS `PlayerPlugin.swift` / Android `PlayerPlugin.kt` 共用同一 wire 协议
//  （Dart `ChannelPlayer._onEvent` 解析面）：
//    · MethodChannel `com.vbox.player/player`：open / play / pause / seekTo /
//      setVolume / setSpeed / dispose
//    · EventChannel `com.vbox.player/player/events`：state / progress / videoSize / error
//
//  后端口径（D6）：Windows/macOS 主后端 libmpv。libmpv 运行时（mpv-2.dll）按
//  D28 分发决策随安装包同目录分发（不入 git，由 scripts/bundle-libmpv-windows.ps1
//  从 GitHub Release 资产拉取并改名 mpv-2.dll 拷入 runner 目录），插件运行期
//  LoadLibraryW + GetProcAddress 动态解析，构建期不依赖第三方导入库。
//
//  渲染口径（R-渲1）：`vo=libmpv`（render API 前置）+ `mpv_render_context`（SW
//  后端，`MPV_RENDER_API_TYPE_SW`）把每帧软渲染为 BGRA 像素，经 Flutter
//  `TextureRegistrar`（[PixelBufferTexture]）上屏；`open` 返回 `textureId` 交
//  Dart `Texture(textureId:)` 承载。视频尺寸经 `videoSize` 事件上报，Dart 侧按
//  纵横比自适应（对齐 iOS `videoGravity = .resizeAspect`）。
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
#include <flutter/texture_registrar.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "libmpv/client.h"

namespace vbox {

// ─────────────── libmpv render API（SW 后端）───────────────
//
// `libmpv/render.h` 未随仓库分发（仅 client.h），此处按 mpv ABI 手动声明本插件
// 用到的 SW 渲染子集；枚举值与 mpv 官方 render.h 一一对应（0~20），不得改动顺序。
struct mpv_render_context;
typedef void (*mpv_render_update_fn)(void* callback_ctx);
typedef uint64_t mpv_render_update_flag;

enum mpv_render_param_type {
  MPV_RENDER_PARAM_INVALID = 0,
  MPV_RENDER_PARAM_API_TYPE = 1,
  MPV_RENDER_PARAM_OPENGL_INIT_PARAMS = 2,
  MPV_RENDER_PARAM_OPENGL_FBO = 3,
  MPV_RENDER_PARAM_FLIP_Y = 4,
  MPV_RENDER_PARAM_DEPTH = 5,
  MPV_RENDER_PARAM_ICC_PROFILE = 6,
  MPV_RENDER_PARAM_AMBIENT_LIGHT = 7,
  MPV_RENDER_PARAM_X11_DISPLAY = 8,
  MPV_RENDER_PARAM_WL_DISPLAY = 9,
  MPV_RENDER_PARAM_ADVANCED_CONTROL = 10,
  MPV_RENDER_PARAM_NEXT_FRAME_INFO = 11,
  MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 12,
  MPV_RENDER_PARAM_SKIP_RENDERING = 13,
  MPV_RENDER_PARAM_DRM_DISPLAY = 14,
  MPV_RENDER_PARAM_DRM_DRAW_SURFACE_SIZE = 15,
  MPV_RENDER_PARAM_DRM_DISPLAY_V2 = 16,
  MPV_RENDER_PARAM_SW_SIZE = 17,
  MPV_RENDER_PARAM_SW_FORMAT = 18,
  MPV_RENDER_PARAM_SW_STRIDE = 19,
  MPV_RENDER_PARAM_SW_POINTER = 20,
};

struct mpv_render_param {
  enum mpv_render_param_type type;
  void* data;
};

// SW 渲染 api type 字符串（MPV_RENDER_API_TYPE_SW）。
constexpr const char* kRenderApiSw = "sw";
// mpv_render_context_update 返回标志：有新帧可渲染。
constexpr mpv_render_update_flag kRenderUpdateFrame = 1;

// libmpv C API 函数指针表（mpv-2.dll 运行期动态解析）。
// 仅收录本插件用到的符号；签名与 libmpv/client.h / render.h 一一对应。
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

  // ── render API（R-渲1；可选：旧 dll 缺失时为 nullptr → 无纹理输出）──
  int (*render_context_create)(mpv_render_context** res, mpv_handle* ctx,
                               mpv_render_param* params) = nullptr;
  int (*render_context_render)(mpv_render_context* ctx,
                               mpv_render_param* params) = nullptr;
  void (*render_context_set_update_callback)(mpv_render_context* ctx,
                                             mpv_render_update_fn callback,
                                             void* callback_ctx) = nullptr;
  mpv_render_update_flag (*render_context_update)(mpv_render_context* ctx) =
      nullptr;
  void (*render_context_free)(mpv_render_context* ctx) = nullptr;

  // 加载 mpv-2.dll 并解析全部符号；失败时 loaded=false。
  bool Load();
};

// Windows 播放器插件（libmpv + 视频纹理输出面，见文件头注释）。
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

  // ── Flutter 纹理输出面（R-渲1）──
  flutter::TextureRegistrar* texture_registrar_ = nullptr;
  std::unique_ptr<flutter::TextureVariant> texture_;
  int64_t texture_id_ = -1;
  FlutterDesktopPixelBuffer pixel_buffer_{};
  std::mutex frame_mutex_;
  std::vector<uint8_t> frame_buffer_;  // BGRA8888（引擎读取的前缓冲）
  int frame_width_ = 0;
  int frame_height_ = 0;
  // 引擎是否正持有 [frame_buffer_]（CopyPixelBuffer 后至 release_callback 间）。
  // 置位期间渲染线程丢弃新帧，避免写坏引擎正在采样的缓冲。
  std::atomic<bool> frame_locked_{false};
  int last_video_width_ = 0;   // 上次上报的视频尺寸（去重）
  int last_video_height_ = 0;

  // ── libmpv ──
  MpvApi api_;
  mpv_handle* mpv_ = nullptr;
  mpv_render_context* render_ctx_ = nullptr;
  std::unique_ptr<std::thread> event_thread_;
  std::atomic<bool> running_{false};
  std::unique_ptr<std::thread> render_thread_;
  std::atomic<bool> render_running_{false};
  std::atomic<bool> render_requested_{false};
  std::mutex render_mutex_;
  std::condition_variable render_cv_;

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

  // ── 渲染输出面内部（R-渲1）──
  static void OnRenderUpdate(void* callback_ctx);
  static void OnPixelBufferReleased(void* release_context);
  bool SetupRenderContext();
  void RunRenderLoop();
  void RenderFrame();
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width, size_t height);
  void RegisterTexture();
  void UnregisterTexture();

  // ── 事件面 ──
  std::shared_ptr<flutter::EventSink<flutter::EncodableValue>> SinkSnapshot();
  void EmitState(const std::string& value);
  void EmitProgress();
  void EmitVideoSize(int width, int height);
  void EmitError(const std::string& message, bool fatal);

  // 读属性辅助（返回值 <0 表示不可用）。
  bool GetDoubleProperty(const char* name, double* out);
  bool GetFlagProperty(const char* name, int* out);
  bool GetInt64Property(const char* name, int64_t* out);
};

}  // namespace vbox

#endif  // RUNNER_PLAYER_PLUGIN_H_