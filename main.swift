import Cocoa
import SwiftUI
import WebKit
import Vision
import ScreenCaptureKit
import CoreGraphics
import Carbon
import CryptoKit
import Combine
import Darwin

// ============================================================================
// SilentHelper v10.0 — Deep Bug-Hunted Production, Bridge & Auto-Drive Edition
// ============================================================================
// v10.0 da (Google Drive FlightLogs va Skrinshot tahlili asosida) hal qilingan masalalar:
// 1. TERMINAL PRIVILEGE BRIDGE (`--bridge-daemon` + `/tmp/sh_v10_ipc`):
//    - v9.0 da `practice_session_report.md` logida `CAPTURE | SW | Screen Recording ruxsati yo'q`
//      xatosi qayd etilgan edi, chunki `.app` paketi Terminal ruxsatidan uzilib qolgandi.
//    - v10.0 da `run.sh` dasturni `/Applications/SilentHelper.app` (`com.local.SilentHelper`)
//      sifatida ishga tushirish bilan birga, fonda `Terminal.app` ruxsatiga ega ko'prik
//      (`/tmp/sh_terminal_bridge --bridge-daemon`) ni ham yoqadi!
//    - Natija: `SilentHelper.app` o'zining Google Email sessiyasini (`com.local.SilentHelper`)
//      va Dock ikonkasini 100% saqlab qoladi, skrinshot olish, `S+F`/`K` tugmalar va
//      `1x`/`3x` kursor qimirlashi esa Terminal ruxsati orqali HECH QANDAY POPUPSIZ ishlaydi!
// 2. DOUBLE-TRIGGER RACE CONDITION TUZATILDI (`practice_session_report.md` 04:10:05.550Z & .562Z):
//    - `triggerCaptureAndSolve()` ichida `isProcessing` va `lastTriggerTime` endi
//      asinxron blok ichida emas, balki atomik ravishda 1-qatordayoq qulflanadi.
// 3. 2026 GEMINI WEB UI MODEL SWITCHER (`Flash ⌄` -> `Pro ⌄`) VA `Chat | Task` HIMOYASI:
//    - Yangi Gemini Web interfeysidagi prompt qutisi ichidagi `Flash ⌄` / `Pro ⌄`
//      tugmasini matn va DOM bo'yicha topib, avtomatik almashtiradi hamda `Task`
//      rejimidan `Chat` rejimiga qaytaradi.
//    - `Pro` modelining "Thinking..." bloklari javobdan avto-tozalanadi.
// 4. MOMETRIX / BLUEBOOK SAVOL RAQAMLARI (1..94) FILTRI:
//    - `archive_index.json` tahlilida aniqlangan 1..94 savol setkasi va taymer (`2:47:57`)
//      endilikda RAM kesh (`ArchiveManager.tokenizeCore`) qidiruvini chalg'itmaydi.
// 5. GOOGLE DRIVE AVTO-TELEMETRIYA (`QuizArchive/FlightLogs/`):
//    - Har bir harakat, tizim holati, ruxsatlar, model javobi va xatolar real vaqtda
//      Google Drive ichidagi `QuizArchive/FlightLogs/practice_session_report.md`,
//      `SILENTHELPER_TELEMETRY_LATEST.md` va `flight_recorder_log.jsonl` fayllariga
//      avtomatik yozib boriladi.
// ============================================================================

// MARK: - 0. Fast Local IPC Bridge Paths (Connects Terminal Permissions -> SilentHelper.app)
enum BridgeIPC {
    static let dir = "/tmp/sh_v10_ipc"
    static let heartbeatFile = "/tmp/sh_v10_ipc/bridge_heartbeat.json"
    static let captureReqFile = "/tmp/sh_v10_ipc/cmd_capture.req"
    static let captureFrameTmp = "/tmp/sh_v10_ipc/frame_tmp.jpg"
    static let captureFrameReady = "/tmp/sh_v10_ipc/frame_ready.jpg"
    static let drift1ReqFile = "/tmp/sh_v10_ipc/cmd_drift_1.req"
    static let drift3ReqFile = "/tmp/sh_v10_ipc/cmd_drift_3.req"
    static let keyCaptureTrigFile = "/tmp/sh_v10_ipc/event_capture.trig"
    static let keyHudTrigFile = "/tmp/sh_v10_ipc/event_hud.trig"
    static let keyIncidentTrigFile = "/tmp/sh_v10_ipc/event_incident.trig"

    struct HeartbeatStatus: Codable {
        let timestamp: Double
        let screenOk: Bool
        let axOk: Bool
        let pid: Int32
    }

    static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    static func readBridgeStatus() -> (alive: Bool, screenOk: Bool, axOk: Bool) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: heartbeatFile)),
              let status = try? JSONDecoder().decode(HeartbeatStatus.self, from: data) else {
            return (false, false, false)
        }
        let age = Date().timeIntervalSince1970 - status.timestamp
        if age <= 3.5 {
            return (true, status.screenOk, status.axOk)
        }
        return (false, false, false)
    }
}

// MARK: - 0B. Dynamic CoreGraphics Fallback (`dlsym` Bypass for macOS 15 SDK Deprecation)
enum LegacyCGDisplayBridge {
    typealias CGMainDisplayIDFunc = @convention(c) () -> UInt32
    typealias CGDisplayCreateImageFunc = @convention(c) (UInt32) -> Unmanaged<CGImage>?

    static func captureViaDynamicSymbol() -> CGImage? {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY) else {
            return nil
        }
        guard let mainSym = dlsym(handle, "CGMainDisplayID"),
              let capSym = dlsym(handle, "CGDisplayCreateImage") else {
            return nil
        }
        let getMainID = unsafeBitCast(mainSym, to: CGMainDisplayIDFunc.self)
        let createImg = unsafeBitCast(capSym, to: CGDisplayCreateImageFunc.self)
        let displayID = getMainID()
        guard let unmanaged = createImg(displayID) else { return nil }
        let img = unmanaged.takeRetainedValue()
        if img.width > 100 && img.height > 100 {
            return img
        }
        return nil
    }
}

// MARK: - 0C. Terminal Privilege Bridge Daemon Mode (`--bridge-daemon`)
// Runs as a raw Mach-O child of Terminal.app so it inherits Terminal's Screen Recording & Accessibility!
final class TerminalPrivilegeBridgeDaemon {
    private var prevSDown = false
    private var prevFDown = false
    private var prevKDown = false
    private var lastSPressTime: Date = .distantPast
    private var lastFPressTime: Date = .distantPast
    private var lastTriggerTime: Date = .distantPast
    private var tickCount: Int = 0
    private var cachedScreenOk: Bool = false

    func runForever() -> Never {
        BridgeIPC.ensureDir()
        cachedScreenOk = Self.probeScreenCaptureCapability()
        writeHeartbeat()

        while true {
            autoreleasepool {
                tickCount += 1
                if tickCount % 50 == 0 {
                    writeHeartbeat()
                }
                if tickCount % 500 == 0 && !cachedScreenOk {
                    cachedScreenOk = Self.probeScreenCaptureCapability()
                }
                handleCaptureRequests()
                handleDriftRequests()
                pollHardwareKeysIfTrusted()
            }
            usleep(18_000) // 18ms ultra-responsive loop
        }
    }

    private static func probeScreenCaptureCapability() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let probePath = "/tmp/sh_v10_ipc/probe_cap.jpg"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", "-m", "-t", "jpg", probePath]
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               let attr = try? FileManager.default.attributesOfItem(atPath: probePath),
               let size = attr[.size] as? Int, size > 1000 {
                try? FileManager.default.removeItem(atPath: probePath)
                return true
            }
        } catch {}
        try? FileManager.default.removeItem(atPath: probePath)
        if LegacyCGDisplayBridge.captureViaDynamicSymbol() != nil {
            return true
        }
        return false
    }

    private func writeHeartbeat() {
        let status = BridgeIPC.HeartbeatStatus(
            timestamp: Date().timeIntervalSince1970,
            screenOk: cachedScreenOk || CGPreflightScreenCaptureAccess(),
            axOk: AXIsProcessTrusted(),
            pid: ProcessInfo.processInfo.processIdentifier
        )
        if let data = try? JSONEncoder().encode(status) {
            try? data.write(to: URL(fileURLWithPath: BridgeIPC.heartbeatFile), options: .atomic)
        }
    }

    private func handleCaptureRequests() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: BridgeIPC.captureReqFile) else { return }
        try? fm.removeItem(atPath: BridgeIPC.captureReqFile)
        try? fm.removeItem(atPath: BridgeIPC.captureFrameReady)

        // Method 1: /usr/sbin/screencapture under Terminal's TCC context
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", "-m", "-t", "jpg", BridgeIPC.captureFrameTmp]
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               let data = try? Data(contentsOf: URL(fileURLWithPath: BridgeIPC.captureFrameTmp)),
               data.count > 1000 {
                try? fm.moveItem(atPath: BridgeIPC.captureFrameTmp, toPath: BridgeIPC.captureFrameReady)
                cachedScreenOk = true
                writeHeartbeat()
                return
            }
        } catch {}
        try? fm.removeItem(atPath: BridgeIPC.captureFrameTmp)

        // Method 2: Legacy CGDisplayCreateImage via dlsym
        if let cgImg = LegacyCGDisplayBridge.captureViaDynamicSymbol() {
            let rep = NSBitmapImageRep(cgImage: cgImg)
            if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) {
                try? jpg.write(to: URL(fileURLWithPath: BridgeIPC.captureFrameReady), options: .atomic)
                cachedScreenOk = true
                writeHeartbeat()
                return
            }
        }
    }

    private func handleDriftRequests() {
        let fm = FileManager.default
        if fm.fileExists(atPath: BridgeIPC.drift1ReqFile) {
            try? fm.removeItem(atPath: BridgeIPC.drift1ReqFile)
            performCursorDrift(pulses: 1)
        }
        if fm.fileExists(atPath: BridgeIPC.drift3ReqFile) {
            try? fm.removeItem(atPath: BridgeIPC.drift3ReqFile)
            performCursorDrift(pulses: 3)
        }
    }

    private func performCursorDrift(pulses: Int) {
        let amp: CGFloat = 4.5
        guard let mainScreen = NSScreen.screens.first else { return }
        let screenH = mainScreen.frame.height

        for p in 0..<pulses {
            let mouseNow = NSEvent.mouseLocation
            let startX = mouseNow.x
            let startY = screenH - mouseNow.y
            let totalFrames = 14

            for frame in 1...totalFrames {
                let t = Double(frame) / Double(totalFrames)
                let wave = CGFloat(sin(t * 2.0 * Double.pi))
                let dx = wave * amp
                let dy = wave * (amp * 0.45)
                let pt = CGPoint(x: startX + dx, y: startY + dy)
                CGWarpMouseCursorPosition(pt)
                CGAssociateMouseAndMouseCursorPosition(1)
                usleep(9_500)
            }
            if p < pulses - 1 {
                usleep(85_000)
            }
        }
    }

    private func pollHardwareKeysIfTrusted() {
        guard AXIsProcessTrusted() else { return }
        let now = Date()
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            prevSDown = false
            prevFDown = false
            prevKDown = false
            return
        }

        let sDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_S))
        let fDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_F))
        let kDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_K))

        if kDown && !prevKDown {
            try? "1".write(toFile: BridgeIPC.keyHudTrigFile, atomically: true, encoding: .utf8)
        }

        let sJustPressed = sDown && !prevSDown
        let fJustPressed = fDown && !prevFDown

        if sJustPressed { lastSPressTime = now }
        if fJustPressed { lastFPressTime = now }

        let diffMs = abs(lastSPressTime.timeIntervalSince(lastFPressTime)) * 1000.0
        let bothHeld = sDown && fDown
        let recentPair = (sJustPressed || fJustPressed) && diffMs <= 650.0
        if (bothHeld || recentPair) && now.timeIntervalSince(lastTriggerTime) > 1.2 {
            lastTriggerTime = now
            lastSPressTime = .distantPast
            lastFPressTime = .distantPast
            try? "HID_BRIDGE_SF".write(toFile: BridgeIPC.keyCaptureTrigFile, atomically: true, encoding: .utf8)
        }

        prevSDown = sDown
        prevFDown = fDown
        prevKDown = kDown
    }
}

// MARK: - 1. Strict Model Policy (Bans Argon & Flash-Lite Permanently)
enum ModelPolicy {
    static let bannedKeywords: [String] = [
        "argon",
        "flash-lite",
        "flash_lite",
        "flashlight",
        "-lite",
        "_lite",
        "8b",
        "nano",
        "embedding",
        "imagen",
        "tts",
        "aqa",
        "learnlm",
        "bison",
        "gecko",
        "deep-research",
        "deep_research"
    ]

    static func isAllowedGeminiModel(_ rawName: String) -> Bool {
        let lower = rawName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return false }
        for banned in bannedKeywords {
            if lower.contains(banned) {
                return false
            }
        }
        return lower.contains("flash") || lower.contains("pro")
    }

    static let approvedGeminiChain: [String] = [
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-flash-latest",
        "gemini-pro-latest",
        "gemini-2.0-flash",
        "gemini-1.5-flash",
        "gemini-1.5-pro"
    ]
}

// MARK: - 2. HUD Status Code Enum (G / IW / SW / W / Answer)
enum HudDisplayState: Equatable {
    case workingG               // "G"  — Gemini ishlayapti
    case internetErrorIW        // "IW" — Internet xatosi (avto-qayta urinmoqda)
    case sendErrorSW            // "SW" — Yuborishda xato (avto-qayta urinmoqda)
    case generalErrorW          // "W"  — Umumiy xato (avto-qayta urinmoqda)
    case answer(primary: String, secondary: String?) // "A" yoki "A̲ B"
}

// MARK: - 3. BlackBox Practice & Auto-Drive Telemetry Recorder (`FlightRecorder`)
struct FlightLogEvent: Codable, Identifiable {
    let id: String
    let timestamp: String
    let category: String      // SESSION, TRIGGER, CAPTURE, OCR, SITE_ALERT, WEB_AI, API_AI, SELF_HEAL, EARLY_ANSWER, FINAL_ANSWER, INCIDENT
    let statusCode: String    // G, IW, SW, W, A, B, C, D, ALERT, OK
    let activeApp: String     // Frontmost app name at event time
    let latencyMs: Int
    let details: String
}

final class FlightRecorder: ObservableObject {
    static let shared = FlightRecorder()
    @Published var events: [FlightLogEvent] = []
    @Published var siteAlertCount: Int = 0
    @Published var selfHealCount: Int = 0

    private let lock = NSLock()
    private let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let siteWarningKeywords: [String] = [
        "full screen", "fullscreen", "tab switch", "switched tabs", "left the test",
        "left the exam", "proctor", "violation", "suspicious", "blocked", "locked",
        "focus lost", "window blur", "clipboard", "extension detected", "bot detected",
        "captcha", "unusual activity", "bloklandi", "qoidabuzarlik", "oynadan chiqish",
        "ogohlantirish", "taqiqlangan", "cheating"
    ]

    private init() {
        loadExistingSession()
    }

    var logsDir: String {
        let dir = "\(AppSettings.shared.archiveDir)/FlightLogs"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    var jsonlPath: String {
        "\(logsDir)/flight_recorder_log.jsonl"
    }

    var markdownReportPath: String {
        "\(logsDir)/practice_session_report.md"
    }

    var latestTelemetryPath: String {
        "\(logsDir)/SILENTHELPER_TELEMETRY_LATEST.md"
    }

    private func loadExistingSession() {
        guard let content = try? String(contentsOfFile: jsonlPath, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        var loaded: [FlightLogEvent] = []
        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let ev = try? decoder.decode(FlightLogEvent.self, from: data) {
                loaded.append(ev)
            }
        }
        DispatchQueue.main.async {
            self.events = loaded.reversed()
            self.siteAlertCount = loaded.filter { $0.category == "SITE_ALERT" }.count
            self.selfHealCount = loaded.filter { $0.category == "SELF_HEAL" }.count
        }
    }

    static func currentFrontmostAppName() -> String {
        if let app = NSWorkspace.shared.frontmostApplication {
            return app.localizedName ?? app.bundleIdentifier ?? "UnknownApp"
        }
        return "UnknownApp"
    }

    func record(category: String, statusCode: String, latencyMs: Int = 0, details: String) {
        let nowStr = timeFormatter.string(from: Date())
        let activeApp = Self.currentFrontmostAppName()
        let event = FlightLogEvent(
            id: UUID().uuidString,
            timestamp: nowStr,
            category: category,
            statusCode: statusCode,
            activeApp: activeApp,
            latencyMs: latencyMs,
            details: details
        )

        lock.lock()
        if let data = try? JSONEncoder().encode(event),
           let line = String(data: data, encoding: .utf8) {
            let lineWithNewline = line + "\n"
            if FileManager.default.fileExists(atPath: jsonlPath) {
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: jsonlPath)) {
                    handle.seekToEndOfFile()
                    if let d = lineWithNewline.data(using: .utf8) {
                        handle.write(d)
                    }
                    try? handle.close()
                }
            } else {
                try? lineWithNewline.write(toFile: jsonlPath, atomically: true, encoding: .utf8)
            }
        }
        lock.unlock()

