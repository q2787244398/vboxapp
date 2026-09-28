// yl_player Windows plugin skeleton.
//
// Registers a Flutter texture surface and (in a full build) feeds it decoded
// frames from FFmpeg (YlFFmpegBridge equivalent). Pigeon method channel:
// dev.flutter.pigeon.yl_player
//
// This skeleton wires the channel and texture registration so the app compiles
// and runs on Windows; swap the decode callback for a real FFmpeg decoder.

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_message_codec.h>

#include <memory>
#include <string>
#include <vector>

namespace yl_player {

class YlPlayerPlugin : public flutter::Plugin {
 public:
  static YlPlayerPlugin* GetInstance() {
    static YlPlayerPlugin* s_instance = nullptr;
    if (!s_instance) s_instance = new YlPlayerPlugin();
    return s_instance;
  }

  void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    channel_ = std::make_shared<flutter::MethodChannel>(
        registrar->messenger(),
        "dev.flutter.pigeon.yl_player",
        const_cast<flutter::StandardMethodCodec*>(
            flutter::StandardMethodCodec::GetInstance()));
    registrar->AddMessageHandler(channel_);

    // Register a texture registry callback (FFmpeg decoder -> texture).
    texture_registrar_ = registrar->TextureRegistrar();
  }

  ~YlPlayerPlugin() {
    channel_->SetMessageHandler(nullptr);
    channel_.reset();
  }

 private:
  YlPlayerPlugin() {}

  void HandleMessage(const flutter::EncodableValue* message,
                     std::function<void(const flutter::EncodableValue*)> reply) {
    auto method = std::get<std::string>(message->value());
    // Host API surface (see Dart models for args shape).
    if (method == "load" || method == "play" || method == "pause" ||
        method == "stop" || method == "seekTo" || method == "seekToLiveEdge" ||
        method == "setVolume" || method == "setPlaybackSpeed" ||
        method == "selectAudioTrack" || method == "attach" ||
        method == "dispose") {
      // TODO(ffmpeg): drive the decode/render pipeline here.
      reply(flutter::EncodableValue(true));
      return;
    }
    if (method == "assess") {
      reply(flutter::EncodableValue(
          flutter::EncodableMap{{flutter::EncodableValue("tracks"),
                                 flutter::EncodableValue(flutter::EncodableValue())}}));
      return;
    }
    reply(nullptr);
  }

  std::shared_ptr<flutter::MethodChannel<>> channel_;
  flutter::TextureRegistrar* texture_registrar_ = nullptr;
};

void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  YlPlayerPlugin::GetInstance()->RegisterWithRegistrar(registrar);
}

}  // namespace yl_player

// C-ABI entry point consumed by the Flutter Windows plugin registrar.
// The CMake build must export this symbol from the plugin dll.
extern "C" {

__declspec(dllexport)
void GetYlPlayerPluginHandle(
    const flutter::PluginRegistrarWindows* registrar) {
  YlPlayerPlugin::GetInstance()->RegisterWithRegistrar(
      const_cast<flutter::PluginRegistrarWindows*>(registrar));
}

}  // extern "C"
