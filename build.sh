#!/bin/bash
# Builds "YT Music.app" next to this script.
#   ./build.sh            → release build
#   ./build.sh --install  → also copies it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="YTMusicMac"            # SwiftPM product / executable name
DISPLAY_NAME="YT Music"      # name shown in Finder, Dock and the menu bar
BUNDLE_ID="io.github.demir1283.ytmusic"
APP="$DISPLAY_NAME.app"
VERSION="2.1.0"              # shown in "About YT Music"
BUILD_NUMBER="2"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift bulunamadı. Önce şunu çalıştır:  xcode-select --install" >&2
  exit 1
fi

# Start clean if the toolchain changed since the last build.
TOOLCHAIN="$(xcrun --find swift 2>/dev/null || command -v swift)"
if [ -d .build ] && [ "$(cat .build/.toolchain 2>/dev/null)" != "$TOOLCHAIN" ]; then
  echo "▸ Derleyici değişti, eski derleme önbelleği temizleniyor…"
  rm -rf .build
fi

echo "▸ Derleniyor (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
echo "$TOOLCHAIN" > .build/.toolchain

echo "▸ $APP paketleniyor…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# With only the Command Line Tools, SwiftPM records the *deployment target* as the SDK
# version in the binary (e.g. "sdk 14.0"). macOS then runs the app in compatibility
# mode — no Liquid Glass sidebar/toolbar. Stamp the real SDK version so the system
# gives the app the current design.
SDK_VER="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
if [ -n "$SDK_VER" ] && xcrun --find vtool >/dev/null 2>&1; then
  echo "▸ SDK sürümü işleniyor (macOS $SDK_VER tasarımı)…"
  xcrun vtool -set-build-version macos 14.0 "$SDK_VER" -replace \
    -output "$APP/Contents/MacOS/$APP_NAME.tmp" "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null \
    && mv "$APP/Contents/MacOS/$APP_NAME.tmp" "$APP/Contents/MacOS/$APP_NAME" \
    || echo "  (uyarı: SDK sürümü işlenemedi, uygulama eski görünümle açılabilir)"
fi

# Stream-URL challenge solver (yt-dlp-ejs), loaded at run time.
if [ -d Resources/ejs ]; then
  mkdir -p "$APP/Contents/Resources/ejs"
  cp Resources/ejs/* "$APP/Contents/Resources/ejs/"
else
  echo "  (uyarı: Resources/ejs bulunamadı — Premium kalite için gerekli)"
fi

# App icon
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Localizations: with these, macOS shows its own menus (Edit, View, Window, Help, Hide,
# Quit…) in the system language instead of English.
for LANG_DIR in en tr; do
  mkdir -p "$APP/Contents/Resources/$LANG_DIR.lproj"
  printf '"CFBundleDisplayName" = "%s";\n"CFBundleName" = "%s";\n' "$DISPLAY_NAME" "$DISPLAY_NAME" \
    > "$APP/Contents/Resources/$LANG_DIR.lproj/InfoPlist.strings"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with YouTube or Google.</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
  <key>CFBundleAllowMixedLocalizations</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# The app keeps running when its window is closed; quit it so the new build is what opens.
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 1

echo "▸ İmzalanıyor (ad-hoc)…"
codesign --force --deep --sign - "$APP" >/dev/null

if [ "${1:-}" = "--install" ]; then
  echo "▸ /Applications içine kopyalanıyor…"
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  FINAL="/Applications/$APP"
else
  FINAL="$(pwd)/$APP"
fi

# macOS remembers an app's icon by its bundle id (Dock, menu-bar Now Playing…). Point
# Launch Services at this build only, and refresh the cached icon when it changed.
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREG" ]; then
  while IFS= read -r other; do
    [ -n "$other" ] && [ "$other" != "$FINAL" ] && [ -d "$other" ] || continue
    echo "  (eski kopya kaydı kaldırılıyor: $other)"
    "$LSREG" -u "$other" >/dev/null 2>&1 || true
  done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null)
  touch "$FINAL"
  "$LSREG" -f "$FINAL" >/dev/null 2>&1 || true
fi
ICON_SUM="$(md5 -q "$FINAL/Contents/Resources/AppIcon.icns" 2>/dev/null || true)"
if [ -n "$ICON_SUM" ] && [ "$(cat .build/.iconsum 2>/dev/null)" != "$ICON_SUM" ]; then
  echo "▸ Simge değişti, macOS simge önbelleği yenileniyor…"
  killall ControlCenter >/dev/null 2>&1 || true   # menu bar Now Playing (restarts itself)
  killall Dock >/dev/null 2>&1 || true
  echo "$ICON_SUM" > .build/.iconsum
fi

echo "✓ Hazır: $FINAL"
open "$FINAL"
