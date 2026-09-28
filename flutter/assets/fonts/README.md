# MaterialIcons-Regular.otf

The real OpenType binary has been restored from the extracted Flutter
runtime (`file` identifies it as OpenType font data).

If rebuilding from a clean extraction, the binary can be restored from the
Flutter SDK cache as described below.

## How to restore the font in a clean checkout

Option 1: From Flutter SDK cache (most common):
```bash
# After first `flutter pub get` in any project:
cp ~/.pub-cache/hosted/pub.dev/*/lib/fonts/MaterialIcons-Regular.otf \
   flutter/assets/fonts/MaterialIcons-Regular.otf
```

Option 2: From Google Fonts (direct):
```bash
curl -L -o flutter/assets/fonts/MaterialIcons-Regular.otf \
  "https://github.com/google/material-design-icons/raw/master/symbol"
```

Option 3: From the Flutter framework itself:
```bash
# On Linux
cp $FLUTTER_ROOT/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf \
   flutter/assets/fonts/MaterialIcons-Regular.otf
```

> **Note:** `uses-material-design: true` in pubspec.yaml already embeds the
> Material Icons font from the Flutter SDK at compile time. The explicit
> `assets/fonts/MaterialIcons-Regular.otf` entry in the fonts section is
> used when the app needs a *self-contained* copy (e.g., when the Flutter
> engine font resolver is not available, as in TV/embedded builds).
