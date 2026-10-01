import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// G-09 P4：本地 release 构建签名。
// 密钥路径与密码只写在 android/key.properties（已被 .gitignore 排除，不入库、不进 CI）。
// 该文件不存在时（CI 环境）回退 debug 签名，由 build-release-assets.yml 用 apksigner 重签。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.vbox.player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.vbox.player"
        // D12：TV 最低版本锁定 Android 7.0 (API 24)，显式写死以免随 Flutter 默认值漂移。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // G-09 P4：有 key.properties 时使用固定 release keystore（本地发布构建），否则回退 debug。
    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // 批次 Q · Q-02：JSC 引擎原生模块（NDK + CMake）。
    // 编译 jsc/wrapper.c → libvbox_jsc.so（ABI 形状对齐 libvbox_quickjs 的 vq_*）。
    // 前置：scripts/fetch-jsc-android.sh 就位四 ABI libjsc.so（jniLibs，AGP 随 APK 打包）。
    // 构建的 ABI 由 Flutter 侧管理（--target-platform / split-per-abi），此处不设 abiFilters。
    externalNativeBuild {
        cmake {
            path = file("src/main/jni/CMakeLists.txt")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// G-02-A：播放器插件依赖（纯 Gradle 依赖，零 NDK）。
//   · androidx.media3: Media3 主后端（ExoPlayer + HLS）
//   · androidx.media3:media3-session: MediaSessionService 宿主（G-02-C 前台媒体服务）
//   · org.videolan.android:libvlc-all: libVLC 回退（aar 自带原生库，minSdk 21+；实现在 G-02-B/C）
dependencies {
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
    implementation("androidx.media3:media3-session:1.5.1")
    implementation("org.videolan.android:libvlc-all:3.6.0")
}

flutter {
    source = "../.."
}