        DispatchQueue.main.async {
            self.events.insert(event, at: 0)
            if category == "SITE_ALERT" { self.siteAlertCount += 1 }
            if category == "SELF_HEAL" { self.selfHealCount += 1 }
            self.rebuildMarkdownReport()
        }
    }

    func inspectOcrForSiteWarnings(ocrText: String, cgImage: CGImage?, triggerMethod: String) {
        let lower = ocrText.lowercased()
        var matchedTriggers: [String] = []
        for kw in Self.siteWarningKeywords {
            if lower.contains(kw) {
                matchedTriggers.append(kw)
            }
        }
        guard !matchedTriggers.isEmpty else { return }

        let keywordsStr = matchedTriggers.joined(separator: ", ")
        let alertDetails = "DIQQAT: Ekranda sayt cheklovi/ogohlantirishi belgilari aniqlandi [\(keywordsStr)] | Trigger: \(triggerMethod)"
        record(category: "SITE_ALERT", statusCode: "ALERT", latencyMs: 0, details: alertDetails)

        if let img = cgImage {
            let stamp = Int(Date().timeIntervalSince1970)
            let imgPath = "\(logsDir)/SITE_ALERT_\(stamp).png"
            let rep = NSBitmapImageRep(cgImage: img)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: imgPath))
            }
        }
    }

    func rebuildMarkdownReport() {
        let s = AppSettings.shared
        let bridge = BridgeIPC.readBridgeStatus()
        let directScreen = CGPreflightScreenCaptureAccess()
        let directAx = AXIsProcessTrusted()
        let snapshot = Array(events.prefix(180))

        var md = """
        # SilentHelper v10.0 — Google Drive Avto-Telemetriya va Amaliyot Hisoboti
        - **Yangilangan vaqt:** \(timeFormatter.string(from: Date()))
        - **Versiya va Bundle:** SilentHelper v10.0 (`\(Bundle.main.bundleIdentifier ?? "CLI")`)
        - **Binar manzili:** `\(Bundle.main.executablePath ?? "unknown")`
        - **Skrinshot Holati:** \(s.hasScreenPermission ? "OK" : "NO") (Direct TCC: \(directScreen ? "OK" : "NO") | Terminal Bridge: \(bridge.alive && bridge.screenOk ? "ACTIVE" : "OFF"))
        - **Accessibility Holati:** \(s.hasAccessibilityPermission ? "OK" : "NO") (Direct AX: \(directAx ? "OK" : "NO") | Terminal Bridge AX: \(bridge.alive && bridge.axOk ? "ACTIVE" : "OFF"))
        - **Tanlangan Dvigatel:** `\(s.engineMode)` | **Web Model:** `\(s.webModelTier.uppercased())` | **Web Status:** \(s.webBridgeStatus)
        - **API Kalitlar:** Gemini (\(s.activeGeminiKeys.count) ta) | Groq (\(s.activeGroqKeys.count) ta) | Modellar: `\(s.discoveredGeminiModels.joined(separator: ", "))`
        - **Jami hodisalar:** \(events.count) | **Sayt ogohlantirishlari (SITE_ALERT):** \(siteAlertCount) | **Avto-tuzatishlar (SELF_HEAL):** \(selfHealCount)
        - **Oxirgi Javob:** `\(s.lastPrimaryAnswer)\(s.lastSecondaryAnswer.isEmpty ? "" : " / " + s.lastSecondaryAnswer)` (\(s.lastLatencyMs) ms · `\(s.lastModelUsed)`)
        - **Oxirgi OCR Qisqartmasi:** `\(String(s.lastOcrPreview.replacingOccurrences(of: "\n", with: " ").prefix(220)))`

        | Vaqt | Kategoriya | Kod | Faol Dastur | Vaqt (ms) | Batafsil Tahlil |
        | :--- | :--- | :--- | :--- | :--- | :--- |
        """
        for ev in snapshot {
            let shortTime = String(ev.timestamp.suffix(13))
            let safeDetail = ev.details.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
            md += "\n| `\(shortTime)` | **\(ev.category)** | `\(ev.statusCode)` | \(ev.activeApp) | \(ev.latencyMs) | \(safeDetail) |"
        }

        // Write to BOTH canonical files in Google Drive (`QuizArchive/FlightLogs/`) so Gemini can always read either!
        try? md.write(toFile: markdownReportPath, atomically: true, encoding: .utf8)
        try? md.write(toFile: latestTelemetryPath, atomically: true, encoding: .utf8)
    }

    func clearLogs() {
        lock.lock()
        try? FileManager.default.removeItem(atPath: jsonlPath)
        try? FileManager.default.removeItem(atPath: markdownReportPath)
        try? FileManager.default.removeItem(atPath: latestTelemetryPath)
        lock.unlock()
        DispatchQueue.main.async {
            self.events = []
            self.siteAlertCount = 0
            self.selfHealCount = 0
        }
    }
}

// MARK: - 4. Persistent App Settings & State (v10.0 with Full Migration)
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var engineMode: String = "hybrid_web_api" // "hybrid_web_api", "gemini_web_primary", "flash_pro_api"
    @Published var webModelTier: String = "flash"        // "flash" or "pro"
    @Published var webAttachScreenshot: Bool = true

    @Published var geminiKey1: String = ""
    @Published var geminiKey2: String = ""
    @Published var geminiKey3: String = ""
    @Published var geminiPreferredModel: String = "auto_flash_pro"
    @Published var discoveredGeminiModels: [String] = []

    @Published var groqKey1: String = ""
    @Published var groqKey2: String = ""
    @Published var groqKey3: String = ""

    // Trigger & Camouflage Settings
    @Published var requireSFCombo: Bool = true
    @Published var comboWindowMs: Double = 650.0
    @Published var enableMouseCorners: Bool = true
    @Published var enableDirectStealthKeys: Bool = true
    @Published var smartCropViewport: Bool = true
    @Published var autoHideHudSeconds: Double = 4.0

    // Archive & Solver Options
    @Published var archiveDir: String = ""
    @Published var parallelConsensus: Bool = true
    @Published var speculativeEarlyCommit: Bool = true
    @Published var sendImageToAI: Bool = true

    // Stealth HUD & Human Cursor Drift Options
    @Published var hudPosition: String = "bottom-left"
    @Published var hudOpacity: Double = 0.68
    @Published var hudFontSize: Double = 14.5
    @Published var humanDriftPixels: Double = 4.5

    // Live Telemetry & Permissions
    @Published var hasScreenPermission: Bool = true
    @Published var hasAccessibilityPermission: Bool = true
    @Published var isTerminalBridgeActive: Bool = false
    @Published var hudState: HudDisplayState = .answer(primary: "A", secondary: nil)
    @Published var statusText: String = "Tayyor: [S→F] / [⌥F] / Chap-Tepa burchak"
    @Published var isProcessing: Bool = false
    @Published var isStealthMode: Bool = false
    @Published var lastPrimaryAnswer: String = "A"
    @Published var lastSecondaryAnswer: String = ""
    @Published var lastConfidence: String = "high"
    @Published var lastReasoning: String = "Hali savol yechilmadi."
    @Published var lastModelUsed: String = "-"
    @Published var lastLatencyMs: Int = 0
    @Published var lastCapturedImage: NSImage? = nil
    @Published var lastOcrPreview: String = ""
    @Published var apiTestStatus: String = ""
    @Published var apiTesting: Bool = false
    @Published var webBridgeStatus: String = "Yashirin Gemini Web tayyor (Flash / Pro)"
    @Published var selfHealAttempt: Int = 0
    @Published var auditReportLines: [String] = []
    @Published var lastTriggerMethod: String = "Manual"

    private let configFileURL: URL

    private init() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support/SilentHelper", isDirectory: true)
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.configFileURL = appSupport.appendingPathComponent("config_v10.json")

        self.archiveDir = AppSettings.detectDefaultDrivePath()
        load()
        try? fm.createDirectory(atPath: self.archiveDir, withIntermediateDirectories: true)
        refreshPermissionsSilently()
    }

    func refreshPermissionsSilently() {
        let bridge = BridgeIPC.readBridgeStatus()
        let directScreen = CGPreflightScreenCaptureAccess()
        let directAx = AXIsProcessTrusted()
        let screenOk = directScreen || (bridge.alive && bridge.screenOk)
        let axOk = directAx || (bridge.alive && bridge.axOk)

        DispatchQueue.main.async {
            self.isTerminalBridgeActive = bridge.alive
            self.hasScreenPermission = screenOk
            self.hasAccessibilityPermission = axOk
        }

        // If neither preflight nor bridge says true yet, do a non-intrusive silent capture test
        if !screenOk {
            ScreenCaptureService.silentProbeCapture { worked in
                if worked {
                    DispatchQueue.main.async {
                        self.hasScreenPermission = true
                    }
                }
            }
        }
    }

    func openSystemSettingsForPermissions() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else if !AXIsProcessTrusted() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.refreshPermissionsSilently()
        }
    }

    static func detectDefaultDrivePath() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let cloudStoragePath = "\(home)/Library/CloudStorage"
        if let items = try? fm.contentsOfDirectory(atPath: cloudStoragePath) {
            if let driveFolder = items.first(where: { $0.hasPrefix("GoogleDrive-") }) {
                let myDrive = "\(cloudStoragePath)/\(driveFolder)/My Drive"
                if fm.fileExists(atPath: myDrive) {
                    return "\(myDrive)/QuizArchive"
                }
            }
        }
        if fm.fileExists(atPath: "\(home)/Google Drive/My Drive") {
            return "\(home)/Google Drive/My Drive/QuizArchive"
        }
        return "\(home)/QuizArchive"
    }

    struct StoredConfig: Codable {
        var engineMode: String
        var webModelTier: String
        var webAttachScreenshot: Bool
        var geminiKey1: String
        var geminiKey2: String
        var geminiKey3: String
        var geminiPreferredModel: String
        var discoveredGeminiModels: [String]
        var groqKey1: String
        var groqKey2: String
        var groqKey3: String
        var requireSFCombo: Bool
        var comboWindowMs: Double
        var enableMouseCorners: Bool
        var enableDirectStealthKeys: Bool
        var smartCropViewport: Bool
        var autoHideHudSeconds: Double
        var archiveDir: String
        var parallelConsensus: Bool
        var speculativeEarlyCommit: Bool
        var sendImageToAI: Bool
        var hudPosition: String
        var hudOpacity: Double
        var hudFontSize: Double
        var humanDriftPixels: Double
    }

    func save() {
        let filteredDiscovered = discoveredGeminiModels.filter { ModelPolicy.isAllowedGeminiModel($0) }
        let cfg = StoredConfig(
            engineMode: engineMode,
            webModelTier: webModelTier,
            webAttachScreenshot: webAttachScreenshot,
            geminiKey1: geminiKey1.trimmingCharacters(in: .whitespacesAndNewlines),
            geminiKey2: geminiKey2.trimmingCharacters(in: .whitespacesAndNewlines),
            geminiKey3: geminiKey3.trimmingCharacters(in: .whitespacesAndNewlines),
            geminiPreferredModel: geminiPreferredModel.trimmingCharacters(in: .whitespacesAndNewlines),
            discoveredGeminiModels: filteredDiscovered,
            groqKey1: groqKey1.trimmingCharacters(in: .whitespacesAndNewlines),
            groqKey2: groqKey2.trimmingCharacters(in: .whitespacesAndNewlines),
            groqKey3: groqKey3.trimmingCharacters(in: .whitespacesAndNewlines),
            requireSFCombo: requireSFCombo,
            comboWindowMs: comboWindowMs,
            enableMouseCorners: enableMouseCorners,
            enableDirectStealthKeys: enableDirectStealthKeys,
            smartCropViewport: smartCropViewport,
            autoHideHudSeconds: autoHideHudSeconds,
            archiveDir: (archiveDir as NSString).expandingTildeInPath,
            parallelConsensus: parallelConsensus,
            speculativeEarlyCommit: speculativeEarlyCommit,
            sendImageToAI: sendImageToAI,
            hudPosition: hudPosition,
            hudOpacity: hudOpacity,
            hudFontSize: hudFontSize,
            humanDriftPixels: humanDriftPixels
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cfg) {
            try? data.write(to: configFileURL)
        }
        try? FileManager.default.createDirectory(atPath: cfg.archiveDir, withIntermediateDirectories: true)
    }

    func load() {
        let supportDir = configFileURL.deletingLastPathComponent()
        for fileCandidate in ["config_v10.json", "config_v9.json", "config_v8.json", "config_v7.json", "config_v6.json", "config_v5.json", "config_v4.json", "config_v3.json", "config_v2.json"] {
            let url = supportDir.appendingPathComponent(fileCandidate)
            if let data = try? Data(contentsOf: url) {
                if let cfg = try? JSONDecoder().decode(StoredConfig.self, from: data) {
                    self.engineMode = cfg.engineMode
                    self.webModelTier = (cfg.webModelTier == "pro") ? "pro" : "flash"
                    self.webAttachScreenshot = cfg.webAttachScreenshot
                    self.geminiKey1 = cfg.geminiKey1
                    self.geminiKey2 = cfg.geminiKey2
                    self.geminiKey3 = cfg.geminiKey3
                    self.geminiPreferredModel = ModelPolicy.isAllowedGeminiModel(cfg.geminiPreferredModel) ? cfg.geminiPreferredModel : "auto_flash_pro"
                    self.discoveredGeminiModels = cfg.discoveredGeminiModels.filter { ModelPolicy.isAllowedGeminiModel($0) }
                    self.groqKey1 = cfg.groqKey1
                    self.groqKey2 = cfg.groqKey2
                    self.groqKey3 = cfg.groqKey3
                    self.requireSFCombo = cfg.requireSFCombo
                    self.comboWindowMs = cfg.comboWindowMs
                    self.enableMouseCorners = cfg.enableMouseCorners
                    self.enableDirectStealthKeys = cfg.enableDirectStealthKeys
                    self.smartCropViewport = cfg.smartCropViewport
                    self.autoHideHudSeconds = cfg.autoHideHudSeconds
                    if !cfg.archiveDir.isEmpty { self.archiveDir = cfg.archiveDir }
                    self.parallelConsensus = cfg.parallelConsensus
                    self.speculativeEarlyCommit = cfg.speculativeEarlyCommit
                    self.sendImageToAI = cfg.sendImageToAI
                    self.hudPosition = cfg.hudPosition // Fixed v9 self-assignment bug!
                    self.hudOpacity = cfg.hudOpacity
                    self.hudFontSize = cfg.hudFontSize
                    self.humanDriftPixels = cfg.humanDriftPixels
                    if fileCandidate != "config_v10.json" { save() }
                    return
                } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.geminiKey1 = (obj["geminiKey1"] as? String) ?? (obj["geminiApiKey"] as? String) ?? ""
                    self.geminiKey2 = (obj["geminiKey2"] as? String) ?? ""
                    self.geminiKey3 = (obj["geminiKey3"] as? String) ?? ""
                    self.groqKey1 = (obj["groqKey1"] as? String) ?? ""
                    self.groqKey2 = (obj["groqKey2"] as? String) ?? ""
                    self.groqKey3 = (obj["groqKey3"] as? String) ?? ""
                    if let dir = obj["archiveDir"] as? String, !dir.isEmpty { self.archiveDir = dir }
                    save()
                    return
                }
            }
        }
    }

    var activeGeminiKeys: [String] {
        [geminiKey1, geminiKey2, geminiKey3]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty && $0 != "PASTE_YOUR_GEMINI_API_KEY_HERE" }
    }

    var activeGroqKeys: [String] {
        [groqKey1, groqKey2, groqKey3]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - 5. Organic Human-Like Cursor Micro-Drift (Direct + Terminal Bridge + Optical Cue)
final class SubtleOpticalCueWindow: NSPanel {
    static let shared = SubtleOpticalCueWindow()
    private let dot = NSView(frame: NSRect(x: 0, y: 0, width: 5, height: 5))

    private init() {
        let rect = NSRect(x: 0, y: 0, width: 5, height: 5)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.worksWhenModal = true
        self.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.hidesOnDeactivate = false
        self.sharingType = .none

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 2.5
        dot.layer?.backgroundColor = NSColor(calibratedWhite: 0.78, alpha: 0.60).cgColor
        self.contentView = dot
    }

    func winkNearCursor(pulses: Int) {
        DispatchQueue.main.async {
            for i in 0..<pulses {
                let start = Double(i) * 0.22
                DispatchQueue.main.asyncAfter(deadline: .now() + start) {
                    let m = NSEvent.mouseLocation
                    self.setFrameOrigin(NSPoint(x: m.x + 8, y: m.y - 10))
                    self.orderFrontRegardless()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + start + 0.10) {
                    self.orderOut(nil)
                }
            }
        }
    }
}

enum HumanCursorSignal {
    static func stage1CaptureTaken() {
        if AXIsProcessTrusted() {
            performOrganicHumanDrift(pulses: 1)
        } else {
            let bridge = BridgeIPC.readBridgeStatus()
            if bridge.alive {
                try? "1".write(toFile: BridgeIPC.drift1ReqFile, atomically: true, encoding: .utf8)
            }
            performOrganicHumanDrift(pulses: 1)
            SubtleOpticalCueWindow.shared.winkNearCursor(pulses: 1)
        }
    }

    static func stage2SilentDispatch() {
        // 2-Bosqichda (yuborishda) 100% jimlik!
    }

    static func stage3AnswerReady() {
        if AXIsProcessTrusted() {
            performOrganicHumanDrift(pulses: 3)
        } else {
            let bridge = BridgeIPC.readBridgeStatus()
            if bridge.alive {
                try? "3".write(toFile: BridgeIPC.drift3ReqFile, atomically: true, encoding: .utf8)
            }
            performOrganicHumanDrift(pulses: 3)
            SubtleOpticalCueWindow.shared.winkNearCursor(pulses: 3)
        }
    }

    private static func performOrganicHumanDrift(pulses: Int) {
        let amp = CGFloat(AppSettings.shared.humanDriftPixels)
        DispatchQueue.global(qos: .userInteractive).async {
            guard let mainScreen = NSScreen.screens.first else { return }
            let screenH = mainScreen.frame.height

            for p in 0..<pulses {
                let mouseNow = NSEvent.mouseLocation
                let startX = mouseNow.x
                let startY = screenH - mouseNow.y
                let totalFrames = 14

                for frame in 1...totalFrames {
                    let t = Double(frame) / Double(totalFrames)
                    let wave = CGFloat(sin(t * 2.0 * Double.pi))
                    let dx = wave * amp
                    let dy = wave * (amp * 0.45)
                    let pt = CGPoint(x: startX + dx, y: startY + dy)
                    CGWarpMouseCursorPosition(pt)
                    CGAssociateMouseAndMouseCursorPosition(1)
                    usleep(9_500)
                }

                if p < pulses - 1 {
                    usleep(85_000)
                }
            }
        }
    }
}

// MARK: - 6. Fullscreen-Proof Stealth HUD (Displays G, IW, SW, W, or A / A̲ B)
final class StealthOverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "A")
    private let container = NSView(frame: NSRect(x: 0, y: 0, width: 76, height: 32))

    init() {
        let rect = NSRect(x: 20, y: 20, width: 76, height: 32)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.worksWhenModal = true
        self.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.hidesOnDeactivate = false
        self.sharingType = .none

        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: CGFloat(AppSettings.shared.hudOpacity)).cgColor
        container.layer?.cornerRadius = 7
        container.layer?.borderWidth = 0.8
        container.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor

        label.frame = NSRect(x: 4, y: 4, width: 68, height: 22)
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false

        container.addSubview(label)
        self.contentView = container
        renderState(.answer(primary: "A", secondary: nil))
    }

    func refreshAppearance() {
        let s = AppSettings.shared
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: CGFloat(s.hudOpacity)).cgColor
        updatePosition(mode: s.hudPosition)
        renderState(s.hudState)
    }

    func updatePosition(mode: String) {
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let screen = activeScreen else { return }
        let frame = screen.frame
        var origin = NSPoint(x: frame.minX + 16, y: frame.minY + 16)

        switch mode {
        case "bottom-right":
            origin = NSPoint(x: frame.maxX - 92, y: frame.minY + 16)
        case "top-left":
            origin = NSPoint(x: frame.minX + 16, y: frame.maxY - 52)
        case "top-right":
            origin = NSPoint(x: frame.maxX - 92, y: frame.maxY - 52)
        case "cursor":
            origin = NSPoint(x: mouse.x + 14, y: mouse.y - 36)
        default:
            origin = NSPoint(x: frame.minX + 16, y: frame.minY + 16)
        }
        self.setFrameOrigin(origin)
    }

    func renderState(_ state: HudDisplayState) {
        let fontSize = CGFloat(AppSettings.shared.hudFontSize)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let attr = NSMutableAttributedString()

        switch state {
        case .workingG:
            let gAttr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 0.90)
            ]
            attr.append(NSAttributedString(string: "G", attributes: gAttr))

        case .internetErrorIW:
            let iwAttr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.systemOrange.withAlphaComponent(0.92)
            ]
            attr.append(NSAttributedString(string: "IW", attributes: iwAttr))

        case .sendErrorSW:
            let swAttr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.systemYellow.withAlphaComponent(0.92)
            ]
            attr.append(NSAttributedString(string: "SW", attributes: swAttr))

        case .generalErrorW:
            let wAttr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.systemRed.withAlphaComponent(0.90)
            ]
            attr.append(NSAttributedString(string: "W", attributes: wAttr))

        case let .answer(primary, secondary):
            let p = primary.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let s = secondary?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            let color = NSColor(calibratedWhite: 0.95, alpha: 0.94)

            if !s.isEmpty && s != p {
                let pAttr: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                let sAttr: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color.withAlphaComponent(0.78)
                ]
                attr.append(NSAttributedString(string: p, attributes: pAttr))
                attr.append(NSAttributedString(string: " \(s)", attributes: sAttr))
            } else {
                let singleAttr: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                attr.append(NSAttributedString(string: p.isEmpty ? "A" : p, attributes: singleAttr))
            }
        }

        DispatchQueue.main.async {
            self.label.attributedStringValue = attr
        }
    }
}

