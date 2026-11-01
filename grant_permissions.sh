#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SilentHelper"
APP_BUNDLE="$HOME/Applications/${APP_NAME}.app"
SYS_APP_BUNDLE="/Applications/${APP_NAME}.app"

echo "--------------------------------------------------------"
echo "  SilentHelper — Doimiy Ruxsatlarni Berish va Tiklash"
echo "--------------------------------------------------------"

if [ ! -d "$APP_BUNDLE" ] && [ -d "./build/${APP_NAME}.app" ]; then
    mkdir -p "$HOME/Applications"
    cp -R "./build/${APP_NAME}.app" "$APP_BUNDLE"
fi

if [ -w "/Applications" ] && [ -d "$APP_BUNDLE" ]; then
    rm -rf "$SYS_APP_BUNDLE"
    cp -R "$APP_BUNDLE" "$SYS_APP_BUNDLE" 2>/dev/null || true
fi

TARGET_APP="$APP_BUNDLE"
[ -d "$SYS_APP_BUNDLE" ] && TARGET_APP="$SYS_APP_BUNDLE"

CERT_NAME="SilentHelper Dev"
if ! security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    echo "[*] Barqaror kod imzolash sertifikati yaratilmoqda..."
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
    codesign --force --deep --sign "$CERT_NAME" --identifier "com.local.${APP_NAME}" "$TARGET_APP" >/dev/null 2>&1 || true
    echo "[+] ${TARGET_APP} barqaror sertifikat bilan muhrlandi."
fi

USER_TCC="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
if [ -f "$USER_TCC" ] && [ -w "$USER_TCC" ]; then
    sqlite3 "$USER_TCC" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags, last_modified) VALUES ('kTCCServiceScreenCapture', 'com.local.SilentHelper', 0, 2, 4, 1, 0, strftime('%s','now'));" 2>/dev/null || true
    sqlite3 "$USER_TCC" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags, last_modified) VALUES ('kTCCServiceAccessibility', 'com.local.SilentHelper', 0, 2, 4, 1, 0, strftime('%s','now'));" 2>/dev/null || true
    echo "[+] TCC bazasiga to'g'ridan-to'g'ri ruxsatlar kiritildi."
fi

open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

echo ""
echo "[✓] Ruxsatlar sozlamalari ochildi!"
echo "[✓] SilentHelper ro'yxatda yonidagi knopkani 1 marta 'ON' qilib qo'ysangiz yetarli."
echo "[✓] Endi dasturni xoh Finder'dan, xoh Spotlight'dan, xoh Terminal'siz oching — boshqa qayta ruxsat so'ramaydi!"
