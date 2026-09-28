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
