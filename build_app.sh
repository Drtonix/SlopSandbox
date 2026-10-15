#!/bin/zsh
# SlopSandbox.app: собранная игра, значок и ничего лишнего — всё своё внутри.
set -e
cd "${0:A:h}"
APP="$PWD/build/SlopSandbox.app"
# SwiftUI-макросам нужен полный Xcode: с Command Line Tools сборка падает на @State.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

swift build -c release --arch arm64 --product SlopSandbox
BIN="$(swift build -c release --arch arm64 --show-bin-path)/SlopSandbox"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SlopSandbox"
cp icon/AppIcon.icns icon/Assets.car "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>SlopSandbox</string>
<key>CFBundleDisplayName</key><string>SlopSandbox</string>
<key>CFBundleExecutable</key><string>SlopSandbox</string>
<key>CFBundleIdentifier</key><string>space.bdub.slopsandbox</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.simulation-games</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>DrTonix · bdub.space</string>
</dict></plist>
PLIST
# Подпись без сертификата: иначе на Apple Silicon бинарник не запустится.
codesign --force --deep --sign - "$APP" >/dev/null
echo "готово: $(du -sh "$APP" | cut -f1) -> $APP"
