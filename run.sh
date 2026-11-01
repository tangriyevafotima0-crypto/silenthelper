#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SilentHelper"
VERSION="7.0.0"
BUILD_DIR="./build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "--------------------------------------------------------"
echo "  ${APP_NAME} v${VERSION} — Deep Audited & Optimized Runner"
echo "--------------------------------------------------------"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "[!] swiftc topilmadi. Xcode Command Line Tools o'rnatilmoqda..."
    xcode-select --install || true
    echo "[!] O'rnatish tugagach, ./run.sh ni qayta ishga tushiring."
    exit 1
fi

DEFAULT_ARCHIVE="$HOME/QuizArchive"
if [ -d "$HOME/Library/CloudStorage" ]; then
    GDRIVE_DIR=$(find "$HOME/Library/CloudStorage" -maxdepth 1 -name "GoogleDrive-*" | head -n 1 || true)
    if [ -n "$GDRIVE_DIR" ] && [ -d "$GDRIVE_DIR/My Drive" ]; then
        DEFAULT_ARCHIVE="$GDRIVE_DIR/My Drive/QuizArchive"
    fi
elif [ -d "$HOME/Google Drive/My Drive" ]; then
    DEFAULT_ARCHIVE="$HOME/Google Drive/My Drive/QuizArchive"
fi

mkdir -p "$DEFAULT_ARCHIVE"
mkdir -p "$MACOS_DIR"

echo "[*] ${APP_NAME}.app (v${VERSION}) kompilyatsiya qilinmoqda..."

cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

swiftc -O main.swift \
    -framework Cocoa \
    -framework SwiftUI \
    -framework WebKit \
    -framework Vision \
    -framework ScreenCaptureKit \
    -framework CoreGraphics \
    -framework Carbon \
    -framework CryptoKit \
    -o "${MACOS_DIR}/${APP_NAME}"

chmod +x "${MACOS_DIR}/${APP_NAME}"
codesign --force --deep --sign - --identifier "com.local.${APP_NAME}" "${APP_BUNDLE}" >/dev/null 2>&1 || true

echo "[+] Muvaffaqiyatli yig'ildi (v${VERSION}): ${APP_BUNDLE}"
echo ""
echo "v7.0 OPTIMIZATSIYALANGAN BOSHQARUV:"
echo "  1) Ikki Bosqichli Dinamik Carbon [S -> F] (650ms qurollanish) yoki [Option + F]"
echo "  2) Sichqoncha Burchak Kamuflyaji (Gisterezis bilan):"
echo "     - CHAP-TEPA burchak (0.40s) -> Smart-Cropped Skrinshot + AI"
echo "     - CHAP-PAST burchak -> Javob ('A' yoki 'A̲ B') ko'rinadi"
echo "  3) [K] yoki [Option + K] -> Javobni ko'rsatish / yashirish (4.5s avto-yopilish)"
echo "  4) [Option + M] -> Boshqaruv Panelini ochish / yopish"
echo "--------------------------------------------------------"

exec "${MACOS_DIR}/${APP_NAME}"