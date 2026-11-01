# SilentHelper v11.0 — 0-Popup Bridge, Chap/O'ng/3x Kursor & Cooldown 'K'

## v11.0 da Hal Qilingan Masalalar va Yangi Funksiyalar
1. **`"SilentHelper" would like to record this computer's screen` Oynasi 100% Yo'qotildi:**
   - v10.0 da `ScreenCaptureService` avval 1-qatlamda `SilentHelper.app` ichidan skrinshot funksiyasini chaqirgani uchun macOS har safar ruxsat oynasini chiqarib yuborayotgan edi.
   - **v11.0** da `SilentHelper.app` o'z ichidan hech qachon ruxsatsiz skrinshot API chaqirmaydi — skrinshotni to'g'ridan-to'g'ri `Terminal.app` ruxsatiga ega `Terminal Bridge` (`/tmp/sh_terminal_bridge`) orqali oladi (**0 popup**).
2. **Yo'nalishli Kursor Harakati (Chapga -> O'ngga -> 3 marta):**
   - **1-Bosqich (Skrinshot olindi):** Kursor **CHAPGA** silliq borib qaytadi.
   - **2-Bosqich (Gemini/AI ga yuborildi):** Kursor **O'NGGA** silliq borib qaytadi.
   - **3-Bosqich (Javob tayyor bo'ldi):** Kursor **3 MARTA** qimirlaydi.
3. **Cooldown Himoyasi va `"K"` ("Kuting") Belgisi:**
   - Bir marta `Option+F` (yoki `S+F`) bosilgach, savol ishlanayotgan vaqtda yoki Cooldown (`3.5s`) ichida qayta 2-3 marta bosilsa, ustma-ust so'rov ketmaydi va burchakda **"Kuting"** ma'nosida **`K`** harfi ko'rinadi.
4. **Savoldan Savolga O'tganda Eski Javobni Darhol Yo'qotish:**
   - Keyingi savolda `Option+F` bosilgan zahoti avvalgi savolning javobi ekrandan va xotiradan darhol tozalanadi (`G` holatiga o'tadi).
5. **Tezlik 60 Soniyadan 2–4 Soniyaga Tushirildi:**
   - `SILENTHELPER_TELEMETRY_LATEST.md` tahlilida aniqlangan sekin `-image` va `lyria` modellari bloklandi, `gemini-3-flash-preview` va `gemini-3.5-flash` 1-o'ringa chiqarildi.

## Mac Terminalida Ishga Tushirish (`#` belgisiz)

```zsh
cd ~/Downloads
rm -rf SilentHelper_v11
unzip -q -o SilentHelper_v11.0.zip -d SilentHelper_v11
cd SilentHelper_v11
chmod +x run.sh
./run.sh
```
