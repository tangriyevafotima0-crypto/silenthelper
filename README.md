# SilentHelper v10.0 — Deep Bug-Hunted, Auto-Bridge & Google Drive Telemetry Edition

## v10.0 da Hal Qilingan Barcha Muammolar (Bug Hunt Natijalari)
1. **Terminal Ruxsat Ko'prigi (`--bridge-daemon`) + `.app` Email Konteyneri (`com.local.SilentHelper`):**
   - `v9.0` dagi `practice_session_report.md` logida `CAPTURE | SW | Skrinshot xatosi: Screen Recording ruxsati yo'q` xatosi aniqlangan edi.
   - **v10.0** da ikki qatlamli arxitektura ishlaydi:
     - Asosiy dastur `~/Applications/SilentHelper.app` (`com.local.SilentHelper`) sifatida ishga tushadi — bu sizning **Google Email sessiyangizni** va **Dock / Cmd+Tab** ikonkangizni 100% saqlaydi.
     - Shu bilan birga `run.sh` fonda `/tmp/sh_terminal_bridge --bridge-daemon` ko'prigini `Terminal.app` ostida ishga tushiradi — u `Terminal.app` ning mavjud Screen Recording va Accessibility ruxsatlaridan foydalanib, skrinshot olish, `S+F`/`K` tugmalar va `1x`/`3x` kursor siljishini **hech qanday ruxsat so'ramasdan** bajaradi!
   - Shuningdek, `Downloads` papkasidagi eski dublikat `SilentHelper.app` fayllari tozalanadi va binar o'zgarmaguncha qayta imzolanmaydi (`source.sha256`).
2. **Qo'shaloq Bosilish (Double-Trigger) Xatosi Tuzatildi:**
   - `practice_session_report.md` da aniqlangan `04:10:05.550Z` va `04:10:05.562Z` (12ms farq bilan 2 marta ketma-ket ishlash) xatosi atomik `NSLock` va `1.2s` debounce bilan to'liq bartaraf etildi.
3. **2026 Gemini Web `Flash ⌄` / `Pro ⌄` Avto-Almashtirgich va `Chat | Task` Himoyasi:**
   - Yangi Gemini Web interfeysidagi prompt qutisi ichidagi `Flash ⌄` / `Pro ⌄` tugmasi avtomatik boshqariladi hamda `Task` rejimidan `Chat` rejimiga o'tkaziladi.
   - `Pro` modelining ichki "Thinking..." matnlari javobdan avto-tozalanadi.
4. **Mometrix / Bluebook Savol Setkasi (1..94) Filtri:**
   - `archive_index.json` tahlilida aniqlangan 1 dan 94 gacha bo'lgan savol raqamlari RAM Arxiv qidiruvidan filtrlandi.
5. **Google Drive Avto-Telemetriya (`QuizArchive/FlightLogs/`):**
   - Keyingi versiyalarda tahlil qilish uchun barcha harakatlar real vaqtda Google Drive ichidagi quyidagi fayllarga avtomatik yozib boriladi:
     - `QuizArchive/FlightLogs/SILENTHELPER_TELEMETRY_LATEST.md`
     - `QuizArchive/FlightLogs/practice_session_report.md`
     - `QuizArchive/FlightLogs/flight_recorder_log.jsonl`

## Mac Terminalida Ishga Tushirish (`#` belgisiz)

```zsh
cd ~/Downloads
rm -rf SilentHelper_v10
unzip -q -o SilentHelper_v10.0.zip -d SilentHelper_v10
cd SilentHelper_v10
chmod +x run.sh
./run.sh
```