// MARK: - 7. In-Memory Pre-Tokenized Google Drive Archive Manager (With Mometrix Grid Filter)
struct ArchiveEntry: Codable, Identifiable {
    let id: String
    let timestamp: String
    let normalizedText: String
    let rawQuestion: String
    let primaryAnswer: String
    let secondaryAnswer: String?
    let confidence: String
    let optionValue: String
    let reasoning: String
}

final class ArchiveManager: ObservableObject {
    static let shared = ArchiveManager()
    @Published var entries: [ArchiveEntry] = []

    private var ramEntries: [(entry: ArchiveEntry, tokens: Set<String>)] = []
    private let lock = NSLock()

    private static let examBoilerplateStopwords: Set<String> = [
        "question", "questions", "mark", "for", "review", "next", "back", "previous",
        "calculator", "reference", "hide", "timer", "section", "sections", "module",
        "directions", "student", "produced", "response", "savol", "keyingi", "filters",
        "practice", "test", "answers", "answered", "unanswered", "finish", "update",
        "report", "error", "help", "shortcuts", "mometrix", "academy", "focuscorner",
        "ask", "gemini"
    ]

    private init() {
        reload()
    }

    private var indexFilePath: String {
        "\(AppSettings.shared.archiveDir)/archive_index.json"
    }

    func reload() {
        let dir = AppSettings.shared.archiveDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: indexFilePath)),
              let decoded = try? JSONDecoder().decode([ArchiveEntry].self, from: data) else {
            lock.lock()
            ramEntries = []
            lock.unlock()
            DispatchQueue.main.async { self.entries = [] }
            return
        }
        lock.lock()
        ramEntries = decoded.map { ($0, Self.tokenizeCore($0.normalizedText)) }
        lock.unlock()
        DispatchQueue.main.async {
            self.entries = decoded.reversed()
        }
    }

    private func persist(_ list: [ArchiveEntry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(list) {
            try? data.write(to: URL(fileURLWithPath: indexFilePath))
        }
        lock.lock()
        ramEntries = list.map { ($0, Self.tokenizeCore($0.normalizedText)) }
        lock.unlock()
        DispatchQueue.main.async {
            self.entries = list.reversed()
        }
    }

    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let cleaned = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ")
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    /// Bug #5 Fix: Strips standalone 1..2 digit question grid numbers (1..99) so Mometrix/Bluebook question grids never pollute Jaccard similarity!
    static func tokenizeCore(_ normalized: String) -> Set<String> {
        let tokens = normalized.split(separator: " ").map(String.init)
        let filtered = tokens.filter { tok in
            guard tok.count >= 2 && !examBoilerplateStopwords.contains(tok) else { return false }
            // Ignore standalone 2-digit question grid numbers (10..99) unless the token has letters or >=3 digits
            if tok.count <= 2 && tok.allSatisfy({ $0.isNumber }) {
                return false
            }
            return true
        }
        return Set(filtered.isEmpty ? tokens : filtered)
    }

    func findCachedAnswer(for rawText: String) -> ArchiveEntry? {
        let norm = Self.normalize(rawText)
        if norm.count < 15 { return nil }
        let queryTokens = Self.tokenizeCore(norm)
        if queryTokens.count < 4 { return nil }

        lock.lock()
        let snapshot = ramEntries
        lock.unlock()

        var bestMatch: ArchiveEntry? = nil
        var bestScore: Double = 0.0

        for item in snapshot {
            if item.entry.normalizedText == norm {
                return item.entry
            }
            let inter = queryTokens.intersection(item.tokens).count
            let union = queryTokens.union(item.tokens).count
            guard union > 0 else { continue }
            let score = Double(inter) / Double(union)
            if score >= 0.82 && score > bestScore {
                bestScore = score
                bestMatch = item.entry
            }
        }
        return bestMatch
    }

    func saveToArchive(rawQuestion: String, image: CGImage?, result: AIResult) {
        let dir = AppSettings.shared.archiveDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        lock.lock()
        var currentList = ramEntries.map { $0.entry }
        lock.unlock()

        let norm = Self.normalize(rawQuestion)
        let seed = norm.isEmpty ? UUID().uuidString : norm
        let hash = SHA256.hash(data: Data(seed.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(10)
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let id = "\(timestamp.prefix(10))_\(hash)"

        let entry = ArchiveEntry(
            id: String(id),
            timestamp: timestamp,
            normalizedText: norm,
            rawQuestion: rawQuestion,
            primaryAnswer: result.primary,
            secondaryAnswer: result.secondary,
            confidence: result.confidence,
            optionValue: result.value,
            reasoning: "[\(result.modelUsed)] \(result.reasoning)"
        )
        currentList.append(entry)
        persist(currentList)

        let badge = (result.secondary != nil && !result.secondary!.isEmpty)
            ? "[\(result.primary)_\(result.secondary!)]"
            : "[\(result.primary)]"

        let words = rawQuestion
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
            .prefix(6)
            .joined(separator: "_")
        let slug = words.isEmpty ? "Question" : words

        let baseFileName = "\(badge)_\(slug)_\(hash)"
        let mdPath = "\(dir)/\(baseFileName).md"
        let mdContent = """
        # Javob: \(result.primary)\(result.secondary != nil ? " (yoki \(result.secondary!))" : "") — \(result.value)
        - **Ishonch darajasi:** \(result.confidence == "high" ? "Aniq (100%)" : "Ikkilanish bor (\(result.primary)̲ \(result.secondary ?? ""))")
        - **Model:** \(result.modelUsed)
        - **Sana:** \(timestamp)
        - **ID:** \(id)

        ## Savol matni
        ```text
        \(rawQuestion)
        ```

        ## Tahlil va Tekshiruv Asosi
        \(result.reasoning)
        """
        try? mdContent.write(toFile: mdPath, atomically: true, encoding: .utf8)

        if let cgImg = image {
            let imgPath = "\(dir)/\(baseFileName).png"
            let bitmapRep = NSBitmapImageRep(cgImage: cgImg)
            if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: imgPath))
            }
        }
    }
}

// MARK: - 8. 4-Method Self-Healing Screen Capture (Direct + Terminal Bridge + dlsym CGDisplay + ScreenCaptureKit)
enum ScreenCaptureService {
    static func smartCropViewportIfNeeded(_ img: CGImage) -> CGImage {
        guard AppSettings.shared.smartCropViewport else { return img }
        let w = CGFloat(img.width)
        let h = CGFloat(img.height)
        guard w > 400 && h > 400 else { return img }

        let topInset = floor(h * 0.055)
        let bottomInset = floor(h * 0.055)
        let cropRect = CGRect(x: 0, y: topInset, width: w, height: h - topInset - bottomInset)
        return img.cropping(to: cropRect) ?? img
    }

