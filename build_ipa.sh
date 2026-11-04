#!/bin/bash
# ---------------------------------------------------------------------------
# Hub 播放器 iOS 单机版 —— macOS + Xcode 一键出 IPA
# ---------------------------------------------------------------------------
# 用法（把整个 HubPlayer-iOS 目录拷到 Mac）：
#   bash build_ipa.sh
#
# 默认：不签名 Archive，直接打包成 HubPlayer-unsigned.ipa，
#       之后用 Sideloadly / AltStore 填自己的 Apple ID 现场重签安装。
# 可选：若你有证书与描述文件，设置环境变量后走签名导出：
#       TEAM_ID=XXXXXXXXXX PROFILE_NAME="My Profile" bash build_ipa.sh
#
# Windows 无法生成 IPA（必须 macOS + Xcode 工具链）。
# ---------------------------------------------------------------------------
set -e

PROJ="HubPlayer.xcodeproj"
SCHEME="HubPlayer"
CONFIG="Release"
ARCHIVE="./build/HubPlayer.xcarchive"
TEAM_ID="${TEAM_ID:-}"
PROFILE_NAME="${PROFILE_NAME:-}"
METHOD="${METHOD:-development}"

echo "[*] Archive（Release）…"
if [ -n "$TEAM_ID" ]; then
  xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration "$CONFIG" \
    -archivePath "$ARCHIVE" DEVELOPMENT_TEAM="$TEAM_ID" clean archive
else
  echo "    未设置 TEAM_ID → 不签名编译（产出未签名 IPA）"
  xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration "$CONFIG" \
    -archivePath "$ARCHIVE" CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO clean archive
fi

APP="$ARCHIVE/Products/Applications/HubPlayer.app"
if [ ! -d "$APP" ]; then
  echo "Archive 未产出 .app，请检查上方 xcodebuild 报错"
  exit 1
fi

rm -rf build/ipa
mkdir -p build/ipa

if [ -n "$TEAM_ID" ] && [ -n "$PROFILE_NAME" ]; then
  echo "[*] 导出已签名 IPA…"
  cat > build/ipa/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>signingStyle</key><string>manual</string>
  <key>method</key><string>$METHOD</string>
  <key>teamId</key><string>$TEAM_ID</string>
  <key>provisioningProfiles</key>
  <dict><key>com.hub.player</key><string>$PROFILE_NAME</string></dict>
  <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist build/ipa/ExportOptions.plist \
    -exportPath build/ipa
  OUT=$(ls build/ipa/*.ipa | head -1)
else
  echo "[*] 打包未签名 IPA…"
  mkdir -p build/ipa/Payload
  cp -R "$APP" build/ipa/Payload/
  (cd build/ipa && zip -qry HubPlayer-unsigned.ipa Payload)
  OUT="build/ipa/HubPlayer-unsigned.ipa"
fi

echo ""
echo "IPA 已生成：$OUT"
echo "   未签名包请用 Sideloadly / AltStore 自行重签安装。"
