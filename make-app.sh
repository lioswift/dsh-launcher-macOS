#!/bin/zsh
# ============================================================================
# make-app.sh —— 把任意脚本打包成可放进 Dock 的 .app
#
# 用法：
#   ./make-app.sh <目标.app路径> <脚本路径> [图标(.icns 或 .png)]
#
# 例：
#   ./make-app.sh "$HOME/Applications/dsh 启动器.app" ./dsh-launcher ~/Downloads/deep.png
#
# 生成的 app 要点（都是踩坑换来的）：
#   - LSUIElement=true：启动器本体随点随退，运行时不占 Dock（守卫跑在 app 外）
#   - 图标用 iconutil 生成标准 icns：Safari WebApp 的模板 icns 在普通 app 上会渲染空白
#   - 完成后自动 lsregister 刷新 LaunchServices
# ============================================================================
set -e

APP_PATH="$1"
SRC_SCRIPT="$2"
ICON_SRC="$3"

if [ -z "$APP_PATH" ] || [ -z "$SRC_SCRIPT" ]; then
  echo "用法: $0 <目标.app路径> <脚本路径> [图标(.icns 或 .png)]" >&2
  exit 1
fi
[ -f "$SRC_SCRIPT" ] || { echo "脚本不存在: $SRC_SCRIPT" >&2; exit 1; }

APP_NAME="$(basename "$APP_PATH" .app)"
EXEC_NAME="$(basename "$SRC_SCRIPT")"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

# ---------- 可执行脚本 ----------
cp -f "$SRC_SCRIPT" "$APP_PATH/Contents/MacOS/$EXEC_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$EXEC_NAME"

# ---------- Info.plist ----------
cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
  <key>CFBundleIdentifier</key><string>local.launcher.$RANDOM$RANDOM</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# ---------- 图标 ----------
if [ -n "$ICON_SRC" ] && [ -f "$ICON_SRC" ]; then
  case "$ICON_SRC" in
    *.icns)
      cp -f "$ICON_SRC" "$APP_PATH/Contents/Resources/ApplicationIcon.icns"
      ;;
    *.png)
      TMPDIR_ICONSET="$(mktemp -d)"
      ICONSET="$TMPDIR_ICONSET/AppIcon.iconset"
      mkdir -p "$ICONSET"
      for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
                  "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512"; do
        size=${spec%% *}; name=${spec##* }
        sips -z $size $size "$ICON_SRC" --out "$ICONSET/$name.png" >/dev/null 2>&1
      done
      cp -f "$ICON_SRC" "$ICONSET/icon_512x512@2x.png"
      iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/ApplicationIcon.icns"
      rm -rf "$TMPDIR_ICONSET"
      ;;
  esac
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ApplicationIcon" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
fi

# ---------- 刷新 LaunchServices ----------
touch "$APP_PATH"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH" 2>/dev/null || true

echo "✓ 已生成: $APP_PATH"
echo "  下一步: 把它拖进 Dock。"
