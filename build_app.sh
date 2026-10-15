#!/bin/bash
set -euo pipefail

# 构建「发票合并打印」.app（macOS 应用包）
ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-release}"
BUNDLE_NAME="发票合并打印"
EXEC_NAME="InvoicePrint"
BUNDLE="$ROOT/dist/$BUNDLE_NAME.app"

echo "==> 编译 ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/InvoicePrintApp"

if [ ! -f "$ROOT/Assets/AppIcon.icns" ]; then
  echo "==> 生成应用图标…"
  python3 "$ROOT/make_icon.py"
fi

echo "==> 组装 $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$EXEC_NAME"
cp "$ROOT/Assets/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>发票合并打印</string>
    <key>CFBundleDisplayName</key>
    <string>发票合并打印</string>
    <key>CFBundleExecutable</key>
    <string>InvoicePrint</string>
    <key>CFBundleIdentifier</key>
    <string>com.invoiceprint.app</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array><string>com.adobe.pdf</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.png</string>
                <string>public.jpeg</string>
                <string>public.tiff</string>
                <string>public.heic</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "APPL????" > "$BUNDLE/Contents/PkgInfo"

echo "==> 临时签名（ad-hoc）"
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || echo "  (codesign 跳过)"

echo "==> 完成: $BUNDLE"
echo "    运行: open \"$BUNDLE\""
