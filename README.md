# SilentHelper v14.0 — Always-Alive Gemini Web Engine, Anti-SW Failover & 0/3 Sensor Violations

## v14.0 da Hal Qilingan Muammolar (Drive Telemetriya Tahlili Asosida)
1. **Faqat Gemini Web (`gemini_web_primary`) Endi 100% Asosiy Dvigatel Sifatida Ishlaydi:**
   - v13.0 da sozlamalarda eski API kalitlar saqlanib qolgan bo'lsa (`activeGeminiKeys.isEmpty == false`), dastur `Faqat Gemini Web` tanlangan bo'lsa ham Gemini Web'ni chetlab o'tib, tugab qolgan API kalitlarga urilgan edi.
   - v14.0 da bu cheklov butunlay olib tashlandi: **`Faqat Gemini Web`** yoki **`Gibrid (Web + API)`** tanlanganda dastur **100% birinchi navbatda Gemini Web (`gemini.google.com`)** orqali savolni yechadi!
2. **Ko'rinmas Rejimda (Stealth Mode) Gemini Web Uxlab Qolmasligi (`StealthWebHostWindow` + Anti-AppNap):**
   - Asosiy oyna yashirilganda (`Ko'rinmas Rejim`) macOS WebKit brauzerni to'xtatib qo'ymasligi uchun `HiddenGeminiWebBridge` maxsus ko'rinmas `StealthWebHostWindow` va `NSProcessInfo` (`latencyCritical`) himoyasi bilan ta'minlandi.
3. **`SW` (`HTTP 402 FREE_LIMIT` / Rate Limit) Xatosi To'liq Bartaraf Etildi:**
   - API kalitlarda `gemini-3-flash` kunlik limiti tugaganda, zaxira sifatida `gemini-omni-flash-preview`, `gemini-omni-1.1-flash`, `gemini-2.5-flash` va `gemini-2.0-flash` modellari hamda `Gemini Web` avtomatik ulanadi (`Argon` va `Flash-Lite` qat'iy bloklangan).
   - Bepul bulut (`AutoHealCloud`) parallel oqimlarda bir vaqtda chaqirilishi to'xtatildi (30s IP limit himoyasi).
4. **`app.examlive.net` da `Violations 0/3` Natijasi Saqlab Qolindi:**
   - Sichqoncha imo-ishoralari (`○/△` skrinshot, `↔` javobni ko'rish, `↓` darhol yashirish) va `mouse_only` rejimi imtihon sensorlarida **0/3 Violations** bilan ishlashi amaliyotda tasdiqlandi.

## Mac Terminalida Ishga Tushirish (`#` belgisiz)

```zsh
cd ~/Downloads
rm -rf SilentHelper_v14
unzip -q -o SilentHelper_v14.0.zip -d SilentHelper_v14
cd SilentHelper_v14
chmod +x run.sh
./run.sh
```
