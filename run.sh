#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SilentHelper"
VERSION="10.0.0"
INSTALL_DIR="$HOME/Applications"
APP_BUNDLE="${INSTALL_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
BRIDGE_BIN="/tmp/sh_terminal_bridge"

echo "--------------------------------------------------------"
echo "  ${APP_NAME} v${VERSION} — Auto-Bridge & Drive Telemetry"
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

mkdir -p "$DEFAULT_ARCHIVE/FlightLogs"
mkdir -p "/tmp/sh_v10_ipc"

pkill -f "sh_terminal_bridge" >/dev/null 2>&1 || true
pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 || true

find "$HOME/Downloads" -name "${APP_NAME}.app" -type d -prune -exec rm -rf {} + 2>/dev/null || true
if [ -d "/Applications/${APP_NAME}.app" ] && [ ! -L "/Applications/${APP_NAME}.app" ]; then
    rm -rf "/Applications/${APP_NAME}.app" 2>/dev/null || true
fi

mkdir -p "$MACOS_DIR"

CERT_NAME="SilentHelper Dev"
SIGN_IDENTITY="-"
if command -v security >/dev/null 2>&1; then
    if ! security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
        TEMP_DIR=$(mktemp -d)
        openssl req -x509 -newkey rsa:2048 -days 3650 \
            -keyout "${TEMP_DIR}/dev.key" -out "${TEMP_DIR}/dev.crt" -nodes \
            -subj "/CN=${CERT_NAME}" \
            -addext "keyUsage=critical,digitalSignature" \
            -addext "extendedKeyUsage=codeSigning" 2>/dev/null || true

        openssl pkcs12 -export -legacy \
            -in "${TEMP_DIR}/dev.crt" -inkey "${TEMP_DIR}/dev.key" \
            -out "${TEMP_DIR}/dev.p12" -password pass:silenthelper 2>/dev/null || \
        openssl pkcs12 -export \
            -in "${TEMP_DIR}/dev.crt" -inkey "${TEMP_DIR}/dev.key" \
            -out "${TEMP_DIR}/dev.p12" -password pass:silenthelper 2>/dev/null || true

        if [ -f "${TEMP_DIR}/dev.p12" ]; then
            KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
            [ ! -f "$KEYCHAIN" ] && KEYCHAIN="$HOME/Library/Keychains/login.keychain"
            security import "${TEMP_DIR}/dev.p12" -k "$KEYCHAIN" -P silenthelper -T /usr/bin/codesign >/dev/null 2>&1 || true
            security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "${TEMP_DIR}/dev.crt" >/dev/null 2>&1 || true
        fi
        rm -rf "${TEMP_DIR}"
    fi

    if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
        SIGN_IDENTITY="$CERT_NAME"
    fi
fi

CURRENT_HASH=$(shasum -a 256 main.swift | awk '{print $1}')
SAVED_HASH=""
if [ -f "${CONTENTS_DIR}/source.sha256" ]; then
    SAVED_HASH=$(cat "${CONTENTS_DIR}/source.sha256" || true)
fi

if [ ! -f "${MACOS_DIR}/${APP_NAME}" ] || [ "$CURRENT_HASH" != "$SAVED_HASH" ]; then
    echo "[*] ${APP_NAME}.app (v${VERSION}) yig'ilmoqda (CDHash doimiy saqlanadi)..."

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
    <key>NSScreenCaptureUsageDescription</key>
    <string>SilentHelper savollarni tahlil qilish uchun ekrandan xavfsiz skrinshot oladi.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>SilentHelper kursorni siljitish va klavishlarni kuzatish uchun ruxsat ishlatadi.</string>
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
    xattr -cr "${APP_BUNDLE}" >/dev/null 2>&1 || true

    if [ "$SIGN_IDENTITY" != "-" ]; then
        codesign --force --deep --sign "$SIGN_IDENTITY" \
            -r='designated => identifier "com.local.SilentHelper"' \
            --identifier "com.local.${APP_NAME}" "${APP_BUNDLE}" >/dev/null 2>&1 || \
        codesign --force --deep --sign - --identifier "com.local.${APP_NAME}" "${APP_BUNDLE}" >/dev/null 2>&1 || true
    else
        codesign --force --deep --sign - --identifier "com.local.${APP_NAME}" "${APP_BUNDLE}" >/dev/null 2>&1 || true
    fi

    echo "$CURRENT_HASH" > "${CONTENTS_DIR}/source.sha256"
else
    echo "[+] Mavjud imzolangan ${APP_NAME}.app topildi (qayta imzolanmadi, ruxsat saqlanadi)."
fi

if [ -w "/Applications" ] && [ ! -e "/Applications/${APP_NAME}.app" ]; then
    ln -sf "${APP_BUNDLE}" "/Applications/${APP_NAME}.app" 2>/dev/null || true
fi

cp -f "${MACOS_DIR}/${APP_NAME}" "$BRIDGE_BIN"
chmod +x "$BRIDGE_BIN"
xattr -cr "$BRIDGE_BIN" >/dev/null 2>&1 || true

nohup "$BRIDGE_BIN" --bridge-daemon >/dev/null 2>&1 &
BRIDGE_PID=$!

echo "[+] Terminal Ruxsat Ko'prigi (Bridge PID: ${BRIDGE_PID}) ishga tushdi!"
echo "[+] Google Email sessiyasi (com.local.SilentHelper) saqlangan!"
echo "[+] Google Drive Avto-Telemetriya fayllari:"
echo "    1) ${DEFAULT_ARCHIVE}/FlightLogs/SILENTHELPER_TELEMETRY_LATEST.md"
echo "    2) ${DEFAULT_ARCHIVE}/FlightLogs/practice_session_report.md"
echo "    3) ${DEFAULT_ARCHIVE}/FlightLogs/flight_recorder_log.jsonl"
echo ""
echo "v10.0 BOSHQARUV:"
echo "  • [S -> F] yoki [Option + F] yoki Chap-Tepa Burchak -> Skrinshot + AI"
echo "  • [K] yoki [Option + K] yoki Chap-Past Burchak -> G / IW / SW / W / Javob (A, B, C, D)"
echo "  • [Option + L] (⌥L) -> Amaliyot payti xato yoki blok bo'lsa, lahzani skrinshoti bilan muhrlash"
echo "  • [Option + M] (⌥M) -> Boshqaruv Panelini ochish / yashirish"
echo "--------------------------------------------------------"

exec "${MACOS_DIR}/${APP_NAME}"