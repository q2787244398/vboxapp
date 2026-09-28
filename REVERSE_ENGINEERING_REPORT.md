# TVS - CatVod Video Player App: Reverse Engineering Report

## APK Analysis Summary

### Basic Info
- **Package**: com.example.tvs
- **App Name**: TVS
- **Version**: 1.2.1 (versionCode 4006)
- **Min SDK**: 24 (Android 7.0)
- **Target SDK**: 36 (Android 16)
- **Architecture**: x86_64

### Components
- **Activities**: MainActivity, ConfigCenterActivity, WebViewActivity
- **Services**: AudioService (audio playback)
- **Receivers**: MediaButtonReceiver, SharePlusPendingIntent, ProfileInstallReceiver

### Permissions
- WAKE_LOCK, INTERNET, ACCESS_NETWORK_STATE
- FOREGROUND_SERVICE, FOREGROUND_SERVICE_MEDIA_PLAYBACK
- REQUEST_INSTALL_PACKAGES

### Native Libraries
- libflutter.so - Flutter engine
- libnode.so - Node.js runtime
- libnode_bridge.so - Native bridge for Node.js
- libapp.so - Dart AOT compiled app code
- libisar.so - Isar database engine (Rust)
- libyl_player_ffmpeg.so - Video player with FFmpeg
- libfastdev_quickjs_runtime.so - QuickJS runtime for Dart↔JS bridge
- libc++_shared.so - C++ standard library

### Key Findings

1. **Flutter App with Node.js Integration**: The app uses Flutter for UI but embeds a full Node.js runtime for video source parsing (CatVod spider engine).

2. **CatVod Spider Architecture**: The Node.js engine loads spider bundles that scrape video sources from Chinese streaming sites (bilibili, quark, baidu, etc.).

3. **Native Bridge**: `NodeBridge.kt` manages starting/stopping the Node.js process and communicating via MethodChannel.

4. **Video Playback**: Uses `yl_player` (custom FFmpeg-based player) for video rendering.

5. **Database**: Uses Isar (embedded NoSQL database) for storing search history, favorites, and watch history.

6. **Audio**: Uses `audio_service` for background audio playback with media controls.

7. **DPAD Navigation**: `config-center-dpad.js` provides TV-optimized DPAD navigation for web views.

## Reconstructed Source Code

### Project Structure
```
tvs-rebuild/
├── android/                    # Android native code (Kotlin)
│   ├── build.gradle
│   ├── settings.gradle
│   └── app/
│       ├── build.gradle
│       ├── AndroidManifest.xml
│       └── src/main/kotlin/com/example/tvs/
│           ├── MainActivity.kt          # Main Flutter activity
│           ├── NodeBridge.kt            # Native Node.js bridge
│           ├── ConfigCenterActivity.kt  # Configuration center
│           └── UpdateFileProvider.kt     # APK update file provider
├── flutter/                     # Flutter Dart code
│   ├── pubspec.yaml
│   ├── assets/js/               # Node.js spider assets
│   │   ├── node-main-template.js
│   │   ├── node-intl-polyfill.js
│   │   └── config-center-dpad.js
│   └── lib/
│       ├── main.dart            # App entry point
│       ├── models/              # Data models
│       │   ├── models.dart      # Vod, VodSite, PlaySource, etc.
│       │   └── app_state.dart   # App state management
│       ├── routing/             # GoRouter configuration
│       │   └── router.dart      # Route definitions
│       ├── services/            # State management services
│       │   ├── node_service.dart    # Node.js API communication
│       │   ├── config_service.dart  # Configuration management
│       │   ├── database_service.dart # Isar database
│       │   ├── player_service.dart   # Video playback
│       │   └── audio_service.dart    # Audio playback
│       └── pages/               # Flutter pages
│           ├── home_page.dart
│           ├── search_page.dart
│           ├── player_page.dart
│           ├── detail_page.dart
│           ├── live_page.dart
│           ├── config_page.dart
│           ├── website_page.dart
│           ├── audio_player_page.dart
│           ├── node_debug_page.dart
│           ├── settings_detail_page.dart
│           └── video_grid.dart
├── node/                        # Node.js spider engine
│   ├── package.json
│   └── spider/
│       ├── server.js            # HTTP API server
│       ├── spider.js            # Main spider bundle
│       └── template.js          # Spider bundle template
└── config/                      # Configuration files
    └── tvs-config.yaml          # App configuration
```

### Key Architecture Decisions

1. **Three-Layer Architecture**:
   - Flutter UI Layer (Dart) → Native Bridge (Kotlin) → Node.js Spider Engine

2. **Communication Protocol**:
   - Flutter ↔ Native: MethodChannel
   - Native ↔ Node.js: Process spawning + HTTP API
   - Flutter ↔ Node.js: HTTP REST API on localhost

3. **Data Flow**:
   - User searches → Flutter → Node.js HTTP API → Spider bundle → External sites → JSON → Flutter → UI

4. **State Management**:
   - Provider package for state management
   - ChangeNotifier for reactive UI updates

5. **Routing**:
   - GoRouter for declarative routing with shell routes for bottom navigation

## How to Build

### Android Build
1. Place files in `android/` directory
2. Add Flutter embedding dependency
3. Build with `./gradlew assembleRelease`

### Flutter Build
1. Place files in `flutter/` directory
2. Run `flutter pub get`
3. Run `flutter build appbundle`

### Node.js Engine
1. Place files in `node/` directory
2. Run `npm install`
3. Start with `node spider/server.js`

## Limitations

This is a **reconstructed source code** based on reverse engineering the APK. The actual implementation may differ in:
- Exact API endpoints and parameters
- Spider bundle implementation details
- UI/UX design specifics
- Platform channel method names
- Database schema details

The code provides a working architecture that matches the original app's behavior but may need adjustments for exact compatibility.