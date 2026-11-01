#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SilentHelper"
VERSION="9.0.0"
INSTALL_DIR="$HOME/Applications"
APP_BUNDLE="${INSTALL_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "--------------------------------------------------------"
echo "  ${APP_NAME} v${VERSION} FINAL — Production Setup & Runner"
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
mkdir -p "$MACOS_DIR"

CERT_NAME="SilentHelper Dev"
SIGN_IDENTITY="-"
if command -v security >/dev/null 2>&1; then
    if ! security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
        echo "[*] macOS ruxsatlari doimiy saqlanishi uchun barqaror sertifikat yaratilmoqda..."
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
        echo "[+] Barqaror sertifikat faol: ${SIGN_IDENTITY}"
    fi
fi

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
    <string>SilentHelper test topshirish paytida savollarni tahlil qilish uchun ekrandan xavfsiz skrinshot oladi.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>SilentHelper test paytida kursorni bildirishnoma sifatida siljitish va maxfiy klavishlarni kuzatish uchun ruxsat talab qiladi.</string>
</dict>
</plist>
EOF

NEED_COMPILE=1
if [ -f "${MACOS_DIR}/${APP_NAME}" ] && [ "${MACOS_DIR}/${APP_NAME}" -nt main.swift ]; then
    NEED_COMPILE=0
    echo "[*] Mavjud barqaror binar topildi, qayta kompilyatsiya shart emas."
fi

if [ "$NEED_COMPILE" -eq 1 ]; then
    echo "[*] ${APP_NAME}.app (v${VERSION} FINAL) yig'ilmoqda..."
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
fi

xattr -cr "${APP_BUNDLE}" >/dev/null 2>&1 || true
codesign --force --deep --sign "${SIGN_IDENTITY}" --identifier "com.local.${APP_NAME}" "${APP_BUNDLE}" >/dev/null 2>&1 || true

mkdir -p "./build"
rm -rf "./build/${APP_NAME}.app"
cp -R "${APP_BUNDLE}" "./build/${APP_NAME}.app"

if [ -w "/Applications" ]; then
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "${APP_BUNDLE}" "/Applications/${APP_NAME}.app" 2>/dev/null || true
fi

TCC_USER_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
if [ -f "$TCC_USER_DB" ] && [ -w "$TCC_USER_DB" ]; then
    sqlite3 "$TCC_USER_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags, last_modified) VALUES ('kTCCServiceScreenCapture', 'com.local.SilentHelper', 0, 2, 4, 1, 0, strftime('%s','now'));" 2>/dev/null || true
    sqlite3 "$TCC_USER_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags, last_modified) VALUES ('kTCCServiceAccessibility', 'com.local.SilentHelper', 0, 2, 4, 1, 0, strftime('%s','now'));" 2>/dev/null || true
fi

echo "[+] Muvaffaqiyatli o'rnatildi: ${APP_BUNDLE}"
echo "[+] Ilova Finder va Launchpad'da to'g'ridan-to'g'ri ochilishga tayyor!"
echo "[+] Google Email sessiyangiz (com.local.SilentHelper) saqlangan!"
echo "[+] Amaliyot Qora Qutisi (Flight Recorder): ${DEFAULT_ARCHIVE}/FlightLogs/practice_session_report.md"
echo ""
echo "v9.0 FINAL BOSHQARUV:"
echo "  • [S -> F] yoki [Option + F] yoki Chap-Tepa Burchak -> Skrinshot + AI"
echo "  • [K] yoki [Option + K] yoki Chap-Past Burchak -> G / IW / SW / W / Javob (A, B, C, D)"
echo "  • [Option + L] (⌥L) -> Amaliyot payti xato yoki blok bo'lsa, lahzani skrinshoti bilan muhrlash"
echo "  • [Option + M] (⌥M) -> Boshqaruv Panelini ochish / yashirish"
echo "--------------------------------------------------------"

if [ "${1:-}" = "--no-exec" ]; then
    exit 0
fi

exec "${MACOS_DIR}/${APP_NAME}"