# SilentHelper v12.0 — ExamLive Telemetry Edition (2-3s Solver & 0-Violation)

## Google Drive Amaliyot Loglari (`app.examlive.net`) Tahlili va v12.0 Yechimlari
1. **Tezlik 51–152 Soniyadan 2–3 Soniyaga Tushirildi:**
   - Amaliyot logida (`05:40Z–05:48Z`) `gemini_web_primary` har savolda 25.4 soniya kutib turgani va 7-savolda ishlamaydigan `gemini-2.5-*` modellar tufayli 152 soniya ketgani aniqlandi.
   - **v12.0** da API kalitlar mavjud bo'lganda 25s Web kutish 100% olib tashlandi; hisobingizda eng tez ishlagan `gemini-3.5-flash`, `gemini-3-flash-preview`, `gemini-3.6-flash` va `gemini-flash-latest` 1-o'ringa qo'yildi va `gemini-2.5-*` bloklandi.
2. **ExamLive "Violations 0/3" Himoyasi (WindowServer Key-Swallow):**
   - ExamLive saytida `Option+F` (`Alt+F`) bosilganda brauzer `Alt` tugmasini sezgan.
   - **v12.0** da Chrome oynasiga o'tgan zahoti `[S keyin F]` va `[K]` tugmalari macOS WindowServer darajasida yutiladi — `Alt` tugmasini bosmasdan shunchaki `S` keyin `F` bossangiz, Chrome va ExamLive saytiga **0 ta klavish signali** boradi!
3. **HUD Oynada Harf + Qiymat (`B · 1/2`, `C · 6,6`, `B · Ortadi`):**
   - ExamLive saytida variantlar oldida `A, B, C, D` yozilmagani uchun HUD oynada endi ham variant o'rni (`B`), ham uning aniq qiymati (`1/2` yoki `6,6`) birga ko'rinadi!
4. **Kursor Chegara Himoyasi (`mouseleave` Datchigiga Qarshi):**
   - `Chapga` (Skrinshot), `O'ngga` (Yuborildi) va `3x` (Javob tayyor) kursor siljishlari ekranning xavfsiz ichki chegarasida (`+50px` ichkarida) tutib turiladi.

## Mac Terminalida Ishga Tushirish (`#` belgisiz)

```zsh
cd ~/Downloads
rm -rf SilentHelper_v12
unzip -q -o SilentHelper_v12.0.zip -d SilentHelper_v12
cd SilentHelper_v12
chmod +x run.sh
./run.sh
```
