#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SilentHelper"
VERSION="8.0.0"
BIN_PATH="./silenthelper_bin"

echo "--------------------------------------------------------"
echo "  ${APP_NAME} v${VERSION} — Terminal-Backed Self-Healing Runner"
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

# 1. Eski buzilgan SilentHelper.app TCC yozuvlarini tozalash (qayta-qayta so'ramasligi uchun)
tccutil reset Accessibility com.local.SilentHelper >/dev/null 2>&1 || true

# 2. Bevosita Terminal.app ruxsati ostida ishlaydigan binar faylni yig'ish
# Nima uchun bu muhim? Chunki Terminal.app Apple imzosiga ega — unga bir marta
# Screen Recording va Accessibility ruxsatini bersangiz, v8, v9, v10... qayta
# yig'ilganda ruxsat HECH QACHON yo'qolmaydi!
echo "[*] ${APP_NAME} v${VERSION} kompilyatsiya qilinmoqda..."

swiftc -O main.swift \
    -framework Cocoa \
    -framework SwiftUI \
    -framework WebKit \
    -framework Vision \
    -framework ScreenCaptureKit \
    -framework CoreGraphics \
    -framework Carbon \
    -framework CryptoKit \
    -o "$BIN_PATH"

chmod +x "$BIN_PATH"
xattr -cr "$BIN_PATH" >/dev/null 2>&1 || true

# 3. Terminal orqali skrinshot ruxsatini avtomatik tekshirish va so'rash
echo "[*] Terminal orqali Screen Recording ruxsati tekshirilmoqda..."
if /usr/sbin/screencapture -x -m -t jpg /tmp/sh_perm_check.jpg >/dev/null 2>&1 && [ -s /tmp/sh_perm_check.jpg ]; then
    rm -f /tmp/sh_perm_check.jpg
    echo "[+] Screen Recording ruxsati TASDIQLANGAN (100% tayyor)!"
else
    rm -f /tmp/sh_perm_check.jpg
    echo "[!] Diqqat: Hozir ochiladigan oynada 'Terminal' uchun Screen Recording va Accessibility ni yoqing."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" || true
fi

echo ""
echo "v8.0 BOSHQARUV VA JONLI KODLAR ([K] bosilganda):"
echo "  • [S -> F] yoki [Option + F] yoki Chap-Tepa Burchak:"
echo "    - 1-bosqich: Kursor inson qo'lidek 1 marta bilinar-bilinmas siljiydi"
echo "    - 2-bosqich: 100% JIM (orqa fonda Gemini'ga yuboriladi)"
echo "    - 3-bosqich: Javob chiqqach, kursor 3 marta mayin siljiydi"
echo "  • [K] yoki [Option + K] yoki Chap-Past Burchak (HUD Kodlari):"
echo "    - G   : Gemini hozir ishlayapti"
echo "    - IW  : Internet xatosi (dastur o'zi qayta urinmoqda)"
echo "    - SW  : Yuborishda xato (dastur o'zi modelni almashtirib qayta yubormoqda)"
echo "    - W   : Umumiy xato (dastur o'zi avto-tuzatmoqda)"
echo "    - A / B / C / D yoki A̲ B : Tayyor javob!"
echo "--------------------------------------------------------"

exec "$BIN_PATH"