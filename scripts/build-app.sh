#!/usr/bin/env bash
# 把 layoutD 的 GUI(LayoutDApp) 打包成可双击的 macOS .app。
#
# 用法:
#   bash scripts/build-app.sh                 # 产出 ~/Desktop/LayoutD.app
#   bash scripts/build-app.sh path/to/icon.png   # 带图标(png 自动转 icns;也接受 .icns)
#
# 说明:
#   - 现在 swift build 产出的是裸命令行二进制;本脚本套上标准 .app 外壳 + Info.plist。
#   - 做 ad-hoc 代码签名(Apple Silicon 本机运行需要);**分发给别人**仍需开发者账号签名+公证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LayoutD"
BUNDLE_ID="com.layoutd.app"
VERSION="0.1.0"
BUILD="$(date +%Y%m%d)"
ICON_SRC="${1:-}"
OUT="$HOME/Desktop/${APP_NAME}.app"

echo "==> swift build -c release (首次较慢)"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/layoutD"
[ -f "$BIN" ] || { echo "✗ 找不到二进制: $BIN"; exit 1; }

echo "==> 组装 $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

cp "$BIN" "$OUT/Contents/MacOS/$APP_NAME"
chmod +x "$OUT/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$OUT/Contents/PkgInfo"

# ---- 图标(可选): png 经 sips/iconutil 转 icns ----
ICON_KEY=""
if [ -n "$ICON_SRC" ] && [ -f "$ICON_SRC" ]; then
  if [[ "$ICON_SRC" == *.icns ]]; then
    cp "$ICON_SRC" "$OUT/Contents/Resources/AppIcon.icns"
    ICON_KEY="AppIcon"
  elif [[ "$ICON_SRC" == *.png ]]; then
    echo "==> 由 PNG 生成 .icns"
    TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$TMP_ICONSET"
    for sz in 16 32 64 128 256 512; do
      sips -z $sz $sz       "$ICON_SRC" --out "$TMP_ICONSET/icon_${sz}x${sz}.png"   >/dev/null 2>&1 || true
      sips -z $((sz*2)) $((sz*2)) "$ICON_SRC" --out "$TMP_ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null 2>&1 || true
    done
    if iconutil -c icns "$TMP_ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns" 2>/dev/null; then
      ICON_KEY="AppIcon"
    else
      echo "  (icns 生成失败,跳过图标)"
    fi
  fi
fi

# ---- Info.plist ----
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>         <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>$( [ -n "$ICON_KEY" ] && printf '\n    <key>CFBundleIconFile</key>        <string>%s</string>' "$ICON_KEY" )
</dict>
</plist>
PLIST

# ---- ad-hoc 签名(Apple Silicon 本机运行需要) ----
echo "==> ad-hoc 代码签名"
codesign --force --deep --sign - "$OUT" 2>/dev/null && echo "  签名 OK" || echo "  (签名跳过/失败,本机仍可运行)"

echo ""
echo "✅ 完成: $OUT"
echo "   双击打开,或: open \"$OUT\""
echo "   分发给别人需开发者账号签名+公证(本地双击无需)。"
