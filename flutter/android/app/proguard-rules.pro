# TVS app-specific R8/ProGuard rules.
# Keep Flutter embedding and platform channel entry points.
-keep class com.example.tvs.** extends android.app.Application { *; }
-keep class com.example.tvs.MainActivity { *; }
-keep class com.example.tvs.ConfigCenterActivity { *; }
-keep class com.example.tvs.NodeBridge { *; }
-keep class com.example.tvs.UpdateFileProvider { *; }

# Keep classes used by Flutter plugins through reflection.
-keep class io.flutter.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }

# Preserve native method names and channel callback signatures.
-keepclasseswithmembers,includedescriptorclasses class * {
    native <methods>;
}
-dontwarn org.jetbrains.annotations.**
-dontwarn javax.annotation.**

# Flutter 引擎内嵌了 Play Core 的 deferred components 支持
# （io.flutter.embedding.engine.deferredcomponents.PlayStoreDeferredComponentManager、
#  FlutterPlayStoreSplitApplication）。本项目未依赖 Play Core，R8 在 release
# 压缩阶段会把这些缺失引用判为错误并使 :app:minifyReleaseWithR8 失败。
-dontwarn com.google.android.play.core.**