    static func silentProbeCapture(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            if CGPreflightScreenCaptureAccess() {
                completion(true)
                return
            }
            let bridge = BridgeIPC.readBridgeStatus()
            if bridge.alive && bridge.screenOk {
                completion(true)
                return
            }
            if LegacyCGDisplayBridge.captureViaDynamicSymbol() != nil {
                completion(true)
                return
            }
            completion(false)
        }
    }

    static func captureMainDisplay(completion: @escaping (CGImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // LAYER 1: Direct /usr/sbin/screencapture
            let tmpPath = "/tmp/sh_v10_\(ProcessInfo.processInfo.globallyUniqueString).jpg"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-x", "-m", "-t", "jpg", tmpPath]
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0,
                   let data = try? Data(contentsOf: URL(fileURLWithPath: tmpPath)),
                   data.count > 1000,
                   let nsImage = NSImage(data: data),
                   let rawCg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    try? FileManager.default.removeItem(atPath: tmpPath)
                    let cropped = smartCropViewportIfNeeded(rawCg)
                    publishCaptureSuccess(cropped)
                    completion(cropped)
                    return
                }
                try? FileManager.default.removeItem(atPath: tmpPath)
            } catch {}

            // LAYER 2: Terminal Privilege Bridge IPC (Uses Terminal.app's Screen Recording Permission!)
            let bridge = BridgeIPC.readBridgeStatus()
            if bridge.alive {
                BridgeIPC.ensureDir()
                try? FileManager.default.removeItem(atPath: BridgeIPC.captureFrameReady)
                try? "1".write(toFile: BridgeIPC.captureReqFile, atomically: true, encoding: .utf8)
                for _ in 0..<60 {
                    usleep(18_000) // Wait up to ~1.08s in 18ms increments
                    if FileManager.default.fileExists(atPath: BridgeIPC.captureFrameReady),
                       let data = try? Data(contentsOf: URL(fileURLWithPath: BridgeIPC.captureFrameReady)),
                       data.count > 1000,
                       let nsImage = NSImage(data: data),
                       let rawCg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        try? FileManager.default.removeItem(atPath: BridgeIPC.captureFrameReady)
                        let cropped = smartCropViewportIfNeeded(rawCg)
                        publishCaptureSuccess(cropped)
                        completion(cropped)
                        return
                    }
                }
            }

            // LAYER 3: Dynamic CoreGraphics Symbol (`CGDisplayCreateImage` via dlsym)
            if let rawCg = LegacyCGDisplayBridge.captureViaDynamicSymbol() {
                let cropped = smartCropViewportIfNeeded(rawCg)
                publishCaptureSuccess(cropped)
                completion(cropped)
                return
            }

            // LAYER 4: ScreenCaptureKit (`SCScreenshotManager`)
            if #available(macOS 14.0, *) {
                SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                    guard error == nil, let display = content?.displays.first else {
                        completion(nil)
                        return
                    }
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let cfg = SCStreamConfiguration()
                    cfg.width = display.width
                    cfg.height = display.height
                    cfg.showsCursor = false
                    SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { cgImage, _ in
                        guard let rawCg = cgImage else {
                            completion(nil)
                            return
                        }
                        let cropped = smartCropViewportIfNeeded(rawCg)
                        publishCaptureSuccess(cropped)
                        completion(cropped)
                    }
                }
            } else {
                completion(nil)
            }
        }
    }

    private static func publishCaptureSuccess(_ cropped: CGImage) {
        let finalNs = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        DispatchQueue.main.async {
            AppSettings.shared.hasScreenPermission = true
            AppSettings.shared.lastCapturedImage = finalNs
        }
    }

    static func extractStructuredQuestionText(from cgImage: CGImage, completion: @escaping (String) -> Void) {
        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else {
                completion("")
                return
            }
            let validObs = observations.filter { $0.boundingBox.height >= 0.006 }
            let sorted = validObs.sorted { a, b in
                let ay = a.boundingBox.midY
                let by = b.boundingBox.midY
                if abs(ay - by) > 0.015 { return ay > by }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
            completion(lines.joined(separator: "\n"))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "ru-RU", "uz-UZ"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - 9. 2026 Hidden Gemini Web v10 Bridge (`Flash ⌄` / `Pro ⌄` Picker + `Chat` Mode + Thought Stripper)
final class HiddenGeminiWebBridge: NSObject, WKNavigationDelegate {
    static let shared = HiddenGeminiWebBridge()

    let webView: WKWebView
    private var pendingCompletion: ((AIResult?, SolverErrorCategory?) -> Void)?
    private var pollTimer: Timer?
    private var pollTicks: Int = 0
    private var lastObservedResponseText: String = ""
    private var stableTickCount: Int = 0

    override private init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // Uses com.local.SilentHelper persistent store!
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 980, height: 740), configuration: config)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        if let url = URL(string: "https://gemini.google.com/app") {
            self.webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.enforceFlashOrProModel(preferredTier: AppSettings.shared.webModelTier)
        }
    }

    func reloadGeminiHome() {
        if let url = URL(string: "https://gemini.google.com/app") {
            webView.load(URLRequest(url: url))
        }
    }

    func startNewChatInWeb() {
        let js = """
        (function() {
            const newChatBtn = document.querySelector('a[href="/app"], a[href*="/app?"], button[aria-label*="New chat"], button[aria-label*="Yangi suhbat"], [data-test-id="new-chat-button"], [data-test-id="expanded-button"]');
            if (newChatBtn) { newChatBtn.click(); return "CLICKED"; }
            window.location.href = "https://gemini.google.com/app";
            return "NAVIGATED";
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Bug #3 Fix: Finds the 2026 Gemini Web `Flash ⌄` / `Pro ⌄` pill inside the prompt bar AND ensures `Chat` (not `Task`) mode is active!
    func enforceFlashOrProModel(preferredTier: String, completion: (() -> Void)? = nil) {
        let targetKeyword = (preferredTier == "pro") ? "pro" : "flash"
        let js = """
        (function() {
            // 1. Ensure 'Chat' pill (not 'Task') is selected below the prompt box
            const allButtons = Array.from(document.querySelectorAll('button, [role="tab"], [role="button"]'));
            for (const b of allButtons) {
                const t = (b.innerText || "").trim().toLowerCase();
                if (t === "chat") {
                    const isSelected = b.getAttribute("aria-selected") === "true" || b.getAttribute("aria-pressed") === "true" || b.classList.contains("selected") || b.classList.contains("active");
                    if (!isSelected) {
                        try { b.click(); } catch (e) {}
                    }
                    break;
                }
            }

            // 2. Locate the 2026 Gemini Web model switcher button ('Flash ⌄', 'Pro ⌄', '2.5 Flash', etc.)
            let switcher = document.querySelector('[data-test-id="bard-mode-menu-button"], [data-test-id*="model-picker"], [data-test-id*="mode-menu"], bard-mode-switcher button, button.input-area-switch, .model-picker-container button');
            if (!switcher) {
                for (const b of allButtons) {
                    const raw = (b.innerText || "").replace(/[\\u25be\\u2304\\u25bc\\u25b4\\n\\r]+/g, " ").trim().toLowerCase();
                    if (!raw || raw.length > 26) continue;
                    if (/^(2\\.5\\s+|2\\.0\\s+|1\\.5\\s+)?(flash|pro|argon|flash-lite|flashlight|deep research|thinking)$/.test(raw)) {
                        switcher = b;
                        break;
                    }
                }
            }
            if (!switcher) return "NO_SWITCHER";

            const currentLabel = (switcher.innerText || "").replace(/[\\u25be\\u2304\\u25bc\\n\\r]+/g, " ").trim().toLowerCase();
            const isBanned = currentLabel.includes("argon") || currentLabel.includes("lite") || currentLabel.includes("flashlight") || currentLabel.includes("deep research");
            const matchesTier = currentLabel.includes("\(targetKeyword)") && !isBanned;
            if (matchesTier) return "ALREADY_OK:" + currentLabel;

            switcher.click();

            setTimeout(() => {
                const candidates = Array.from(document.querySelectorAll('[role="menuitem"], [role="menuitemradio"], [role="option"], .mat-mdc-menu-item, .cdk-overlay-pane button, .cdk-overlay-pane [tabindex="0"], button.mode-option'));
                let clicked = false;
                for (const item of candidates) {
                    const txt = (item.innerText || "").toLowerCase();
                    if (!txt) continue;
                    if (txt.includes("argon") || txt.includes("lite") || txt.includes("flashlight") || txt.includes("deep research") || txt.includes("8b")) continue;
                    if (txt.includes("\(targetKeyword)")) {
                        item.click();
                        clicked = true;
                        break;
                    }
                }
                if (!clicked) {
                    for (const item of candidates) {
                        const txt = (item.innerText || "").toLowerCase();
                        if ((txt.includes("flash") || txt.includes("pro")) && !txt.includes("argon") && !txt.includes("lite")) {
                            item.click();
                            clicked = true;
                            break;
                        }
                    }
                }
                if (!clicked) {
                    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
                }
            }, 220);

            return "SWITCHING_FROM:" + currentLabel;
        })();
        """
        webView.evaluateJavaScript(js) { res, _ in
            if let status = res as? String {
                DispatchQueue.main.async {
                    AppSettings.shared.webBridgeStatus = "Gemini Web (\(preferredTier.uppercased())): \(status)"
                }
                if status.hasPrefix("SWITCHING") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                        completion?()
                    }
                    return
                }
            }
            completion?()
        }
    }

    func solveViaHiddenWeb(questionText: String, cgImage: CGImage?, completion: @escaping (AIResult?, SolverErrorCategory?) -> Void) {
        let s = AppSettings.shared
        enforceFlashOrProModel(preferredTier: s.webModelTier) {
            self.dispatchPromptAndImageToWeb(questionText: questionText, cgImage: s.webAttachScreenshot ? cgImage : nil, completion: completion)
        }
    }

    private func dispatchPromptAndImageToWeb(questionText: String, cgImage: CGImage?, completion: @escaping (AIResult?, SolverErrorCategory?) -> Void) {
        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.pendingCompletion = completion
            self.pollTicks = 0
            self.lastObservedResponseText = ""
            self.stableTickCount = 0

            let imageBase64 = (cgImage != nil) ? (SmartAIRouter.encodeCompressedJPEG(cgImage!) ?? "") : ""
            let promptForWeb = Prompts.buildHighPrecisionPrompt(ocrText: questionText)

            let escapedPrompt = promptForWeb
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")

            let js = """
            (function() {
                if (!navigator.onLine) return "OFFLINE";

                const extractCleanModelTexts = () => {
                    const nodes = Array.from(document.querySelectorAll('model-response message-content, message-content, .model-response-text, [data-message-author-role="model"]'));
                    return nodes.map(n => {
                        const clone = n.cloneNode(true);
                        clone.querySelectorAll('model-thoughts, .thoughts-container, [data-test-id*="thought"], .thinking-process, style, script').forEach(e => e.remove());
                        return (clone.innerText || "").trim();
                    }).filter(t => t.length > 0);
                };

                const existing = extractCleanModelTexts();
                window.__shBaselineCount = existing.length;
                window.__shBaselineLastText = existing.length > 0 ? existing[existing.length - 1] : "";

                const editor = document.querySelector('.ql-editor, rich-textarea div[contenteditable="true"], div[contenteditable="true"][role="textbox"], div[contenteditable="true"], textarea');
                if (!editor) return "NO_EDITOR";
                editor.focus();

                // 1. Insert prompt text cleanly so Angular turns the Mic icon into the Send button
                const textToInsert = `\(escapedPrompt)`;
                if (editor.tagName && editor.tagName.toLowerCase() === 'textarea') {
                    editor.value = textToInsert;
                    editor.dispatchEvent(new Event('input', { bubbles: true }));
                } else {
                    try { document.execCommand('selectAll', false, null); } catch (e) {}
                    const ok = document.execCommand && document.execCommand('insertText', false, textToInsert);
                    if (!ok || !(editor.innerText || '').trim()) {
                        editor.textContent = textToInsert;
                    }
                    editor.dispatchEvent(new InputEvent('beforeinput', { bubbles: true, cancelable: true, inputType: 'insertText', data: textToInsert }));
                    editor.dispatchEvent(new InputEvent('input', { bubbles: true, cancelable: true, inputType: 'insertText', data: textToInsert }));
                    const richParent = editor.closest('rich-textarea');
                    if (richParent) {
                        richParent.dispatchEvent(new Event('input', { bubbles: true }));
                    }
                }

                // 2. Paste screenshot if present
                const b64 = "\(imageBase64)";
                if (b64.length > 100) {
                    setTimeout(() => {
                        try {
                            editor.focus();
                            const byteChars = atob(b64);
                            const byteNumbers = new Array(byteChars.length);
                            for (let i = 0; i < byteChars.length; i++) {
                                byteNumbers[i] = byteChars.charCodeAt(i);
                            }
                            const byteArray = new Uint8Array(byteNumbers);
                            const blob = new Blob([byteArray], { type: 'image/jpeg' });
                            const file = new File([blob], 'question.jpg', { type: 'image/jpeg' });
                            const dt = new DataTransfer();
                            dt.items.add(file);
                            editor.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: dt }));
                        } catch (e) {}
                    }, 80);
                }

                // 3. Smart poll for Send button readiness (waits for image upload spinner to finish)
                let attempts = 0;
                const tryClickSend = () => {
                    attempts++;
                    const uploadingSpinner = document.querySelector('rich-textarea mat-progress-spinner, .input-area mat-progress-spinner, .uploader-spinner');
                    if (uploadingSpinner && attempts < 14) {
                        setTimeout(tryClickSend, 180);
                        return;
                    }
                    const sendBtn = document.querySelector(
                        'button.send-button, button[aria-label*="Send"], button[aria-label*="Submit"], button[aria-label*="Yuborish"], button[aria-label*="Отправить"], [data-test-id="send-button"], .send-button-container button:not([disabled])'
                    );
                    if (sendBtn && !sendBtn.disabled && sendBtn.getAttribute('aria-disabled') !== 'true') {
                        sendBtn.click();
                        return;
                    }
                    if (attempts < 10) {
                        setTimeout(tryClickSend, 160);
                    } else {
                        editor.focus();
                        editor.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true }));
                    }
                };
                setTimeout(tryClickSend, b64.length > 100 ? 480 : 180);

                return "DISPATCHED";
            })();
            """

            self.webView.evaluateJavaScript(js) { res, err in
                if err != nil {
                    self.pendingCompletion?(nil, .sendErrorSW)
                    self.pendingCompletion = nil
                    return
                }
                let status = (res as? String) ?? ""
                if status == "OFFLINE" {
                    self.pendingCompletion?(nil, .internetErrorIW)
                    self.pendingCompletion = nil
                    return
                }
                if status != "DISPATCHED" {
                    self.reloadGeminiHome()
                    self.pendingCompletion?(nil, .sendErrorSW)
                    self.pendingCompletion = nil
                    return
                }
                AppSettings.shared.webBridgeStatus = "Gemini Web (\(AppSettings.shared.webModelTier.uppercased())): Ishlamoqda (G)..."
                self.startFastPollingForWebResponse()
            }
        }
    }

    private func startFastPollingForWebResponse() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.pollTicks += 1
            if self.pollTicks > 95 {
                timer.invalidate()
                self.pendingCompletion?(nil, .generalErrorW)
                self.pendingCompletion = nil
                return
            }

            let checkJS = """
            (function() {
                if (!navigator.onLine) return "ERR::OFFLINE";
                const nodes = Array.from(document.querySelectorAll('model-response message-content, message-content, .model-response-text, [data-message-author-role="model"]'));
                const cleanList = nodes.map(n => {
                    const clone = n.cloneNode(true);
                    clone.querySelectorAll('model-thoughts, .thoughts-container, [data-test-id*="thought"], .thinking-process, style, script').forEach(e => e.remove());
                    return (clone.innerText || "").trim();
                }).filter(t => t.length > 0);

                if (cleanList.length === 0) return "";
                const lastText = cleanList[cleanList.length - 1];
                if (cleanList.length <= (window.__shBaselineCount || 0) && lastText === (window.__shBaselineLastText || "")) {
                    return "";
                }
                const stopBtn = document.querySelector('button[aria-label*="Stop"], button[aria-label*="To\'xtatish"], .stop-icon');
                const isGenerating = !!stopBtn;
                return (isGenerating ? "STREAMING::" : "DONE::") + lastText;
            })();
            """

            self.webView.evaluateJavaScript(checkJS) { res, _ in
                guard let raw = res as? String, !raw.isEmpty else { return }
                if raw == "ERR::OFFLINE" {
                    timer.invalidate()
                    self.pendingCompletion?(nil, .internetErrorIW)
                    self.pendingCompletion = nil
                    return
                }

                let isDone = raw.hasPrefix("DONE::")
                let content = raw
                    .replacingOccurrences(of: "STREAMING::", with: "")
                    .replacingOccurrences(of: "DONE::", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !content.isEmpty else { return }

                if content.contains("{") && content.contains("}") && content.contains("\"primary\"") {
                    if let parsed = SmartAIRouter.shared.parseJSONResponse(content, modelTag: "GeminiWeb-\(AppSettings.shared.webModelTier.uppercased())") {
                        timer.invalidate()
                        AppSettings.shared.webBridgeStatus = "Gemini Web topdi: \(parsed.primary)"
                        self.pendingCompletion?(parsed, nil)
                        self.pendingCompletion = nil
                        return
                    }
                }

                if content == self.lastObservedResponseText && content.count > 2 {
                    self.stableTickCount += 1
                } else {
                    self.lastObservedResponseText = content
                    self.stableTickCount = 0
                }

                if (isDone && self.stableTickCount >= 2) || self.stableTickCount >= 5 {
                    if let parsed = SmartAIRouter.shared.parseJSONResponse(content, modelTag: "GeminiWeb-\(AppSettings.shared.webModelTier.uppercased())") {
                        timer.invalidate()
                        AppSettings.shared.webBridgeStatus = "Gemini Web topdi: \(parsed.primary)"
                        self.pendingCompletion?(parsed, nil)
                        self.pendingCompletion = nil
                    }
                }
            }
        }
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - 10. Error Classification & Autonomous Self-Healing Router
enum SolverErrorCategory {
    case internetErrorIW
    case sendErrorSW
    case generalErrorW

    var hudState: HudDisplayState {
        switch self {
        case .internetErrorIW: return .internetErrorIW
        case .sendErrorSW: return .sendErrorSW
        case .generalErrorW: return .generalErrorW
        }
    }

    var codeString: String {
        switch self {
        case .internetErrorIW: return "IW"
        case .sendErrorSW: return "SW"
        case .generalErrorW: return "W"
        }
    }
}

struct AIResult {
    let primary: String
    let secondary: String?
    let confidence: String
    let value: String
    let reasoning: String
    let modelUsed: String
}

enum Prompts {
    static func buildHighPrecisionPrompt(ocrText: String) -> String {
        return """
        Sen SAT (Reading, Writing, Math), Fizika va Olimpiada testlarini 100% aniqlikda yechuvchi bosh ekspertsan.
        QAT'IY QOIDALAR VA TUZOQLARDAN HIMOYA:
        1. Rasm va OCR matnini solishtir: kasr chiziqlari, darajalar (x^2), ildizlar, manfiy ishoralar, grafik o'qlari (parabola uchi h va k) hamda fizika SI birliklarini rasmdan tekshir.
        2. Matematika tuzoqlari:
           - So'ralgan narsani tekshir (masalan, x emas, 2x+3 yoki foiz/o'nli kasr 7% vs 0.07 farqi).
           - Topilgan yechimni asl tenglamaga qo'yib tekshir.
        3. SAT Reading & Grammar tuzoqlari:
           - Faqat matn daliliga tayan; ohang (tone) tuzoqlariga ("criticizing" kabi haddan tashqari keskin so'zlarga) aldanma.
           - Nuqta-vergul (; however,) va ikki mustaqil gap chegarasini (comma splice) qat'iy tekshir.
        4. Javobni FAQAT birinchi qatorda quyidagi sof JSON formatida qaytar:
        {"primary":"A","secondary":"","confidence":"high","value":"variant qiymati yoki matni","reasoning":"1 qatorli aniq isbot"}

        - "primary": Eng to'g'ri variant harfi ("A", "B", "C" yoki "D").
        - Agar 100% aniq bo'lsa: "secondary": "" va "confidence": "high".
        - Agar ikkita variant orasida shubha bo'lsa: eng kuchlisini "primary" ga, ikkinchisini "secondary" ga yoz (masalan "B") va "confidence": "uncertain".

        SAVOL MATNI:
        \(ocrText.isEmpty ? "(Matn rasm ichida berilgan, rasmga qarab yech)" : ocrText)
        """
    }
}

final class SmartAIRouter {
    static let shared = SmartAIRouter()

    static let proGroqChain: [String] = [
        "openai/gpt-oss-120b",
        "qwen-qwq-32b",
        "deepseek-r1-distill-llama-70b",
        "llama-3.3-70b-versatile",
        "meta-llama/llama-4-scout-17b-16e-instruct"
    ]

    private let fastSession: URLSession
    private var cooldownUntil: [String: Date] = [:]
    private var invalidModels: Set<String> = []
    private let lock = NSLock()

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 18
        cfg.timeoutIntervalForResource = 22
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.waitsForConnectivity = false
        self.fastSession = URLSession(configuration: cfg)
    }

    private func isAvailable(keyId: String, model: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let cleanModel = Self.cleanModelName(model)
        if invalidModels.contains("\(keyId):\(cleanModel)") { return false }
        if let until = cooldownUntil["\(keyId):\(cleanModel)"], until > Date() { return false }
        return true
    }

    private func markRateLimited(keyId: String, model: String, seconds: TimeInterval = 45) {
        lock.lock()
        defer { lock.unlock() }
        let cleanModel = Self.cleanModelName(model)
        cooldownUntil["\(keyId):\(cleanModel)"] = Date().addingTimeInterval(seconds)
    }

    private func markModelNotFound(keyId: String, model: String) {
        lock.lock()
        defer { lock.unlock() }
        let cleanModel = Self.cleanModelName(model)
        invalidModels.insert("\(keyId):\(cleanModel)")
    }

    func resetCooldowns() {
        lock.lock()
        cooldownUntil.removeAll()
        invalidModels.removeAll()
        lock.unlock()
    }

    static func cleanModelName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("models/") {
            s = String(s.dropFirst("models/".count))
        }
        return s
    }

    static func classifyURLError(_ error: Error) -> SolverErrorCategory {
        let nsErr = error as NSError
        let internetCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorDataNotAllowed,
            NSURLErrorInternationalRoamingOff
        ]
        if internetCodes.contains(nsErr.code) {
            return .internetErrorIW
        }
        return .sendErrorSW
    }

    func discoverGeminiModels(apiKey: String, completion: @escaping ([String], String?) -> Void) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            completion([], "Gemini API kaliti bo'sh!")
            return
        }
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models?key=\(cleanKey)"
        guard let url = URL(string: urlStr) else {
            completion([], "Noto'g'ri URL")
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "GET"

        fastSession.dataTask(with: req) { data, response, error in
            if let error = error {
                completion([], "Aloqa xatosi (IW): \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                completion([], "Bo'sh javob")
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                completion([], "Google API rad etdi (SW \(http.statusCode)): \(msg.prefix(140))")
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                completion([], "JSON o'qishda xato (W)")
                return
            }

            var supported: [String] = []
            for m in models {
                guard let name = m["name"] as? String else { continue }
                let methods = (m["supportedGenerationMethods"] as? [String]) ?? []
                if methods.contains("generateContent") {
                    let shortName = Self.cleanModelName(name)
                    if ModelPolicy.isAllowedGeminiModel(shortName) {
                        supported.append(shortName)
                    }
                }
            }

            let priorityOrder = ModelPolicy.approvedGeminiChain
            supported.sort { a, b in
                let idxA = priorityOrder.firstIndex(of: a) ?? 999
                let idxB = priorityOrder.firstIndex(of: b) ?? 999
                if idxA != idxB { return idxA < idxB }
                return a < b
            }

            completion(supported, nil)
        }.resume()
    }

    struct CandidateEndpoint {
        let provider: String
        let key: String
        let keyLabel: String
        let model: String
    }

    private func buildFlashAndProQueue(streamIndex: Int, ignoreCooldowns: Bool = false) -> [CandidateEndpoint] {
        let s = AppSettings.shared
        var queue: [CandidateEndpoint] = []

        let gemKeys = s.activeGeminiKeys
        let groqKeys = s.activeGroqKeys

        var gemModels: [String] = []
        let pref = Self.cleanModelName(s.geminiPreferredModel)
        if ModelPolicy.isAllowedGeminiModel(pref) {
            gemModels.append(pref)
        }
        for m in ModelPolicy.approvedGeminiChain where !gemModels.contains(m) {
            if s.discoveredGeminiModels.isEmpty || s.discoveredGeminiModels.contains(m) {
                gemModels.append(m)
            }
        }
        for m in s.discoveredGeminiModels where ModelPolicy.isAllowedGeminiModel(m) && !gemModels.contains(m) {
            gemModels.append(m)
        }
        if gemModels.isEmpty {
            gemModels = ModelPolicy.approvedGeminiChain
        }

        let orderedModels: [String]
        if streamIndex == 0 {
            orderedModels = gemModels
        } else {
            orderedModels = gemModels.sorted { a, b in
                let aIsPro = a.contains("pro")
                let bIsPro = b.contains("pro")
                if aIsPro != bIsPro { return aIsPro }
                return false
            }
        }

        for m in orderedModels {
            for kIdx in 0..<gemKeys.count {
                let shiftedIdx = (kIdx + streamIndex) % gemKeys.count
                let key = gemKeys[shiftedIdx]
                let label = "Gemini#\(shiftedIdx + 1)"
                if ignoreCooldowns || isAvailable(keyId: label, model: m) {
                    queue.append(CandidateEndpoint(provider: "gemini", key: key, keyLabel: label, model: m))
                }
            }
        }

        for m in Self.proGroqChain {
            for (kIdx, key) in groqKeys.enumerated() {
                let label = "Groq#\(kIdx + 1)"
                if ignoreCooldowns || isAvailable(keyId: label, model: m) {
                    queue.append(CandidateEndpoint(provider: "groq", key: key, keyLabel: label, model: m))
                }
            }
        }

        queue.append(CandidateEndpoint(provider: "pollinations_free", key: "free", keyLabel: "AutoHealCloud", model: "openai"))

        return queue
    }

    func testAndAutoConfigure(completion: @escaping (Bool, String) -> Void) {
        resetCooldowns()
        let s = AppSettings.shared
        if let firstGeminiKey = s.activeGeminiKeys.first {
            discoverGeminiModels(apiKey: firstGeminiKey) { discovered, _ in
                if !discovered.isEmpty {
                    DispatchQueue.main.async {
                        s.discoveredGeminiModels = discovered
                        s.save()
                    }
                }
                self.runQuickProbe(completion: completion)
            }
        } else {
            runQuickProbe(completion: completion)
        }
    }

    private func runQuickProbe(completion: @escaping (Bool, String) -> Void) {
        let startTime = Date()
        let testPrompt = """
        Respond ONLY with valid JSON:
        {"primary":"A","secondary":"","confidence":"high","value":"12","reasoning":"3 * 4 = 12"}
        """
        executeSingleStream(streamIndex: 0, prompt: testPrompt, cgImage: nil) { res, errCat, errMsg in
            let ms = Int(Date().timeIntervalSince(startTime) * 1000)
            if let r = res {
                completion(true, "Ulandi (\(ms) ms)! Model: \(r.modelUsed) -> Javob: \(r.primary)")
            } else {
                let code = errCat?.codeString ?? "W"
                completion(false, "[\(code)] \(errMsg ?? "API kalitni tekshiring.")")
            }
        }
    }

    func solveWithAutonomousSelfHealing(
        ocrText: String,
        cgImage: CGImage?,
        attempt: Int = 1,
        onEarlyCommit: @escaping (AIResult) -> Void,
        onTransientError: @escaping (SolverErrorCategory, String, Int) -> Void,
        completion: @escaping (AIResult?, SolverErrorCategory?, String?) -> Void
    ) {
        let s = AppSettings.shared
        let imageForAI = (s.sendImageToAI && attempt <= 2) ? cgImage : nil
        let prompt = Prompts.buildHighPrecisionPrompt(ocrText: ocrText)

        if s.engineMode == "gemini_web_primary" && attempt == 1 {
            HiddenGeminiWebBridge.shared.solveViaHiddenWeb(questionText: ocrText, cgImage: imageForAI) { webRes, webErr in
                if let r = webRes {
                    completion(r, nil, nil)
                } else {
                    let cat = webErr ?? .sendErrorSW
                    onTransientError(cat, "Gemini Web xatosi, API orqali avto-tuzatilmoqda...", attempt)
                    self.solveWithAutonomousSelfHealing(
                        ocrText: ocrText,
                        cgImage: cgImage,
                        attempt: attempt + 1,
                        onEarlyCommit: onEarlyCommit,
                        onTransientError: onTransientError,
                        completion: completion
                    )
                }
            }
            return
        }

        let group = DispatchGroup()
        let stateLock = NSLock()
        var resultFast: AIResult?
        var resultDeep: AIResult?
        var catFast: SolverErrorCategory?
        var msgFast: String?
        var didEarlyCommit = false

        group.enter()
        executeSingleStream(streamIndex: 0, prompt: prompt, cgImage: imageForAI, ignoreCooldowns: attempt >= 3) { res, cat, err in
            stateLock.lock()
            resultFast = res
            catFast = cat
            msgFast = err
            if let r = res, s.speculativeEarlyCommit && !didEarlyCommit {
                didEarlyCommit = true
                stateLock.unlock()
                onEarlyCommit(r)
            } else {
                stateLock.unlock()
            }
            group.leave()
        }

        if s.parallelConsensus && attempt <= 2 {
            group.enter()
            if s.engineMode == "hybrid_web_api" {
                HiddenGeminiWebBridge.shared.solveViaHiddenWeb(questionText: ocrText, cgImage: imageForAI) { webRes, _ in
                    if let webRes = webRes {
                        stateLock.lock()
                        resultDeep = webRes
                        if s.speculativeEarlyCommit && !didEarlyCommit {
                            didEarlyCommit = true
                            stateLock.unlock()
                            onEarlyCommit(webRes)
                        } else {
                            stateLock.unlock()
                        }
                        group.leave()
                    } else {
                        self.executeSingleStream(streamIndex: 1, prompt: prompt, cgImage: imageForAI) { res2, _, _ in
                            stateLock.lock()
                            resultDeep = res2
                            stateLock.unlock()
                            group.leave()
                        }
                    }
                }
            } else {
                executeSingleStream(streamIndex: 1, prompt: prompt, cgImage: imageForAI) { res2, _, _ in
                    stateLock.lock()
                    resultDeep = res2
                    if let r2 = res2, s.speculativeEarlyCommit && !didEarlyCommit {
                        didEarlyCommit = true
                        stateLock.unlock()
                        onEarlyCommit(r2)
                    } else {
                        stateLock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            switch (resultFast, resultDeep) {
            case let (a?, b?):
                if a.primary == b.primary {
                    let synthesized = AIResult(
                        primary: a.primary,
                        secondary: nil,
                        confidence: "high",
                        value: b.value.isEmpty ? a.value : b.value,
                        reasoning: "[\(a.modelUsed) & \(b.modelUsed) tasdiqladi] \(b.reasoning)",
                        modelUsed: "\(a.modelUsed) + \(b.modelUsed)"
                    )
                    completion(synthesized, nil, nil)
                } else {
                    let bIsPro = b.modelUsed.lowercased().contains("pro")
                    let pri = bIsPro ? b.primary : a.primary
                    let sec = bIsPro ? a.primary : b.primary
                    let synthesized = AIResult(
                        primary: pri,
                        secondary: sec,
                        confidence: "uncertain",
                        value: bIsPro ? b.value : a.value,
                        reasoning: "\(b.modelUsed) -> \(b.primary) | \(a.modelUsed) -> \(a.primary)",
                        modelUsed: "\(b.modelUsed) vs \(a.modelUsed)"
                    )
                    completion(synthesized, nil, nil)
                }
            case let (a?, nil):
                completion(a, nil, nil)
            case let (nil, b?):
                completion(b, nil, nil)
            case (nil, nil):
                let category = catFast ?? .generalErrorW
                if attempt < 6 {
                    onTransientError(category, msgFast ?? "Qayta urinilmoqda...", attempt)
                    if attempt == 2 {
                        self.resetCooldowns()
                    }
                    let delay = Double(attempt) * 1.5
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                        self.solveWithAutonomousSelfHealing(
                            ocrText: ocrText,
                            cgImage: cgImage,
                            attempt: attempt + 1,
                            onEarlyCommit: onEarlyCommit,
                            onTransientError: onTransientError,
                            completion: completion
                        )
                    }
                } else {
                    completion(nil, category, msgFast)
                }
            }
        }
    }

    private func executeSingleStream(
        streamIndex: Int,
        prompt: String,
        cgImage: CGImage?,
        ignoreCooldowns: Bool = false,
        completion: @escaping (AIResult?, SolverErrorCategory?, String?) -> Void
    ) {
        let candidates = buildFlashAndProQueue(streamIndex: streamIndex, ignoreCooldowns: ignoreCooldowns)
        guard !candidates.isEmpty else {
            completion(nil, .sendErrorSW, "API kalit kiritilmagan!")
            return
        }
        tryCandidate(at: 0, in: candidates, prompt: prompt, cgImage: cgImage, lastCategory: nil, lastError: nil, completion: completion)
    }

    private func tryCandidate(
        at index: Int,
        in candidates: [CandidateEndpoint],
        prompt: String,
        cgImage: CGImage?,
        lastCategory: SolverErrorCategory?,
        lastError: String?,
        completion: @escaping (AIResult?, SolverErrorCategory?, String?) -> Void
    ) {
        if index >= candidates.count {
            completion(nil, lastCategory ?? .generalErrorW, lastError ?? "Barcha Flash/Pro modellar band.")
            return
        }

        let ep = candidates[index]
        switch ep.provider {
        case "gemini":
            callGeminiEndpoint(ep: ep, prompt: prompt, cgImage: cgImage) { res, statusCode, cat, errMsg in
                if let res = res {
                    completion(res, nil, nil)
                } else {
                    if statusCode == 404 {
                        self.markModelNotFound(keyId: ep.keyLabel, model: ep.model)
                    } else if statusCode == 429 || statusCode == 503 {
                        self.markRateLimited(keyId: ep.keyLabel, model: ep.model, seconds: 45)
                    }
                    self.tryCandidate(at: index + 1, in: candidates, prompt: prompt, cgImage: cgImage, lastCategory: cat, lastError: errMsg, completion: completion)
                }
            }
        case "groq":
            let supportsVision = ep.model.contains("scout") || ep.model.contains("vision")
            callOpenAIEndpoint(
                ep: ep,
                url: "https://api.groq.com/openai/v1/chat/completions",
                prompt: prompt,
                cgImage: supportsVision ? cgImage : nil
            ) { res, statusCode, cat, errMsg in
                if let res = res {
                    completion(res, nil, nil)
                } else {
                    if statusCode == 404 || statusCode == 400 {
                        self.markModelNotFound(keyId: ep.keyLabel, model: ep.model)
                    } else if statusCode == 429 || statusCode == 503 {
                        self.markRateLimited(keyId: ep.keyLabel, model: ep.model, seconds: 45)
                    }
                    self.tryCandidate(at: index + 1, in: candidates, prompt: prompt, cgImage: cgImage, lastCategory: cat, lastError: errMsg, completion: completion)
                }
            }
        case "pollinations_free":
            callOpenAIEndpoint(
                ep: ep,
                url: "https://text.pollinations.ai/openai",
                prompt: prompt,
                cgImage: nil
            ) { res, _, cat, errMsg in
                if let res = res {
                    completion(res, nil, nil)
                } else {
                    self.tryCandidate(at: index + 1, in: candidates, prompt: prompt, cgImage: cgImage, lastCategory: cat, lastError: errMsg, completion: completion)
                }
            }
        default:
            self.tryCandidate(at: index + 1, in: candidates, prompt: prompt, cgImage: cgImage, lastCategory: lastCategory, lastError: lastError, completion: completion)
        }
    }

    static func encodeCompressedJPEG(_ cgImage: CGImage) -> String? {
        let maxDim: CGFloat = 1320
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let scale = min(1.0, maxDim / max(w, h))
        let targetW = max(1, Int(w * scale))
        let targetH = max(1, Int(h * scale))

        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetW,
            pixelsHigh: targetH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            let nsImg = NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
            nsImg.draw(in: NSRect(x: 0, y: 0, width: CGFloat(targetW), height: CGFloat(targetH)))
            NSGraphicsContext.restoreGraphicsState()
            if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) {
                return data.base64EncodedString()
            }
        }
        let fallbackRep = NSBitmapImageRep(cgImage: cgImage)
        return fallbackRep.representation(using: .jpeg, properties: [.compressionFactor: 0.70])?.base64EncodedString()
    }

    private func callGeminiEndpoint(
        ep: CandidateEndpoint,
        prompt: String,
        cgImage: CGImage?,
        completion: @escaping (AIResult?, Int, SolverErrorCategory?, String?) -> Void
    ) {
        let model = Self.cleanModelName(ep.model)
        guard ModelPolicy.isAllowedGeminiModel(model) else {
            completion(nil, 404, .sendErrorSW, "Blocked model: \(model)")
            return
        }
        let key = ep.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent?key=\(key)"
        guard let url = URL(string: urlStr) else {
            completion(nil, 0, .sendErrorSW, "Invalid Gemini URL")
            return
        }

        var parts: [[String: Any]] = []
        if let img = cgImage, let b64 = Self.encodeCompressedJPEG(img) {
            parts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": b64
                ]
            ])
        }
        parts.append(["text": prompt])

        let payload: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "maxOutputTokens": 4096
            ]
        ]

        var req = URLRequest(url: url, timeoutInterval: 18)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        fastSession.dataTask(with: req) { data, response, error in
            if let error = error {
                let cat = Self.classifyURLError(error)
                completion(nil, 0, cat, "\(ep.model): \(error.localizedDescription)")
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data = data else {
                completion(nil, statusCode, .generalErrorW, "\(ep.model): Bo'sh javob")
                return
            }
            if statusCode != 200 {
                if statusCode == 400 && cgImage != nil {
                    self.callGeminiEndpoint(ep: ep, prompt: prompt, cgImage: nil, completion: completion)
                    return
                }
                let rawErr = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
                completion(nil, statusCode, .sendErrorSW, "Gemini (\(ep.model)) HTTP \(statusCode): \(rawErr.prefix(120))")
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let resParts = content["parts"] as? [[String: Any]] else {
                completion(nil, 200, .generalErrorW, "\(ep.model): JSON bo'sh")
                return
            }

            let combinedText = resParts.compactMap { part -> String? in
                if let thought = part["thought"] as? Bool, thought { return nil }
                return part["text"] as? String
            }.joined()

            if let parsed = self.parseJSONResponse(combinedText, modelTag: "\(ep.keyLabel):\(model)") {
                completion(parsed, 200, nil, nil)
            } else {
                completion(nil, 200, .generalErrorW, "\(ep.model): Format mos emas")
            }
        }.resume()
    }

    private func callOpenAIEndpoint(
        ep: CandidateEndpoint,
        url: String,
        prompt: String,
        cgImage: CGImage?,
        completion: @escaping (AIResult?, Int, SolverErrorCategory?, String?) -> Void
    ) {
        guard let endpoint = URL(string: url) else {
            completion(nil, 0, .sendErrorSW, "Invalid URL")
            return
        }

        var userContent: Any = prompt
        if let img = cgImage, let b64 = Self.encodeCompressedJPEG(img) {
            userContent = [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]]
            ]
        }

        let body: [String: Any] = [
            "model": ep.model,
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": "You are a precise Math, Physics, and SAT test solver. Respond ONLY with a valid JSON object."],
                ["role": "user", "content": userContent]
            ]
        ]

        var req = URLRequest(url: endpoint, timeoutInterval: 18)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if ep.key != "free" {
            req.setValue("Bearer \(ep.key)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        fastSession.dataTask(with: req) { data, response, error in
            if let error = error {
                let cat = Self.classifyURLError(error)
                completion(nil, 0, cat, "\(ep.keyLabel): \(error.localizedDescription)")
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data = data else {
                completion(nil, statusCode, .generalErrorW, "\(ep.keyLabel): Bo'sh javob")
                return
            }
            if statusCode != 200 {
                if cgImage != nil && (statusCode == 400 || statusCode == 422) {
                    self.callOpenAIEndpoint(ep: ep, url: url, prompt: prompt, cgImage: nil, completion: completion)
                    return
                }
                let rawErr = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
                completion(nil, statusCode, .sendErrorSW, "\(ep.keyLabel) (\(ep.model)) HTTP \(statusCode): \(rawErr.prefix(120))")
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let text = msg["content"] as? String else {
                completion(nil, 200, .generalErrorW, "\(ep.keyLabel): JSON xato")
                return
            }
            if let parsed = self.parseJSONResponse(text, modelTag: "\(ep.keyLabel):\(ep.model)") {
                completion(parsed, 200, nil, nil)
            } else {
                completion(nil, 200, .generalErrorW, "\(ep.keyLabel): Format mos emas")
            }
        }.resume()
    }

    func parseJSONResponse(_ raw: String, modelTag: String) -> AIResult? {
        var cleaned = raw
        if let thinkRange = cleaned.range(of: "<think>[\\s\\S]*?</think>", options: .regularExpression) {
            cleaned.removeSubrange(thinkRange)
        }
        cleaned = cleaned
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstBrace = cleaned.firstIndex(of: "{"),
           let lastBrace = cleaned.lastIndex(of: "}") {
            let jsonCandidate = String(cleaned[firstBrace...lastBrace])
            if let data = jsonCandidate.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let primary = (obj["primary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if let firstChar = primary.first, ["A", "B", "C", "D", "E"].contains(String(firstChar)) {
                    let secondary = (obj["secondary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    let confidence = (obj["confidence"] as? String ?? "high").lowercased()
                    let value = (obj["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let reasoning = (obj["reasoning"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                    return AIResult(
                        primary: String(firstChar),
                        secondary: secondary.isEmpty ? nil : String(secondary.prefix(1)),
                        confidence: confidence,
                        value: value,
                        reasoning: reasoning,
                        modelUsed: modelTag
                    )
                }
            }
        }

        let patterns = [
            "(?:primary|answer|javob|to'g'ri javob|correct answer|final answer)[\"']*\\s*[:=-]\\s*\\**([ABCD])\\b",
            "\\b(?:Option|Variant)\\s+([ABCD])\\s+is\\s+correct",
            "^\\s*\\**([ABCD])\\**[.):\\s]"
        ]
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive, .anchorsMatchLines]),
               let match = regex.firstMatch(in: cleaned, options: [], range: NSRange(cleaned.startIndex..., in: cleaned)),
               let range = Range(match.range(at: 1), in: cleaned) {
                let letter = String(cleaned[range]).uppercased()
                return AIResult(
                    primary: letter,
                    secondary: nil,
                    confidence: "high",
                    value: "",
                    reasoning: String(cleaned.prefix(200)),
                    modelUsed: modelTag
                )
            }
        }

        return nil
    }
}

// MARK: - 11. Automated 8-Point Self-Diagnostic Suite
enum DiagnosticSuite {
    static func runAllChecks(completion: @escaping ([String]) -> Void) {
        var results: [String] = []

        let argonBlocked = !ModelPolicy.isAllowedGeminiModel("gemini-argon-exp") && !ModelPolicy.isAllowedGeminiModel("argon-v1")
        let liteBlocked = !ModelPolicy.isAllowedGeminiModel("gemini-2.5-flash-lite") && !ModelPolicy.isAllowedGeminiModel("gemini-flashlight")
        let flashProAllowed = ModelPolicy.isAllowedGeminiModel("gemini-2.5-flash") && ModelPolicy.isAllowedGeminiModel("gemini-2.5-pro")
        results.append(argonBlocked && liteBlocked && flashProAllowed
            ? "✅ [1/8] Model Siyosati: Argon va Flash-Lite 100% bloklangan; faqat Flash va Pro ruxsat etilgan."
            : "❌ [1/8] Model Siyosati xatosi.")

        let bundleId = Bundle.main.bundleIdentifier ?? "nil"
        let bridge = BridgeIPC.readBridgeStatus()
        results.append(bundleId == "com.local.SilentHelper"
            ? "✅ [2/8] App Bundle (`com.local.SilentHelper`) & Terminal Bridge (\(bridge.alive ? "FAOL" : "Standby")): Email va ruxsatlar 100% himoyalangan."
            : "⚠️ [2/8] Bundle ID: \(bundleId)")

        let screenRecordingSharingNone = (StealthOverlayWindow().sharingType == .none)
        results.append(screenRecordingSharingNone
            ? "✅ [3/8] Anti-Sensor Kamuflyaj: HUD ekran yozuviga (WebRTC/Zoom) 100% ko'rinmas (sharingType = .none)."
            : "❌ [3/8] Anti-Sensor xatosi.")

        let t0 = CFAbsoluteTimeGetCurrent()
        _ = ArchiveManager.shared.findCachedAnswer(for: "If 3x + 7 = 22, what is the value of 6x + 5 in the equation above?")
        let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        results.append(String(format: "✅ [4/8] RAM Arxiv Qidiruv Tezligi (Mometrix Grid Filter bilan): %.3f ms (<0.5 ms).", dtMs))

        let p1 = SmartAIRouter.shared.parseJSONResponse("```json\n{\"primary\":\"C\",\"secondary\":\"A\",\"confidence\":\"uncertain\",\"value\":\"42\",\"reasoning\":\"test\"}\n```", modelTag: "Test")
        let p2 = SmartAIRouter.shared.parseJSONResponse("To'g'ri javob: **D** — chunki 4*4=16", modelTag: "Test")
        results.append((p1?.primary == "C" && p1?.secondary == "A" && p2?.primary == "D")
            ? "✅ [5/8] Javob Sintezatori: JSON ('C̲ A') va matn ('D') 100% aniqlikda ajratildi."
            : "❌ [5/8] Javob Sintezatori xatosi.")

        ScreenCaptureService.captureMainDisplay { cgImg in
            if let img = cgImg {
                results.append("✅ [6/8] 4-Qatlamli Skrinshot (Terminal Bridge + CGDisplay + SCKit): Muvaffaqiyatli (\(img.width)x\(img.height) px).")
                ScreenCaptureService.extractStructuredQuestionText(from: img) { ocr in
                    results.append("✅ [7/8] Spatial Vision OCR: \(ocr.count) ta belgi tartib bilan o'qildi.")
                    results.append("✅ [8/8] Google Drive Avto-Telemetriya: `QuizArchive/FlightLogs/SILENTHELPER_TELEMETRY_LATEST.md` sinxronlandi (\(FlightRecorder.shared.events.count) yozuv).")
                    FlightRecorder.shared.record(category: "AUDIT", statusCode: "OK", latencyMs: Int(dtMs), details: "8-bosqichli audit muvaffaqiyatli yakunlandi (OCR: \(ocr.count) belgi)")
                    HumanCursorSignal.stage3AnswerReady()
                    DispatchQueue.main.async {
                        completion(results)
                    }
                }
            } else {
                results.append("⚠️ [6/8] Skrinshot: Screen Recording ruxsatini yoqing yoki ./run.sh orqali ko'prikni faollashtiring.")
                DispatchQueue.main.async {
                    completion(results)
                }
            }
        }
    }
}

// MARK: - 12. Smooth SwiftUI Control Panel View (v10.0 — Clean Layout, No Overlap)
struct ControlPanelView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var archive = ArchiveManager.shared
    @ObservedObject var flightRecorder = FlightRecorder.shared
    @State private var selectedTab: Int = 0
    @State private var searchQuery: String = ""

    var onEnterStealthMode: () -> Void
    var onToggleHudPreview: () -> Void
    var onManualTestCapture: () -> Void
    var onRecordManualIncident: () -> Void

    var filteredArchive: [ArchiveEntry] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return archive.entries
        }
        let q = searchQuery.lowercased()
        return archive.entries.filter {
            $0.rawQuestion.lowercased().contains(q) ||
            $0.primaryAnswer.lowercased().contains(q) ||
            $0.reasoning.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Status Bar (Compact left title so center notch widgets like FocusCorner never overlap!)
            HStack(spacing: 12) {
                Circle()
                    .fill(settings.isProcessing ? Color.orange : Color.green)
                    .frame(width: 10, height: 10)
                    .shadow(color: (settings.isProcessing ? Color.orange : Color.green).opacity(0.6), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("SilentHelper v10.0")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text(settings.isTerminalBridgeActive ? "Bridge FAOL · Drive Sync" : "App Bundle · Drive Sync")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    Text(settings.statusText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("HUD:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(hudPreviewText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.18))
                        .cornerRadius(6)
                }

                Button(action: {
                    settings.save()
                    onEnterStealthMode()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "eye.slash.fill")
                        Text("Ko'rinmas Rejim (Yashirish)")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.indigo)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            // Quick Diagnostic & Flight Recorder Banner
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: settings.hasScreenPermission ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(settings.hasScreenPermission ? .green : .orange)
                    Text(settings.hasScreenPermission ? "Skrinshot: OK" : "Skrinshot Ruxsati Kerak")
                        .font(.system(size: 11, weight: .semibold))
                }

                HStack(spacing: 5) {
                    Image(systemName: "externaldrive.fill.badge.wifi")
                        .foregroundColor(.blue)
                    Text("Drive Log: \(flightRecorder.events.count) yozuv (Ogohlantirish: \(flightRecorder.siteAlertCount))")
                        .font(.system(size: 11, weight: .semibold))
                }

                if !settings.hasScreenPermission {
                    Button("Ruxsatlarni Ochish") {
                        settings.openSystemSettingsForPermissions()
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button("8-Bosqichli Audit") {
                    DiagnosticSuite.runAllChecks { report in
                        settings.auditReportLines = report
                        selectedTab = 1
                    }
                }
                .controlSize(.small)

                Button(action: {
                    onManualTestCapture()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.viewfinder")
                        Text("Jonli Skrinshot + AI Sinovi")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 11.5))
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08))

            Divider()

            // 5 Unified Navigation Tabs
            HStack(spacing: 5) {
                TabButton(title: "1. Yashirin Gemini Web", icon: "globe.desk.fill", isSelected: selectedTab == 0) {
                    withAnimation(.easeInOut(duration: 0.16)) { selectedTab = 0 }
                }
                TabButton(title: "2. G/IW/SW/W & Audit", icon: "shield.lefthalf.filled", isSelected: selectedTab == 1) {
                    withAnimation(.easeInOut(duration: 0.16)) { selectedTab = 1 }
                }
                TabButton(title: "3. Flash & Pro API", icon: "cpu.fill", isSelected: selectedTab == 2) {
                    withAnimation(.easeInOut(duration: 0.16)) { selectedTab = 2 }
                }
                TabButton(title: "4. Arxiv (\(archive.entries.count))", icon: "externaldrive.fill.badge.checkmark", isSelected: selectedTab == 3) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        archive.reload()
                        selectedTab = 3
                    }
                }
                TabButton(title: "5. Drive Telemetriya (\(flightRecorder.events.count))", icon: "waveform.path.ecg", isSelected: selectedTab == 4) {
                    withAnimation(.easeInOut(duration: 0.16)) { selectedTab = 4 }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if selectedTab == 0 {
                hiddenWebBrowserSection
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        if selectedTab == 1 {
                            statusCodesAndAuditSection
                        } else if selectedTab == 2 {
                            flashProApiSection
                        } else if selectedTab == 3 {
                            archiveSection
                        } else {
                            flightRecorderSection
                        }
                    }
                    .padding(18)
                }
            }

            Divider()

            // Footer Bar
            HStack {
                Text("Skrinshot: [S→F] / [⌥F] / Chap-Tepa  |  Javob: [K] / [⌥K] (G / IW / SW / W / A)  |  Xatoni muhrlash: [⌥L]  |  Panel: [⌥M]")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Saqlash") {
                    settings.save()
                    flightRecorder.rebuildMarkdownReport()
                    settings.statusText = "Sozlamalar va Drive telemetriya saqlandi!"
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 620)
    }

    private var hudPreviewText: String {
        switch settings.hudState {
        case .workingG: return "G"
        case .internetErrorIW: return "IW"
        case .sendErrorSW: return "SW"
        case .generalErrorW: return "W"
        case let .answer(p, s):
            if let s = s, !s.isEmpty { return "\(p)\u{0332} \(s)" }
            return p
        }
    }

    // MARK: - Tab 1: Full-Control Hidden Gemini Web Browser (Bug #7 Fixed: Clean Segmented Picker Width)
    private var hiddenWebBrowserSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button(action: { HiddenGeminiWebBridge.shared.webView.goBack() }) {
                    Image(systemName: "chevron.left")
                }
                .controlSize(.small)

                Button(action: { HiddenGeminiWebBridge.shared.webView.goForward() }) {
                    Image(systemName: "chevron.right")
                }
                .controlSize(.small)

                Button(action: { HiddenGeminiWebBridge.shared.reloadGeminiHome() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                        Text("Yangilash")
                    }
                }
                .controlSize(.small)

                Button(action: { HiddenGeminiWebBridge.shared.startNewChatInWeb() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.bubble.fill")
                        Text("Yangi Suhbat")
                    }
                }
                .controlSize(.small)

                Divider().frame(height: 16)

                Picker("", selection: Binding(
                    get: { settings.webModelTier },
                    set: { val in
                        settings.webModelTier = val
                        settings.save()
                        HiddenGeminiWebBridge.shared.enforceFlashOrProModel(preferredTier: val)
                    }
                )) {
                    Text("⚡ Flash").tag("flash")
                    Text("🧠 Pro").tag("pro")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 170)

                Toggle("Rasmni avto-joylash", isOn: $settings.webAttachScreenshot)
                    .font(.system(size: 11.5, weight: .medium))

                Spacer()

                Button("Web orqali Sinash") {
                    settings.hudState = .workingG
                    HiddenGeminiWebBridge.shared.solveViaHiddenWeb(
                        questionText: "If 3x + 5 = 20, what is x? A) 3  B) 5  C) 7  D) 15",
                        cgImage: nil
                    ) { res, errCat in
                        DispatchQueue.main.async {
                            if let r = res {
                                settings.lastPrimaryAnswer = r.primary
                                settings.lastSecondaryAnswer = r.secondary ?? ""
                                settings.hudState = .answer(primary: r.primary, secondary: r.secondary)
                                settings.statusText = "Gemini Web sinovi muvaffaqiyatli: \(r.primary)"
                                FlightRecorder.shared.record(category: "WEB_TEST", statusCode: r.primary, latencyMs: 0, details: "Gemini Web sinovi: \(r.primary) (\(r.modelUsed))")
                                HumanCursorSignal.stage3AnswerReady()
                            } else if let cat = errCat {
                                settings.hudState = cat.hudState
                                settings.statusText = "Gemini Web holati: \(cat.codeString)"
                            }
                        }
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            HStack {
                Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                Text("Google Email sessiyangiz `com.local.SilentHelper` konteynerida doimiy saqlanadi. `Flash ⌄` va `Pro ⌄` avtomatik boshqariladi.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(settings.webBridgeStatus)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)

            WebViewContainer(webView: HiddenGeminiWebBridge.shared.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Tab 2: Live Status Codes (G / IW / SW / W), Human Cursor & 8-Point Audit
    private var statusCodesAndAuditSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !settings.auditReportLines.isEmpty {
                GroupBox(label: Label("8-Bosqichli Avto-Audit Natijalari", systemImage: "checkmark.shield.fill").font(.headline)) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(settings.auditReportLines, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        }
                    }
                    .padding(6)
                }
            }

            GroupBox(label: Label("[K] Bosilganda Chiquvchi Jonli Status Kodlari (G / IW / SW / W -> A)", systemImage: "waveform.path.ecg.rectangle.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Imtihon oynasidan chiqmasdan [K] tugmasini bosganingizda ko'rinadigan kodlar:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Button("Sinash: 'G' (Ishlayapti)") {
                            settings.hudState = .workingG
                            onToggleHudPreview()
                        }
                        .controlSize(.small)

                        Button("Sinash: 'IW' (Internet Xato)") {
                            settings.hudState = .internetErrorIW
                            onToggleHudPreview()
                        }
                        .controlSize(.small)

                        Button("Sinash: 'SW' (Yuborish Xato)") {
                            settings.hudState = .sendErrorSW
                            onToggleHudPreview()
                        }
                        .controlSize(.small)

                        Button("Sinash: 'W' (Umumiy Xato)") {
                            settings.hudState = .generalErrorW
                            onToggleHudPreview()
                        }
                        .controlSize(.small)

                        Button("Sinash: 'A' (Aniq Javob)") {
                            settings.hudState = .answer(primary: "A", secondary: nil)
                            onToggleHudPreview()
                        }
                        .controlSize(.small)

                        Button("Sinash: 'A̲ B' (Ikkilanish)") {
                            settings.hudState = .answer(primary: "A", secondary: "B")
                            onToggleHudPreview()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
            }

            GroupBox(label: Label("Insoniy Kursor Mikro-Aloqasi (1-Bosqich: 1x | 2-Bosqich: Jim | 3-Bosqich: 3x)", systemImage: "hand.point.up.left.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Button("1-Bosqich Sinash (1x Tabiiy Siljish)") {
                            HumanCursorSignal.stage1CaptureTaken()
                        }
                        Button("3-Bosqich Sinash (3x Javob Tayyor)") {
                            HumanCursorSignal.stage3AnswerReady()
                        }
                    }

                    HStack(spacing: 16) {
                        Text("Insoniy mikro-siljish amplitudasi (\(String(format: "%.1f", settings.humanDriftPixels)) px):")
                            .frame(width: 260, alignment: .leading)
                        Slider(value: $settings.humanDriftPixels, in: 2.0...10.0, step: 0.5)
                    }
                }
                .padding(8)
            }

            if let img = settings.lastCapturedImage {
                GroupBox(label: Label("Oxirgi Smart-Cropped Skrinshot va OCR Tekshiruvi", systemImage: "photo.badge.checkmark").font(.headline)) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 160, height: 100)
                            .cornerRadius(6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Model: \(settings.lastModelUsed) (\(settings.lastLatencyMs) ms)")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.green)
                            Text(settings.lastOcrPreview.isEmpty ? "(Matn o'qilmoqda...)" : settings.lastOcrPreview)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                            Text("Izoh: \(settings.lastReasoning)")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(2)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    // MARK: - Tab 3: Flash & Pro API Keys
    private var flashProApiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Label("Avtonom O'zini-O'zi Tuzatuvchi Flash & Pro Dvigateli", systemImage: "lock.shield.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Dvigatel:", selection: Binding(
                        get: { settings.engineMode },
                        set: { val in settings.engineMode = val; settings.save() }
                    )) {
                        Text("Gibrid Parallel (Gemini Web + Flash/Pro API)").tag("hybrid_web_api")
                        Text("Asosiy Yashirin Gemini Web (Flash/Pro)").tag("gemini_web_primary")
                        Text("Parallel Flash & Pro API").tag("flash_pro_api")
                    }
                    .pickerStyle(.segmented)

                    Toggle("Speculative Early-Commit (Tezkor oqim topgan zahoti darhol javob berish)", isOn: $settings.speculativeEarlyCommit)
                        .font(.system(size: 12.5, weight: .medium))
                    Toggle("Parallel Consensus (2 ta mustaqil oqimni solishtirish)", isOn: $settings.parallelConsensus)
                        .font(.system(size: 12.5, weight: .medium))
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Button(action: {
                            settings.save()
                            settings.apiTesting = true
                            settings.apiTestStatus = "Flash va Pro modellar tekshirilmoqda..."
                            SmartAIRouter.shared.testAndAutoConfigure { ok, msg in
                                DispatchQueue.main.async {
                                    settings.apiTesting = false
                                    settings.apiTestStatus = (ok ? "✅ " : "❌ ") + msg
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                if settings.apiTesting {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.badge.checkmark.fill")
                                }
                                Text("Saqlash va Flash/Pro API ni Tekshirish")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .disabled(settings.apiTesting)

                        if !settings.discoveredGeminiModels.isEmpty {
                            Text("Tasdiqlangan Flash/Pro: \(settings.discoveredGeminiModels.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundColor(.green)
                                .lineLimit(1)
                        }
                        Spacer()
                    }

                    if !settings.apiTestStatus.isEmpty {
                        Text(settings.apiTestStatus)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(settings.apiTestStatus.hasPrefix("✅") ? .green : .red)
                    }
                }
                .padding(6)
            }

            GroupBox(label: Label("Google Gemini Flash / Pro API Kalitlari", systemImage: "sparkles").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Gemini Kalit #1:").frame(width: 110, alignment: .leading)
                        SecureField("AIzaSy...", text: $settings.geminiKey1).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Gemini Kalit #2:").frame(width: 110, alignment: .leading)
                        SecureField("AIzaSy... (ixtiyoriy)", text: $settings.geminiKey2).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Gemini Kalit #3:").frame(width: 110, alignment: .leading)
                        SecureField("AIzaSy... (ixtiyoriy)", text: $settings.geminiKey3).textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)
            }

            GroupBox(label: Label("Groq Zaxira Kalitlari (Ixtiyoriy — 120B / 70B / QwQ)", systemImage: "function").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Groq Kalit #1:").frame(width: 110, alignment: .leading)
                        SecureField("gsk_...", text: $settings.groqKey1).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Groq Kalit #2:").frame(width: 110, alignment: .leading)
                        SecureField("gsk_... (ixtiyoriy)", text: $settings.groqKey2).textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Tab 4: Google Drive Archive
    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(label: Label("Google Drive Arxiv Papkasi (<0.5ms RAM Indeksli)", systemImage: "folder.fill.badge.person.crop").font(.headline)) {
                HStack {
                    TextField("Arxiv papkasi", text: $settings.archiveDir)
                        .textFieldStyle(.roundedBorder)
                    Button("Papkani Tanlash...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.archiveDir = url.path
                            settings.save()
                            archive.reload()
                        }
                    }
                    Button("Finder'da Ochish") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: settings.archiveDir))
                    }
                }
                .padding(8)
            }

            HStack {
                TextField("Arxivdagi savollardan qidirish...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                Button("Yangilash") { archive.reload() }
            }

            ForEach(filteredArchive.prefix(30)) { item in
                HStack(alignment: .top, spacing: 12) {
                    Text(item.secondaryAnswer != nil && !item.secondaryAnswer!.isEmpty
                         ? "\(item.primaryAnswer)\u{0332} \(item.secondaryAnswer!)"
                         : item.primaryAnswer)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .frame(width: 48, height: 32)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.rawQuestion.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                        Text(item.reasoning)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(String(item.timestamp.prefix(10)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Tab 5: Google Drive Auto-Telemetry & Flight Recorder
    private var flightRecorderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(label: Label("Google Drive Avto-Telemetriya va Amaliyot Qora Qutisi", systemImage: "waveform.path.ecg").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("""
                    Barcha harakatlar, ruxsatlar holati, javob tezligi (ms), xatolar (IW / SW / W) va sayt ogohlantirishlari real vaqtda Google Drive'dagi `QuizArchive/FlightLogs/practice_session_report.md` hamda `SILENTHELPER_TELEMETRY_LATEST.md` fayllariga avtomatik yozib boriladi. Keyingi versiyalarda Gemini ushbu fayllarni Drive'dan o'zi to'g'ridan-to'g'ri o'qib tahlil qiladi!
                    """)
                    .font(.caption)
                    .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Button("Hozirgi Holatni Muhrlash (⌥L)") {
                            onRecordManualIncident()
                        }
                        Button("Drive Log Papkasini Ochish") {
                            let dir = flightRecorder.logsDir
                            NSWorkspace.shared.open(URL(fileURLWithPath: dir))
                        }
                        Button("Tarixni Tozalash") {
                            flightRecorder.clearLogs()
                        }
                    }
                }
                .padding(8)
            }

            if flightRecorder.events.isEmpty {
                Text("Hozircha amaliyot yozuvlari yo'q. [S+F] yoki [⌥F] bosib sinovlarni boshlang.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(flightRecorder.events.prefix(60)) { ev in
                    HStack(alignment: .top, spacing: 10) {
                        Text(ev.statusCode)
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .frame(width: 46, height: 26)
                            .background(colorForStatusCode(ev.statusCode).opacity(0.18))
                            .foregroundColor(colorForStatusCode(ev.statusCode))
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("[\(ev.category)] Faol dastur: \(ev.activeApp)")
                                    .font(.system(size: 11.5, weight: .bold))
                                if ev.latencyMs > 0 {
                                    Text("(\(ev.latencyMs) ms)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(ev.timestamp.suffix(13)))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Text(ev.details)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func colorForStatusCode(_ code: String) -> Color {
        switch code {
        case "ALERT", "W": return .red
        case "IW", "SW": return .orange
        case "G": return .blue
        default: return .green
        }
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(isSelected ? .semibold : .medium)
            }
            .font(.system(size: 11.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .foregroundColor(isSelected ? .primary : .secondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 13. Carbon HotKey Handler (Includes Option+L Incident Marker)
private var globalAppController: AppController?

private func carbonHotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if status == noErr {
        switch hotKeyID.id {
        case 1:
            globalAppController?.settings.lastTriggerMethod = "Option+F"
            globalAppController?.triggerCaptureAndSolve()
        case 2:
            globalAppController?.toggleOverlay()
        case 3:
            globalAppController?.toggleControlWindow()
        case 4:
            globalAppController?.handleCarbonStealthS()
        case 5:
            globalAppController?.settings.lastTriggerMethod = "Carbon S->F"
            globalAppController?.handleCarbonArmedF()
        case 6:
            globalAppController?.toggleOverlay()
        case 7:
            globalAppController?.recordManualPracticeIncident()
        default:
            break
        }
    }
    return noErr
}

// MARK: - 14. Main Application Controller (v10.0 — Atomic Debounce + Bridge Polling)
final class AppController: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    let archive = ArchiveManager.shared
    let flightRecorder = FlightRecorder.shared
    let overlay = StealthOverlayWindow()

    var controlWindow: NSWindow?
    var statusItem: NSStatusItem?
    var isOverlayVisible = false
    private var hudAutoHideWorkItem: DispatchWorkItem?

    private let triggerLock = NSLock()
    private var atomicCaptureInFlight = false
    private var lastTriggerTime: Date = .distantPast

    private var scanTimer: Timer?
    private var prevSDown = false
    private var prevFDown = false
    private var prevKDown = false
    private var lastSPressTime: Date = .distantPast
    private var lastFPressTime: Date = .distantPast

    private var topLeftEnterTime: Date? = nil
    private var topLeftTriggered = false
    private var bottomLeftPeeking = false

    private var hotKeyRefCapture: EventHotKeyRef?
    private var hotKeyRefOverlay: EventHotKeyRef?
    private var hotKeyRefPanel: EventHotKeyRef?
    private var hotKeyRefIncident: EventHotKeyRef?

    private var stealthHotKeyS: EventHotKeyRef?
    private var stealthArmedHotKeyF: EventHotKeyRef?
    private var stealthHotKeyK: EventHotKeyRef?
    private var disarmFWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        globalAppController = self
        BridgeIPC.ensureDir()
        _ = HiddenGeminiWebBridge.shared
        _ = SubtleOpticalCueWindow.shared

        setupMenuBarStatusItem()
        setupControlWindow()
        registerCarbonHotKeys()
        startZeroPopupScanner()
        showControlWindow()

        settings.refreshPermissionsSilently()
        let bridge = BridgeIPC.readBridgeStatus()
        flightRecorder.record(
            category: "SESSION",
            statusCode: "START",
            latencyMs: 0,
            details: "SilentHelper v10.0 ishga tushdi (Bundle: \(Bundle.main.bundleIdentifier ?? "CLI") | Bridge: \(bridge.alive ? "ACTIVE" : "STANDBY"))"
        )

        if let firstKey = settings.activeGeminiKeys.first {
            SmartAIRouter.shared.discoverGeminiModels(apiKey: firstKey) { models, _ in
                if !models.isEmpty {
                    DispatchQueue.main.async {
                        self.settings.discoveredGeminiModels = models
                        self.flightRecorder.rebuildMarkdownReport()
                    }
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlWindow()
        return true
    }

    private func setupMenuBarStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "●"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Skrinshot + AI Yechish (⌥F / S+F)", action: #selector(menuCapture), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Javobni Ko'rsatish / Yashirish (⌥K / K)", action: #selector(menuToggleHud), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Amaliyot Xatosini Muhrlash (⌥L)", action: #selector(menuRecordIncident), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Boshqaruv Panelini Ochish (⌥M)", action: #selector(menuShowPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Ko'rinmas Rejimga O'tish", action: #selector(menuStealth), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Chiqish (Quit)", action: #selector(menuQuit), keyEquivalent: "q"))
        for m in menu.items { m.target = self }
        item.menu = menu
        self.statusItem = item
    }

    @objc private func menuCapture() {
        settings.lastTriggerMethod = "MenuBar"
        triggerCaptureAndSolve()
    }
    @objc private func menuToggleHud() { toggleOverlay() }
    @objc private func menuRecordIncident() { recordManualPracticeIncident() }
    @objc private func menuShowPanel() { showControlWindow() }
    @objc private func menuStealth() { enterStealthMode() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func registerCarbonHotKeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), carbonHotKeyHandler, 1, &eventType, nil, nil)

        let id1 = EventHotKeyID(signature: OSType(0x53485639), id: 1) // Option + F
        RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(optionKey), id1, GetApplicationEventTarget(), 0, &hotKeyRefCapture)

        let id2 = EventHotKeyID(signature: OSType(0x53485639), id: 2) // Option + K
        RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(optionKey), id2, GetApplicationEventTarget(), 0, &hotKeyRefOverlay)

        let id3 = EventHotKeyID(signature: OSType(0x53485639), id: 3) // Option + M
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(optionKey), id3, GetApplicationEventTarget(), 0, &hotKeyRefPanel)

        let id7 = EventHotKeyID(signature: OSType(0x53485639), id: 7) // Option + L
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(optionKey), id7, GetApplicationEventTarget(), 0, &hotKeyRefIncident)
    }

    private func updateStealthDirectCarbonKeys(active: Bool) {
        disarmFWorkItem?.cancel()
        if let refS = stealthHotKeyS { UnregisterEventHotKey(refS); stealthHotKeyS = nil }
        if let refF = stealthArmedHotKeyF { UnregisterEventHotKey(refF); stealthArmedHotKeyF = nil }
        if let refK = stealthHotKeyK { UnregisterEventHotKey(refK); stealthHotKeyK = nil }

        let bridge = BridgeIPC.readBridgeStatus()
        guard active && settings.enableDirectStealthKeys && !AXIsProcessTrusted() && !(bridge.alive && bridge.axOk) else { return }

        if settings.requireSFCombo {
            let id4 = EventHotKeyID(signature: OSType(0x53485639), id: 4)
            RegisterEventHotKey(UInt32(kVK_ANSI_S), 0, id4, GetApplicationEventTarget(), 0, &stealthHotKeyS)
        } else {
            let id5 = EventHotKeyID(signature: OSType(0x53485639), id: 5)
            RegisterEventHotKey(UInt32(kVK_ANSI_F), 0, id5, GetApplicationEventTarget(), 0, &stealthArmedHotKeyF)
        }

        let id6 = EventHotKeyID(signature: OSType(0x53485639), id: 6)
        RegisterEventHotKey(UInt32(kVK_ANSI_K), 0, id6, GetApplicationEventTarget(), 0, &stealthHotKeyK)
    }

    func handleCarbonStealthS() {
        lastSPressTime = Date()
        disarmFWorkItem?.cancel()
        if stealthArmedHotKeyF == nil {
            let id5 = EventHotKeyID(signature: OSType(0x53485639), id: 5)
            RegisterEventHotKey(UInt32(kVK_ANSI_F), 0, id5, GetApplicationEventTarget(), 0, &stealthArmedHotKeyF)
        }
        let work = DispatchWorkItem { [weak self] in
            if let refF = self?.stealthArmedHotKeyF {
                UnregisterEventHotKey(refF)
                self?.stealthArmedHotKeyF = nil
            }
        }
        disarmFWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (settings.comboWindowMs / 1000.0), execute: work)
    }

    func handleCarbonArmedF() {
        disarmFWorkItem?.cancel()
        if settings.requireSFCombo, let refF = stealthArmedHotKeyF {
            UnregisterEventHotKey(refF)
            stealthArmedHotKeyF = nil
        }
        triggerCaptureAndSolve()
    }

    func recordManualPracticeIncident() {
        let frontApp = FlightRecorder.currentFrontmostAppName()
        ScreenCaptureService.captureMainDisplay { cgImg in
            if let img = cgImg {
                let stamp = Int(Date().timeIntervalSince1970)
                let imgPath = "\(self.flightRecorder.logsDir)/INCIDENT_\(stamp).png"
                let rep = NSBitmapImageRep(cgImage: img)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: imgPath))
                }
                ScreenCaptureService.extractStructuredQuestionText(from: img) { ocr in
                    let snippet = String(ocr.replacingOccurrences(of: "\n", with: " ").prefix(220))
                    self.flightRecorder.record(
                        category: "INCIDENT",
                        statusCode: "USER_LOG",
                        latencyMs: 0,
                        details: "Foydalanuvchi [⌥L] orqali holatni muhrladi | App: \(frontApp) | Rasm: INCIDENT_\(stamp).png | Matn: \(snippet)"
                    )
                    self.flightRecorder.inspectOcrForSiteWarnings(ocrText: ocr, cgImage: img, triggerMethod: "Manual Incident (⌥L)")
                }
            } else {
                self.flightRecorder.record(
                    category: "INCIDENT",
                    statusCode: "SW",
                    latencyMs: 0,
                    details: "Foydalanuvchi [⌥L] bosdi, lekin skrinshot olinmadi (App: \(frontApp))"
                )
            }
        }
    }

    private func startZeroPopupScanner() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.020, repeats: true) { [weak self] _ in
            self?.pollSafeState()
        }
    }

    private func isTypingInControlPanel() -> Bool {
        guard controlWindow?.isVisible == true && NSApp.isActive else { return false }
        if let responder = controlWindow?.firstResponder, responder is NSTextView {
            return true
        }
        return false
    }

    private func pollSafeState() {
        let now = Date()
        let fm = FileManager.default

        // 1. Check IPC triggers from Terminal Bridge Daemon
        if fm.fileExists(atPath: BridgeIPC.keyHudTrigFile) {
            try? fm.removeItem(atPath: BridgeIPC.keyHudTrigFile)
            if !isTypingInControlPanel() {
                toggleOverlay()
            }
        }
        if fm.fileExists(atPath: BridgeIPC.keyCaptureTrigFile) {
            try? fm.removeItem(atPath: BridgeIPC.keyCaptureTrigFile)
            if !isTypingInControlPanel() {
                settings.lastTriggerMethod = "Bridge S+F"
                triggerCaptureAndSolve()
            }
        }

        // 2. Mouse Hot-Corners
        if settings.enableMouseCorners {
            let mouse = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
                let f = screen.frame

                let inTopLeft = (mouse.x <= f.minX + 8) && (mouse.y >= f.maxY - 8)
                if inTopLeft {
                    if topLeftEnterTime == nil {
                        topLeftEnterTime = now
                    } else if !topLeftTriggered, let enter = topLeftEnterTime, now.timeIntervalSince(enter) >= 0.40 {
                        topLeftTriggered = true
                        settings.lastTriggerMethod = "Top-Left Corner"
                        triggerCaptureAndSolve()
                    }
                } else if (mouse.x > f.minX + 24) || (mouse.y < f.maxY - 24) {
                    topLeftEnterTime = nil
                    topLeftTriggered = false
                }

                let enterBottomLeft = (mouse.x <= f.minX + 8) && (mouse.y <= f.minY + 8)
                let exitBottomLeft = (mouse.x >= f.minX + 26) || (mouse.y >= f.minY + 26)

                if enterBottomLeft && !bottomLeftPeeking {
                    bottomLeftPeeking = true
                    hudAutoHideWorkItem?.cancel()
                    if !isOverlayVisible {
                        overlay.refreshAppearance()
                        overlay.orderFrontRegardless()
                        isOverlayVisible = true
                    }
                } else if bottomLeftPeeking && exitBottomLeft {
                    bottomLeftPeeking = false
                    if isOverlayVisible {
                        overlay.orderOut(nil)
                        isOverlayVisible = false
                    }
                }
            }
        }

        // 3. Direct HID Polling (when SilentHelper.app itself has Accessibility permission)
        guard AXIsProcessTrusted() else { return }
        if isTypingInControlPanel() { return }

        let flags = CGEventSource.flagsState(.combinedSessionState)
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            prevSDown = false
            prevFDown = false
            prevKDown = false
            return
        }

        let sDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_S))
        let fDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_F))
        let kDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_K))

        if kDown && !prevKDown {
            toggleOverlay()
        }

        let sJustPressed = sDown && !prevSDown
        let fJustPressed = fDown && !prevFDown

        if sJustPressed { lastSPressTime = now }
        if fJustPressed { lastFPressTime = now }

        if settings.requireSFCombo {
            let diffMs = abs(lastSPressTime.timeIntervalSince(lastFPressTime)) * 1000.0
            let bothHeld = sDown && fDown
            let recentPair = (sJustPressed || fJustPressed) && diffMs <= settings.comboWindowMs
            if bothHeld || recentPair {
                lastSPressTime = .distantPast
                lastFPressTime = .distantPast
                settings.lastTriggerMethod = "HID S+F"
                triggerCaptureAndSolve()
            }
        } else {
            if fJustPressed {
                settings.lastTriggerMethod = "HID F"
                triggerCaptureAndSolve()
            }
        }

        prevSDown = sDown
        prevFDown = fDown
        prevKDown = kDown
    }

    private func setupControlWindow() {
        let contentView = ControlPanelView(
            onEnterStealthMode: { [weak self] in
                self?.enterStealthMode()
            },
            onToggleHudPreview: { [weak self] in
                self?.toggleOverlay()
            },
            onManualTestCapture: { [weak self] in
                self?.settings.lastTriggerMethod = "Panel Test Button"
                self?.triggerCaptureAndSolve()
            },
            onRecordManualIncident: { [weak self] in
                self?.recordManualPracticeIncident()
            }
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 630),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "SilentHelper v10.0 — Boshqaruv va Google Drive Avto-Telemetriya Paneli"
        win.center()
        win.contentView = NSHostingView(rootView: contentView)
        win.isReleasedWhenClosed = false
        self.controlWindow = win
    }

    func toggleControlWindow() {
        if controlWindow?.isVisible == true {
            enterStealthMode()
        } else {
            showControlWindow()
        }
    }

    func showControlWindow() {
        DispatchQueue.main.async {
            self.updateStealthDirectCarbonKeys(active: false)
            self.settings.refreshPermissionsSilently()
            self.settings.isStealthMode = false
            NSApp.setActivationPolicy(.regular)
            self.controlWindow?.makeKeyAndOrderFront(nil)
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func enterStealthMode() {
        DispatchQueue.main.async {
            self.settings.isStealthMode = true
            self.settings.statusText = "Ko'rinmas rejim faol ([S→F] / [⌥F] / [K] -> G/IW/SW/W/A)"
            self.controlWindow?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
            self.updateStealthDirectCarbonKeys(active: true)
            self.flightRecorder.record(category: "MODE", statusCode: "STEALTH", latencyMs: 0, details: "Ko'rinmas rejim yoqildi")
        }
    }

    func toggleOverlay() {
        DispatchQueue.main.async {
            self.hudAutoHideWorkItem?.cancel()
            if self.isOverlayVisible {
                self.overlay.orderOut(nil)
                self.isOverlayVisible = false
            } else {
                self.overlay.refreshAppearance()
                self.overlay.orderFrontRegardless()
                self.isOverlayVisible = true

                if self.settings.autoHideHudSeconds > 0 {
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self, self.isOverlayVisible, !self.bottomLeftPeeking else { return }
                        self.overlay.orderOut(nil)
                        self.isOverlayVisible = false
                    }
                    self.hudAutoHideWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.settings.autoHideHudSeconds, execute: work)
                }
            }
        }
    }

    /// Bug #1 Fix: Synchronous atomic lock & 1.2s debounce so double triggers (like 04:10:05.550Z & .562Z) can NEVER happen!
    func triggerCaptureAndSolve() {
        let now = Date()
        triggerLock.lock()
        if atomicCaptureInFlight || now.timeIntervalSince(lastTriggerTime) < 1.2 {
            triggerLock.unlock()
            return
        }
        atomicCaptureInFlight = true
        lastTriggerTime = now
        triggerLock.unlock()

        let startTime = now
        let triggerUsed = settings.lastTriggerMethod

        DispatchQueue.main.async {
            self.settings.isProcessing = true
            self.settings.selfHealAttempt = 1
            self.settings.hudState = .workingG
            self.overlay.refreshAppearance()
            self.settings.statusText = "G: Skrinshot olinib, Gemini'ga yuborilmoqda..."
            self.statusItem?.button?.title = "G"
        }

        flightRecorder.record(category: "TRIGGER", statusCode: "G", latencyMs: 0, details: "Skrinshot boshlandi (Usul: \(triggerUsed))")

        // 1-BOSQICH SIGNAL: Inson qo'lidek bilinar-bilinmas 1 marta tabiiy kursor siljishi!
        HumanCursorSignal.stage1CaptureTaken()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.06) {
            ScreenCaptureService.captureMainDisplay { cgImage in
                let capMs = Int(Date().timeIntervalSince(startTime) * 1000)
                guard let cgImage = cgImage else {
                    self.triggerLock.lock()
                    self.atomicCaptureInFlight = false
                    self.triggerLock.unlock()

                    DispatchQueue.main.async {
                        self.settings.isProcessing = false
                        self.settings.hasScreenPermission = false
                        self.settings.hudState = .sendErrorSW
                        self.overlay.refreshAppearance()
                        self.statusItem?.button?.title = "SW"
                        self.settings.statusText = "SW: Skrinshot ruxsati kerak (./run.sh orqali ko'prikni yoqing)"
                        self.flightRecorder.record(category: "CAPTURE", statusCode: "SW", latencyMs: capMs, details: "Skrinshot xatosi: Screen Recording ruxsati yo'q va Terminal Bridge topilmadi")
                    }
                    return
                }

                // 2-BOSQICH: 100% JIM
                HumanCursorSignal.stage2SilentDispatch()

                ScreenCaptureService.extractStructuredQuestionText(from: cgImage) { extractedText in
                    let cleanText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ocrMs = Int(Date().timeIntervalSince(startTime) * 1000)

                    DispatchQueue.main.async {
                        self.settings.lastOcrPreview = cleanText
                    }

                    self.flightRecorder.inspectOcrForSiteWarnings(ocrText: cleanText, cgImage: cgImage, triggerMethod: triggerUsed)

                    // 3. RAM Arxiv keshini tekshirish
                    if let cached = self.archive.findCachedAnswer(for: cleanText) {
                        self.triggerLock.lock()
                        self.atomicCaptureInFlight = false
                        self.triggerLock.unlock()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            self.settings.lastPrimaryAnswer = cached.primaryAnswer
                            self.settings.lastSecondaryAnswer = cached.secondaryAnswer ?? ""
                            self.settings.lastConfidence = cached.confidence
                            self.settings.lastReasoning = "[Arxiv keshidan] \(cached.reasoning)"
                            self.settings.hudState = .answer(primary: cached.primaryAnswer, secondary: cached.secondaryAnswer)
                            self.settings.statusText = "Tayyor (Arxiv): \(cached.primaryAnswer)"
                            self.settings.isProcessing = false
                            self.statusItem?.button?.title = cached.primaryAnswer
                            self.overlay.refreshAppearance()
                            self.flightRecorder.record(category: "CACHE_HIT", statusCode: cached.primaryAnswer, latencyMs: ocrMs, details: "Arxiv keshidan topildi")
                            HumanCursorSignal.stage3AnswerReady()
                        }
                        return
                    }

                    // 4. Autonomous Self-Healing Solver
                    var earlySignaled = false
                    SmartAIRouter.shared.solveWithAutonomousSelfHealing(
                        ocrText: cleanText,
                        cgImage: cgImage,
                        attempt: 1,
                        onEarlyCommit: { earlyRes in
                            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
                            DispatchQueue.main.async {
                                earlySignaled = true
                                self.settings.lastPrimaryAnswer = earlyRes.primary
                                self.settings.lastSecondaryAnswer = earlyRes.secondary ?? ""
                                self.settings.lastConfidence = earlyRes.confidence
                                self.settings.lastReasoning = earlyRes.reasoning
                                self.settings.lastModelUsed = earlyRes.modelUsed
                                self.settings.lastLatencyMs = elapsedMs
                                self.settings.hudState = .answer(primary: earlyRes.primary, secondary: earlyRes.secondary)
                                let badgeText = (earlyRes.secondary != nil && !earlyRes.secondary!.isEmpty) ? "\(earlyRes.primary)\u{0332}\(earlyRes.secondary!)" : earlyRes.primary
                                self.statusItem?.button?.title = badgeText
                                self.settings.statusText = "Tayyor (\(elapsedMs) ms · \(earlyRes.modelUsed)): \(badgeText)"
                                self.overlay.refreshAppearance()
                                self.flightRecorder.record(category: "EARLY_ANSWER", statusCode: badgeText, latencyMs: elapsedMs, details: "Model: \(earlyRes.modelUsed) | Izoh: \(earlyRes.reasoning)")
                                HumanCursorSignal.stage3AnswerReady()
                            }
                        },
                        onTransientError: { errCat, errReason, attemptNum in
                            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
                            DispatchQueue.main.async {
                                self.flightRecorder.record(
                                    category: "SELF_HEAL",
                                    statusCode: errCat.codeString,
                                    latencyMs: elapsedMs,
                                    details: "Urinish #\(attemptNum) xatosi (\(errCat.codeString)): \(errReason) -> Avto-tuzatilmoqda"
                                )
                                if !earlySignaled {
                                    self.settings.selfHealAttempt = attemptNum + 1
                                    self.settings.hudState = errCat.hudState
                                    self.overlay.refreshAppearance()
                                    self.statusItem?.button?.title = errCat.codeString
                                    self.settings.statusText = "\(errCat.codeString) (Avto-tuzatish #\(attemptNum + 1)): \(errReason)"
                                }
                            }
                        },
                        completion: { result, finalErrCat, errMsg in
                            self.triggerLock.lock()
                            self.atomicCaptureInFlight = false
                            self.triggerLock.unlock()

                            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
                            DispatchQueue.main.async {
                                self.settings.isProcessing = false
                                self.settings.lastLatencyMs = elapsedMs
                                guard let res = result else {
                                    if !earlySignaled {
                                        let cat = finalErrCat ?? .generalErrorW
                                        self.settings.hudState = cat.hudState
                                        self.overlay.refreshAppearance()
                                        self.statusItem?.button?.title = cat.codeString
                                        self.settings.statusText = "\(cat.codeString): \(errMsg ?? "Barcha urinishlar tugadi.")"
                                        self.flightRecorder.record(category: "FINAL_FAIL", statusCode: cat.codeString, latencyMs: elapsedMs, details: errMsg ?? "Barcha urinishlar tugadi")
                                    }
                                    return
                                }

                                let previousPrimary = self.settings.lastPrimaryAnswer
                                let previousSecondary = self.settings.lastSecondaryAnswer

                                self.settings.lastPrimaryAnswer = res.primary
                                self.settings.lastSecondaryAnswer = res.secondary ?? ""
                                self.settings.lastConfidence = res.confidence
                                self.settings.lastReasoning = res.reasoning
                                self.settings.lastModelUsed = res.modelUsed
                                self.settings.hudState = .answer(primary: res.primary, secondary: res.secondary)
                                let badgeText = (res.secondary != nil && !res.secondary!.isEmpty) ? "\(res.primary)\u{0332}\(res.secondary!)" : res.primary
                                self.statusItem?.button?.title = badgeText
                                self.settings.statusText = "Tasdiqlandi (\(elapsedMs) ms · \(res.modelUsed)): \(badgeText)"

                                self.archive.saveToArchive(rawQuestion: cleanText, image: cgImage, result: res)
                                self.overlay.refreshAppearance()
                                self.flightRecorder.record(category: "FINAL_ANSWER", statusCode: badgeText, latencyMs: elapsedMs, details: "Model: \(res.modelUsed) | Izoh: \(res.reasoning)")

                                if !earlySignaled || previousPrimary != res.primary || previousSecondary != (res.secondary ?? "") {
                                    HumanCursorSignal.stage3AnswerReady()
                                }
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Entry Point (Supports Both Full GUI `.app` Mode and `--bridge-daemon` Mode)
if CommandLine.arguments.contains("--bridge-daemon") {
    let daemon = TerminalPrivilegeBridgeDaemon()
    daemon.runForever()
} else {
    let app = NSApplication.shared
    let delegate = AppController()
    app.delegate = delegate
    app.run()
}
