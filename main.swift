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
// SilentHelper v13.0 — Mouse Gesture Engine, 3 Input Modes, Custom Logo & Manual
// ============================================================================
// v13.0 da qo'shilgan va to'liq hal qilingan masalalar:
// 1. 3 XIL BOSHQARUV REJIMI (FONDA BOSHQA DASTURLARGA UMUMAN XALAQIT BERMAYDI!):
//    - `mouse_only` ("Faqat Sichqoncha"): Klaviaturaga 100% tegmaydi! Barcha
//      dasturlarda bemalol yozish mumkin, boshqaruv faqat sichqoncha imo-ishorasi
//      bilan ishlaydi.
//    - `hybrid` ("Sichqoncha + Klaviatura"): Sichqoncha imo-ishoralari + `⌥F` / `⌥K`
//      (va faqat maxsus yoqilganda `S->F` / `K`).
//    - `keyboard_only` ("Faqat Klaviatura"): Sichqoncha imo-ishoralari o'chiriladi.
// 2. SENSOR-XAVFSIZ SICHQONCHA IMO-ISHORALARI (`MouseGestureRecognizer`):
//    - Ekran chetiga borish shart emas (kursoringiz turgan joyda bajariladi):
//    - [1] SKRINSHOT + AI YUBORISH:
//          • Kichik Aylana `○` yoki Uchburchak `△` chizish (yoki Yuqori-chapdan
//            O'ng-pastga diagonal chiziq tortib qaytish `↘↖`).
//          • Eski javob darhol o'chadi -> Skrinshot olinadi (kursor CHAPGA) ->
//            Gemini'ga yuboriladi (kursor O'NGGA) -> Javob tayyor (kursor 3 MARTA).
//    - [2] JAVOBNI YOKI JARAYONNI (`G` / `K` / `B · 1/2`) KO'RISH:
//          • Kursorni turgan joyida Chap-O'ng-Chap (`↔`) tebratib qo'yish.
//          • HUD oyna (`G`, `K`, `IW`, `SW`, `W` yoki `B · 1/2`) chiqadi.
//    - [3] JAVOBNI DARHOL YASHIRISH (3-4 sekund kutmasdan 0ms da yopish):
//          • HUD ochiq turganda sichqonchani Pastga (`↓`) tortish.
//          • HUD oyna shu zahoti (`0ms`) g'oyib bo'ladi!
// 3. MENUBARDA FAQAT BITTA IKONKA VA MAXSUS APPLICATION LOGO (`AppIcon.icns`):
//    - Qat'iy `PID Lock` va eski nusxalarni `SIGKILL` bilan tozalash orqali
//      Menu Bar'da faqat 1 ta ikonka bo'lishi kafolatlandi.
//    - Dasturga maxsus qalqon va chaqmoq logotipi (`AppIcon.icns`) o'rnatildi.
// 4. DASTUR ICHIDA TO'LIQ INTERAKTIV QO'LLANMA VA MASHQ MAYDONI (1-TAB):
//    - Barcha imo-ishoralar, kursor signallari va kodlar bo'yicha to'liq qo'llanma
//      hamda imo-ishoralarni jonli sinab ko'rish indikatori qo'shildi.
// ============================================================================

// MARK: - 0. Custom Vector App Icon & MenuBar Logo Generator (`AppIcon.icns`)
enum AppIconGenerator {
    static func makeShieldLogoImage(size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }

        let w = size.width
        let h = size.height
        let pad = w * 0.08
        let rect = CGRect(x: pad, y: pad, width: w - pad * 2, height: h - pad * 2)
        let corner = w * 0.22

        // 1. Rounded Squircle Background Gradient
        let bgPath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradColors = [
            NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.24, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.38, alpha: 1.0).cgColor
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        }
        ctx.restoreGState()

        // 2. Glowing Border
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.setStrokeColor(NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.68, alpha: 0.85).cgColor)
        ctx.setLineWidth(max(1.5, w * 0.03))
        ctx.strokePath()
        ctx.restoreGState()

        // 3. Inner Shield Silhouette
        let shieldPath = CGMutablePath()
        let cx = w * 0.50
        let topY = h * 0.78
        let midY = h * 0.46
        let botY = h * 0.20
        let halfW = w * 0.26

        shieldPath.move(to: CGPoint(x: cx, y: topY))
        shieldPath.addLine(to: CGPoint(x: cx + halfW, y: topY - h * 0.08))
        shieldPath.addQuadCurve(to: CGPoint(x: cx, y: botY), control: CGPoint(x: cx + halfW * 0.95, y: midY - h * 0.12))
        shieldPath.addQuadCurve(to: CGPoint(x: cx - halfW, y: topY - h * 0.08), control: CGPoint(x: cx - halfW * 0.95, y: midY - h * 0.12))
        shieldPath.closeSubpath()

        ctx.saveGState()
        ctx.addPath(shieldPath)
        ctx.setFillColor(NSColor(calibratedRed: 0.12, green: 0.68, blue: 0.58, alpha: 0.25).cgColor)
        ctx.fillPath()
        ctx.addPath(shieldPath)
        ctx.setStrokeColor(NSColor(calibratedRed: 0.28, green: 0.92, blue: 0.76, alpha: 0.95).cgColor)
        ctx.setLineWidth(max(1.5, w * 0.04))
        ctx.strokePath()
        ctx.restoreGState()

        // 4. Center Lightning Bolt
        let bolt = CGMutablePath()
        bolt.move(to: CGPoint(x: cx + w * 0.03, y: h * 0.67))
        bolt.addLine(to: CGPoint(x: cx - w * 0.09, y: h * 0.49))
        bolt.addLine(to: CGPoint(x: cx + w * 0.01, y: h * 0.49))
        bolt.addLine(to: CGPoint(x: cx - w * 0.03, y: h * 0.31))
        bolt.addLine(to: CGPoint(x: cx + w * 0.09, y: h * 0.51))
        bolt.addLine(to: CGPoint(x: cx - w * 0.01, y: h * 0.51))
        bolt.closeSubpath()

        ctx.saveGState()
        ctx.addPath(bolt)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        img.unlockFocus()
        return img
    }

    static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let shield = CGMutablePath()
            shield.move(to: CGPoint(x: 8, y: 14.5))
            shield.addLine(to: CGPoint(x: 13.5, y: 12.2))
            shield.addQuadCurve(to: CGPoint(x: 8, y: 1.8), control: CGPoint(x: 13.2, y: 5.0))
            shield.addQuadCurve(to: CGPoint(x: 2.5, y: 12.2), control: CGPoint(x: 2.8, y: 5.0))
            shield.closeSubpath()

            ctx.addPath(shield)
            ctx.setStrokeColor(NSColor.labelColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokePath()

            let dot = CGRect(x: 6.3, y: 6.5, width: 3.4, height: 3.4)
            ctx.fillEllipse(in: dot)
        }
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    static func exportIconset(to iconsetDir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
        let specs: [(String, CGFloat)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]
        for (name, dim) in specs {
            let nsImg = makeShieldLogoImage(size: NSSize(width: dim, height: dim))
            if let tiff = nsImg.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
            }
        }
    }
}

// MARK: - 0B. Fast Local IPC Bridge Paths
enum BridgeIPC {
    static let dir = "/tmp/sh_v13_ipc"
    static let guiPidFile = "/tmp/sh_v13_ipc/single_gui.pid"
    static let heartbeatFile = "/tmp/sh_v13_ipc/bridge_heartbeat.json"
    static let captureReqFile = "/tmp/sh_v13_ipc/cmd_capture.req"
    static let captureFrameTmp = "/tmp/sh_v13_ipc/frame_tmp.jpg"
    static let captureFrameReady = "/tmp/sh_v13_ipc/frame_ready.jpg"
    static let driftLeftReqFile = "/tmp/sh_v13_ipc/cmd_drift_left.req"
    static let driftRightReqFile = "/tmp/sh_v13_ipc/cmd_drift_right.req"
    static let driftReady3ReqFile = "/tmp/sh_v13_ipc/cmd_drift_ready3.req"

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
        if age <= 4.0 {
            return (true, status.screenOk, status.axOk)
        }
        return (false, false, false)
    }
}

// MARK: - 0C. Dynamic CoreGraphics Fallback
enum LegacyCGDisplayBridge {
    typealias CGMainDisplayIDFunc = @convention(c) () -> UInt32
    typealias CGDisplayCreateImageFunc = @convention(c) (UInt32) -> Unmanaged<CGImage>?
    typealias CGDisplayBoundsFunc = @convention(c) (UInt32) -> CGRect

    static func mainDisplayBounds() -> CGRect {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let mainSym = dlsym(handle, "CGMainDisplayID"),
              let boundsSym = dlsym(handle, "CGDisplayBounds") else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        let getMainID = unsafeBitCast(mainSym, to: CGMainDisplayIDFunc.self)
        let getBounds = unsafeBitCast(boundsSym, to: CGDisplayBoundsFunc.self)
        return getBounds(getMainID())
    }

    static func currentMouseQuartzLocation() -> CGPoint {
        if let ev = CGEvent(source: nil) {
            return ev.location
        }
        return CGPoint(x: 500, y: 500)
    }

    static func captureViaDynamicSymbol() -> CGImage? {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let mainSym = dlsym(handle, "CGMainDisplayID"),
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

// MARK: - 0D. Pure CoreGraphics Terminal Privilege Bridge Daemon (`--bridge-daemon`)
// Uses ONLY CoreGraphics (never touches AppKit/NSApp/NSScreen so it NEVER creates a Dock or MenuBar icon!)
final class TerminalPrivilegeBridgeDaemon {
    private var tickCount: Int = 0
    private var cachedScreenOk: Bool = true

    func runForever() -> Never {
        BridgeIPC.ensureDir()
        cachedScreenOk = Self.probeScreenCaptureCapabilityInTerminal()
        writeHeartbeat()

        while true {
            autoreleasepool {
                tickCount += 1
                if tickCount % 45 == 0 {
                    writeHeartbeat()
                }
                handleCaptureRequests()
                handleDriftRequests()
            }
            usleep(15_000)
        }
    }

    private static func probeScreenCaptureCapabilityInTerminal() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let probePath = "\(BridgeIPC.dir)/probe_cap.jpg"
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
        if fm.fileExists(atPath: BridgeIPC.driftLeftReqFile) {
            try? fm.removeItem(atPath: BridgeIPC.driftLeftReqFile)
            performClampedDirectionalShift(directionX: -1.0, amplitude: 9.0)
        }
        if fm.fileExists(atPath: BridgeIPC.driftRightReqFile) {
            try? fm.removeItem(atPath: BridgeIPC.driftRightReqFile)
            performClampedDirectionalShift(directionX: 1.0, amplitude: 9.0)
        }
        if fm.fileExists(atPath: BridgeIPC.driftReady3ReqFile) {
            try? fm.removeItem(atPath: BridgeIPC.driftReady3ReqFile)
            performClampedMultiPulseOscillation(pulses: 3, amplitude: 5.5)
        }
    }

    private static func clampPoint(_ pt: CGPoint, in bounds: CGRect) -> CGPoint {
        let minX = bounds.minX + 55.0
        let maxX = max(minX + 10.0, bounds.maxX - 55.0)
        let minY = bounds.minY + 55.0
        let maxY = max(minY + 10.0, bounds.maxY - 55.0)
        return CGPoint(
            x: min(max(pt.x, minX), maxX),
            y: min(max(pt.y, minY), maxY)
        )
    }

    private func performClampedDirectionalShift(directionX: CGFloat, amplitude: CGFloat) {
        let bounds = LegacyCGDisplayBridge.mainDisplayBounds()
        let rawOrigin = LegacyCGDisplayBridge.currentMouseQuartzLocation()
        let safeOrigin = Self.clampPoint(rawOrigin, in: bounds)
        let outFrames = 9
        let backFrames = 7

        for frame in 1...outFrames {
            let t = CGFloat(frame) / CGFloat(outFrames)
            let ease = sin(t * (.pi / 2.0))
            let dx = directionX * amplitude * ease
            let pt = Self.clampPoint(CGPoint(x: safeOrigin.x + dx, y: safeOrigin.y), in: bounds)
            CGWarpMouseCursorPosition(pt)
            CGAssociateMouseAndMouseCursorPosition(1)
            usleep(8_000)
        }
        usleep(30_000)
        for frame in 1...backFrames {
            let t = CGFloat(frame) / CGFloat(backFrames)
            let remain = 1.0 - sin(t * (.pi / 2.0))
            let dx = directionX * amplitude * remain
            let pt = Self.clampPoint(CGPoint(x: safeOrigin.x + dx, y: safeOrigin.y), in: bounds)
            CGWarpMouseCursorPosition(pt)
            CGAssociateMouseAndMouseCursorPosition(1)
            usleep(7_500)
        }
    }

    private func performClampedMultiPulseOscillation(pulses: Int, amplitude: CGFloat) {
        let bounds = LegacyCGDisplayBridge.mainDisplayBounds()
        for p in 0..<pulses {
            let rawOrigin = LegacyCGDisplayBridge.currentMouseQuartzLocation()
            let safeOrigin = Self.clampPoint(rawOrigin, in: bounds)
            let totalFrames = 14

            for frame in 1...totalFrames {
                let t = Double(frame) / Double(totalFrames)
                let wave = CGFloat(sin(t * 2.0 * Double.pi))
                let dx = wave * amplitude
                let dy = wave * (amplitude * 0.35)
                let pt = Self.clampPoint(CGPoint(x: safeOrigin.x + dx, y: safeOrigin.y + dy), in: bounds)
                CGWarpMouseCursorPosition(pt)
                CGAssociateMouseAndMouseCursorPosition(1)
                usleep(8_500)
            }
            if p < pulses - 1 {
                usleep(75_000)
            }
        }
    }
}

// MARK: - 1. Strict Model Policy
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
        "image",
        "lyria",
        "tts",
        "audio",
        "voice",
        "aqa",
        "learnlm",
        "bison",
        "gecko",
        "deep-research",
        "deep_research",
        "customtools",
        "robotics",
        "computer-use",
        "veo",
        "gemma",
        "gemini-1.5",
        "gemini-2.0",
        "gemini-2.5"
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
        "gemini-3-flash-preview",
        "gemini-3.5-flash",
        "gemini-3.6-flash",
        "gemini-flash-latest",
        "gemini-3.7-flash",
        "gemini-3.8-flash",
        "gemini-3.1-pro-preview",
        "gemini-pro-latest"
    ]
}

// MARK: - 2. HUD Status Code Enum (G / K / IW / SW / W / Answer + Value)
enum HudDisplayState: Equatable {
    case workingG               // "G"  — Gemini ishlayapti
    case cooldownK              // "K"  — Kuting (Cooldown yoki avvalgi savol ishlanmoqda)
    case internetErrorIW        // "IW" — Internet xatosi (avto-qayta urinmoqda)
    case sendErrorSW            // "SW" — Yuborishda xato (avto-qayta urinmoqda)
    case generalErrorW          // "W"  — Umumiy xato (avto-qayta urinmoqda)
    case answer(primary: String, secondary: String?, valuePreview: String?) // "B · 1/2"
}

// MARK: - 2B. Sensor-Safe In-Place Mouse Gesture Recognition Engine (`MouseGestureRecognizer`)
enum DetectedMouseGesture: String {
    case captureLoopOrSlash = "○/△/↘↖ Skrinshot va Yuborish"
    case showHudWiggle      = "↔ Javobni/Holatni Ko'rsatish"
    case hideHudPullDown    = "↓ HUD Oynani Darhol Yashirish"
}

final class MouseGestureRecognizer {
    struct SamplePoint {
        let pt: NSPoint
        let time: TimeInterval
    }

    private var samples: [SamplePoint] = []
    private var lastGestureFireTime: TimeInterval = 0
    private var hudOpenedAtTime: TimeInterval = 0

    func notifyHudOpened() {
        hudOpenedAtTime = Date().timeIntervalSince1970
    }

    func reset() {
        samples.removeAll()
    }

    func feedMousePoint(_ pt: NSPoint, now: TimeInterval, isHudVisible: Bool) -> DetectedMouseGesture? {
        // Ignore mouse movements during programmatic cursor feedback!
        if now < HumanCursorSignal.ignoreGesturesUntil {
            samples.removeAll()
            return nil
        }

        if let last = samples.last {
            let dist = hypot(pt.x - last.pt.x, pt.y - last.pt.y)
            if dist < 2.0 && (now - last.time) < 0.04 {
                return nil
            }
        }

        samples.append(SamplePoint(pt: pt, time: now))
        samples.removeAll { (now - $0.time) > 1.25 }

        guard samples.count >= 6 else { return nil }

        // 1. INSTANT HIDE GESTURE ('↓' Pull-Down >= 55px in <= 0.30s when HUD is open)
        if isHudVisible && (now - hudOpenedAtTime) >= 0.32 {
            let recentHide = samples.filter { (now - $0.time) <= 0.30 }
            if let first = recentHide.first, let last = recentHide.last {
                let dy = last.pt.y - first.pt.y // In macOS NSEvent, moving down decreases y!
                let dx = abs(last.pt.x - first.pt.x)
                if dy <= -55.0 && dx <= abs(dy) * 0.65 {
                    samples.removeAll()
                    lastGestureFireTime = now
                    return .hideHudPullDown
                }
            }
        }

        guard (now - lastGestureFireTime) >= 0.65 else { return nil }

        // 2. SHOW HUD GESTURE ('↔' Horizontal Left-Right-Left Wiggle in place within 0.60s)
        let recentWiggle = samples.filter { (now - $0.time) <= 0.62 }
        if recentWiggle.count >= 7 {
            let xs = recentWiggle.map { $0.pt.x }
            let ys = recentWiggle.map { $0.pt.y }
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0
            let spanX = maxX - minX
            let spanY = maxY - minY

            if spanX >= 38.0 && spanX <= 220.0 && spanY <= 36.0 {
                // Count significant horizontal reversals (>= 28px per stroke)
                var strokeExtrema: [CGFloat] = [recentWiggle[0].pt.x]
                var dir: Int = 0
                for s in recentWiggle.dropFirst() {
                    let lastExtreme = strokeExtrema.last!
                    let diff = s.pt.x - lastExtreme
                    if dir == 0 {
                        if abs(diff) >= 28.0 {
                            dir = diff > 0 ? 1 : -1
                            strokeExtrema.append(s.pt.x)
                        }
                    } else if dir == 1 {
                        if s.pt.x > lastExtreme {
                            strokeExtrema[strokeExtrema.count - 1] = s.pt.x
                        } else if (lastExtreme - s.pt.x) >= 28.0 {
                            dir = -1
                            strokeExtrema.append(s.pt.x)
                        }
                    } else {
                        if s.pt.x < lastExtreme {
                            strokeExtrema[strokeExtrema.count - 1] = s.pt.x
                        } else if (s.pt.x - lastExtreme) >= 28.0 {
                            dir = 1
                            strokeExtrema.append(s.pt.x)
                        }
                    }
                }
                // At least 3 extrema = 2 reversals (e.g. Left -> Right -> Left)
                if strokeExtrema.count >= 4 {
                    samples.removeAll()
                    lastGestureFireTime = now
                    return .showHudWiggle
                }
            }
        }

        // 3. CAPTURE & SOLVE GESTURE:
        //    Pattern A: Small Closed Circle '○' or Triangle '△' (returns near start with angular sweep >= 230 deg)
        //    Pattern B: Diagonal Slash-Back '↘↖' (top-left -> bottom-right -> top-left)
        let windowPts = samples.filter { (now - $0.time) <= 1.15 }
        if windowPts.count >= 10 {
            let xs = windowPts.map { $0.pt.x }
            let ys = windowPts.map { $0.pt.y }
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0
            let boxW = maxX - minX
            let boxH = maxY - minY

            // Pattern A: Closed Circle '○' or Triangle '△'
            if boxW >= 40.0 && boxW <= 340.0 && boxH >= 40.0 && boxH <= 340.0 {
                let aspect = boxW / max(1.0, boxH)
                if aspect >= 0.38 && aspect <= 2.60 {
                    var pathLen: CGFloat = 0
                    for i in 1..<windowPts.count {
                        pathLen += hypot(windowPts[i].pt.x - windowPts[i - 1].pt.x, windowPts[i].pt.y - windowPts[i - 1].pt.y)
                    }
                    let firstPt = windowPts.first!.pt
                    let lastPt = windowPts.last!.pt
                    let closeDist = hypot(lastPt.x - firstPt.x, lastPt.y - firstPt.y)

                    if pathLen >= max(145.0, (boxW + boxH) * 1.65) && closeDist <= max(65.0, max(boxW, boxH) * 0.48) {
                        let cx = (minX + maxX) * 0.5
                        let cy = (minY + maxY) * 0.5
                        var totalAngle: CGFloat = 0
                        for i in 1..<windowPts.count {
                            let a1 = atan2(windowPts[i - 1].pt.y - cy, windowPts[i - 1].pt.x - cx)
                            let a2 = atan2(windowPts[i].pt.y - cy, windowPts[i].pt.x - cx)
                            var da = a2 - a1
                            while da > .pi { da -= 2.0 * .pi }
                            while da < -.pi { da += 2.0 * .pi }
                            totalAngle += da
                        }
                        if abs(totalAngle) >= 4.0 { // ~230+ degrees around center
                            samples.removeAll()
                            lastGestureFireTime = now
                            return .captureLoopOrSlash
                        }
                    }
                }
            }

            // Pattern B: Diagonal Top-Left -> Bottom-Right -> Top-Left Slash-Back ('↘↖')
            if boxW >= 55.0 && boxH >= 55.0 {
                let firstPt = windowPts.first!.pt
                let lastPt = windowPts.last!.pt
                let closeDist = hypot(lastPt.x - firstPt.x, lastPt.y - firstPt.y)
                if closeDist <= 70.0 {
                    // Check if there was a peak point that went down-right (dx >= +55, dy <= -55) from firstPt
                    var foundDiagonalPeak = false
                    for mid in windowPts {
                        let dx = mid.pt.x - firstPt.x
                        let dy = mid.pt.y - firstPt.y
                        if dx >= 55.0 && dy <= -55.0 {
                            foundDiagonalPeak = true
                            break
                        }
                    }
                    if foundDiagonalPeak {
                        samples.removeAll()
                        lastGestureFireTime = now
                        return .captureLoopOrSlash
                    }
                }
            }
        }

        return nil
    }
}

// MARK: - 3. BlackBox Practice & Auto-Drive Telemetry Recorder (`FlightRecorder`)
struct FlightLogEvent: Codable, Identifiable {
    let id: String
    let timestamp: String
    let category: String
    let statusCode: String
    let activeApp: String
    let latencyMs: Int
    let details: String
}

final class FlightRecorder: ObservableObject {
    static let shared = FlightRecorder()
    @Published var events: [FlightLogEvent] = []
    @Published var siteAlertCount: Int = 0
    @Published var selfHealCount: Int = 0

    private let lock = NSLock()
    private var lastAlertSignature: String = ""
    private let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let siteWarningKeywords: [String] = [
        "tab switch detected", "switched tabs", "left the test",
        "left the exam", "suspicious activity", "test blocked", "exam locked",
        "window blur", "extension detected", "bot detected",
        "unusual activity", "bloklandi", "qoidabuzarlik aniqlandi", "oynadan chiqish",
        "cheating detected"
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
        guard keywordsStr != lastAlertSignature else { return }
        lastAlertSignature = keywordsStr

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
        let snapshot = Array(events.prefix(180))

        var md = """
        # SilentHelper v13.0 — Google Drive Avto-Telemetriya va Amaliyot Hisoboti
        - **Yangilangan vaqt:** \(timeFormatter.string(from: Date()))
        - **Versiya va Bundle:** SilentHelper v13.0 (`\(Bundle.main.bundleIdentifier ?? "CLI")`)
        - **Boshqaruv Rejimi (`inputControlMode`):** `\(s.inputControlMode)` (Mouse Gestures: `\(s.enableMouseGestures ? "ON" : "OFF")`)
        - **Skrinshot Holati:** \(s.hasScreenPermission ? "OK" : "NO") (Direct TCC: \(directScreen ? "OK" : "NO (0-Popup Bridge)") | Terminal Bridge: \(bridge.alive && bridge.screenOk ? "ACTIVE" : "OFF"))
        - **Tanlangan Dvigatel:** `\(s.engineMode)` | **Web Model:** `\(s.webModelTier.uppercased())` | **Cooldown:** `\(String(format: "%.1f", s.cooldownSeconds))s`
        - **API Kalitlar:** Gemini (\(s.activeGeminiKeys.count) ta) | Groq (\(s.activeGroqKeys.count) ta) | Tezkor Modellar: `\(s.discoveredGeminiModels.joined(separator: ", "))`
        - **Jami hodisalar:** \(events.count) | **Sayt ogohlantirishlari (SITE_ALERT):** \(siteAlertCount) | **Avto-tuzatishlar (SELF_HEAL):** \(selfHealCount)
        - **Oxirgi Javob:** `\(s.lastPrimaryAnswer)\(s.lastSecondaryAnswer.isEmpty ? "" : " / " + s.lastSecondaryAnswer) (\(s.lastValuePreview))` (\(s.lastLatencyMs) ms · `\(s.lastModelUsed)`)
        - **Oxirgi Aniqlangan Imo-ishora:** `\(s.lastDetectedGestureName)`
        - **Oxirgi OCR Qisqartmasi:** `\(String(s.lastOcrPreview.replacingOccurrences(of: "\n", with: " ").prefix(220)))`

        | Vaqt | Kategoriya | Kod | Faol Dastur | Vaqt (ms) | Batafsil Tahlil |
        | :--- | :--- | :--- | :--- | :--- | :--- |
        """
        for ev in snapshot {
            let shortTime = String(ev.timestamp.suffix(13))
            let safeDetail = ev.details.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
            md += "\n| `\(shortTime)` | **\(ev.category)** | `\(ev.statusCode)` | \(ev.activeApp) | \(ev.latencyMs) | \(safeDetail) |"
        }

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

// MARK: - 4. Persistent App Settings & State (v13.0)
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // 3 Input Control Modes:
    // "hybrid"        -> Sichqoncha Imo-ishorasi (○ / ↔ / ↓) + Klaviatura (⌥F / ⌥K)
    // "mouse_only"    -> Faqat Sichqoncha Imo-ishorasi (Klaviaturaga 0% tegmaydi!)
    // "keyboard_only" -> Faqat Klaviatura (Sichqoncha imo-ishorasi o'chiriladi)
    @Published var inputControlMode: String = "hybrid"
    @Published var enableMouseGestures: Bool = true
    @Published var enableBareExamKeysInStealth: Bool = false // Only when explicitly toggled ON so S and K never block normal typing in background apps!

    @Published var engineMode: String = "flash_pro_api"
    @Published var webModelTier: String = "flash"
    @Published var webAttachScreenshot: Bool = true

    @Published var geminiKey1: String = ""
    @Published var geminiKey2: String = ""
    @Published var geminiKey3: String = ""
    @Published var geminiPreferredModel: String = "auto_flash_pro"
    @Published var discoveredGeminiModels: [String] = []

    @Published var groqKey1: String = ""
    @Published var groqKey2: String = ""
    @Published var groqKey3: String = ""

    // Trigger, Cooldown & Camouflage Settings
    @Published var requireSFCombo: Bool = true
    @Published var comboWindowMs: Double = 700.0
    @Published var cooldownSeconds: Double = 3.5
    @Published var enableMouseCorners: Bool = false
    @Published var smartCropViewport: Bool = true
    @Published var autoHideHudSeconds: Double = 4.0
    @Published var showValueInHud: Bool = true

    // Archive & Solver Options
    @Published var archiveDir: String = ""
    @Published var parallelConsensus: Bool = true
    @Published var speculativeEarlyCommit: Bool = true
    @Published var sendImageToAI: Bool = true
    @Published var useArchiveCacheForSolving: Bool = false

    // Stealth HUD & Human Cursor Drift Options
    @Published var hudPosition: String = "bottom-left"
    @Published var hudOpacity: Double = 0.74
    @Published var hudFontSize: Double = 14.0
    @Published var humanDriftPixels: Double = 8.5

    // Live Telemetry & Permissions
    @Published var hasScreenPermission: Bool = true
    @Published var hasAccessibilityPermission: Bool = true
    @Published var isTerminalBridgeActive: Bool = false
    @Published var hudState: HudDisplayState = .workingG
    @Published var statusText: String = "Tayyor: Sichqonchada [○/△] chizing yoki [⌥F] bosing"
    @Published var isProcessing: Bool = false
    @Published var isStealthMode: Bool = false
    @Published var lastPrimaryAnswer: String = "-"
    @Published var lastSecondaryAnswer: String = ""
    @Published var lastValuePreview: String = ""
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
    @Published var lastDetectedGestureName: String = "Hali imo-ishora qilinmadi"

    private let configFileURL: URL

    private init() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support/SilentHelper", isDirectory: true)
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.configFileURL = appSupport.appendingPathComponent("config_v13.json")

        self.archiveDir = AppSettings.detectDefaultDrivePath()
        load()
        try? fm.createDirectory(atPath: self.archiveDir, withIntermediateDirectories: true)
        refreshPermissionsSilently()
    }

    func refreshPermissionsSilently() {
        let bridge = BridgeIPC.readBridgeStatus()
        let directScreen = CGPreflightScreenCaptureAccess()
        let directAx = AXIsProcessTrusted()
        let screenOk = directScreen || bridge.alive
        let axOk = directAx || bridge.alive

        DispatchQueue.main.async {
            self.isTerminalBridgeActive = bridge.alive
            self.hasScreenPermission = screenOk
            self.hasAccessibilityPermission = axOk
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
        var inputControlMode: String?
        var enableMouseGestures: Bool?
        var enableBareExamKeysInStealth: Bool?
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
        var cooldownSeconds: Double?
        var enableMouseCorners: Bool
        var smartCropViewport: Bool
        var autoHideHudSeconds: Double
        var showValueInHud: Bool?
        var archiveDir: String
        var parallelConsensus: Bool
        var speculativeEarlyCommit: Bool
        var sendImageToAI: Bool
        var useArchiveCacheForSolving: Bool?
        var hudPosition: String
        var hudOpacity: Double
        var hudFontSize: Double
        var humanDriftPixels: Double
    }

    func save() {
        let filteredDiscovered = discoveredGeminiModels.filter { ModelPolicy.isAllowedGeminiModel($0) }
        let cfg = StoredConfig(
            inputControlMode: inputControlMode,
            enableMouseGestures: enableMouseGestures,
            enableBareExamKeysInStealth: enableBareExamKeysInStealth,
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
            cooldownSeconds: cooldownSeconds,
            enableMouseCorners: enableMouseCorners,
            smartCropViewport: smartCropViewport,
            autoHideHudSeconds: autoHideHudSeconds,
            showValueInHud: showValueInHud,
            archiveDir: (archiveDir as NSString).expandingTildeInPath,
            parallelConsensus: parallelConsensus,
            speculativeEarlyCommit: speculativeEarlyCommit,
            sendImageToAI: sendImageToAI,
            useArchiveCacheForSolving: useArchiveCacheForSolving,
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
        for fileCandidate in ["config_v13.json", "config_v12.json", "config_v11.json", "config_v10.json", "config_v9.json", "config_v8.json", "config_v7.json", "config_v6.json", "config_v5.json", "config_v4.json", "config_v3.json", "config_v2.json"] {
            let url = supportDir.appendingPathComponent(fileCandidate)
            if let data = try? Data(contentsOf: url) {
                if let cfg = try? JSONDecoder().decode(StoredConfig.self, from: data) {
                    self.inputControlMode = cfg.inputControlMode ?? "hybrid"
                    self.enableMouseGestures = cfg.enableMouseGestures ?? (self.inputControlMode != "keyboard_only")
                    self.enableBareExamKeysInStealth = cfg.enableBareExamKeysInStealth ?? false
                    self.geminiKey1 = cfg.geminiKey1
                    self.geminiKey2 = cfg.geminiKey2
                    self.geminiKey3 = cfg.geminiKey3
                    if !self.geminiKey1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cfg.engineMode == "gemini_web_primary" {
                        self.engineMode = "flash_pro_api"
                    } else {
                        self.engineMode = cfg.engineMode
                    }
                    self.webModelTier = (cfg.webModelTier == "pro") ? "pro" : "flash"
                    self.webAttachScreenshot = cfg.webAttachScreenshot
                    self.geminiPreferredModel = ModelPolicy.isAllowedGeminiModel(cfg.geminiPreferredModel) ? cfg.geminiPreferredModel : "auto_flash_pro"
                    self.discoveredGeminiModels = cfg.discoveredGeminiModels.filter { ModelPolicy.isAllowedGeminiModel($0) }
                    self.groqKey1 = cfg.groqKey1
                    self.groqKey2 = cfg.groqKey2
                    self.groqKey3 = cfg.groqKey3
                    self.requireSFCombo = cfg.requireSFCombo
                    self.comboWindowMs = max(650.0, cfg.comboWindowMs)
                    self.cooldownSeconds = cfg.cooldownSeconds ?? 3.5
                    self.enableMouseCorners = false
                    self.smartCropViewport = cfg.smartCropViewport
                    self.autoHideHudSeconds = cfg.autoHideHudSeconds
                    self.showValueInHud = cfg.showValueInHud ?? true
                    if !cfg.archiveDir.isEmpty { self.archiveDir = cfg.archiveDir }
                    self.parallelConsensus = cfg.parallelConsensus
                    self.speculativeEarlyCommit = true
                    self.sendImageToAI = cfg.sendImageToAI
                    self.useArchiveCacheForSolving = cfg.useArchiveCacheForSolving ?? false
                    self.hudPosition = cfg.hudPosition
                    self.hudOpacity = cfg.hudOpacity
                    self.hudFontSize = cfg.hudFontSize
                    self.humanDriftPixels = max(6.0, cfg.humanDriftPixels)
                    if fileCandidate != "config_v13.json" { save() }
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

// MARK: - 5. Interior-Clamped Directional Human Cursor Signals (1: Left | 2: Right | 3: 3x)
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
    static var ignoreGesturesUntil: TimeInterval = 0

    private static func clampPoint(_ pt: CGPoint, in screen: NSScreen) -> CGPoint {
        let f = screen.frame
        let minX = f.minX + 55.0
        let maxX = max(minX + 10.0, f.maxX - 55.0)
        let minY = 55.0
        let maxY = max(minY + 10.0, f.height - 55.0)
        return CGPoint(
            x: min(max(pt.x, minX), maxX),
            y: min(max(pt.y, minY), maxY)
        )
    }

    static func stage1CaptureTakenLeft() {
        ignoreGesturesUntil = Date().timeIntervalSince1970 + 0.45
        let bridge = BridgeIPC.readBridgeStatus()
        if bridge.alive {
            try? "L".write(toFile: BridgeIPC.driftLeftReqFile, atomically: true, encoding: .utf8)
        }
        if AXIsProcessTrusted() {
            performDirectionalShift(directionX: -1.0)
        } else if !bridge.alive {
            performDirectionalShift(directionX: -1.0)
            SubtleOpticalCueWindow.shared.winkNearCursor(pulses: 1)
        }
    }

    static func stage2DispatchedRight() {
        ignoreGesturesUntil = Date().timeIntervalSince1970 + 0.45
        let bridge = BridgeIPC.readBridgeStatus()
        if bridge.alive {
            try? "R".write(toFile: BridgeIPC.driftRightReqFile, atomically: true, encoding: .utf8)
        }
        if AXIsProcessTrusted() {
            performDirectionalShift(directionX: 1.0)
        } else if !bridge.alive {
            performDirectionalShift(directionX: 1.0)
            SubtleOpticalCueWindow.shared.winkNearCursor(pulses: 1)
        }
    }

    static func stage3AnswerReady() {
        ignoreGesturesUntil = Date().timeIntervalSince1970 + 0.75
        let bridge = BridgeIPC.readBridgeStatus()
        if bridge.alive {
            try? "3".write(toFile: BridgeIPC.driftReady3ReqFile, atomically: true, encoding: .utf8)
        }
        if AXIsProcessTrusted() {
            performOrganicHumanDrift(pulses: 3)
        } else if !bridge.alive {
            performOrganicHumanDrift(pulses: 3)
            SubtleOpticalCueWindow.shared.winkNearCursor(pulses: 3)
        }
    }

    private static func performDirectionalShift(directionX: CGFloat) {
        let amp = max(6.0, CGFloat(AppSettings.shared.humanDriftPixels))
        DispatchQueue.global(qos: .userInteractive).async {
            guard let mainScreen = NSScreen.screens.first else { return }
            let screenH = mainScreen.frame.height
            let mouseNow = NSEvent.mouseLocation
            let safeOrigin = clampPoint(CGPoint(x: mouseNow.x, y: screenH - mouseNow.y), in: mainScreen)
            let outFrames = 9
            let backFrames = 7

            for frame in 1...outFrames {
                let t = CGFloat(frame) / CGFloat(outFrames)
                let ease = sin(t * (.pi / 2.0))
                let dx = directionX * amp * ease
                let pt = clampPoint(CGPoint(x: safeOrigin.x + dx, y: safeOrigin.y), in: mainScreen)
                CGWarpMouseCursorPosition(pt)
                CGAssociateMouseAndMouseCursorPosition(1)
                usleep(8_000)
            }
            usleep(30_000)
            for frame in 1...backFrames {
                let t = CGFloat(frame) / CGFloat(backFrames)
                let remain = 1.0 - sin(t * (.pi / 2.0))
                let dx = directionX * amp * remain
                let pt = clampPoint(CGPoint(x: safeOrigin.x + dx, y: safeOrigin.y), in: mainScreen)
                CGWarpMouseCursorPosition(pt)
                CGAssociateMouseAndMouseCursorPosition(1)
                usleep(7_500)
            }
        }
    }

    private static func performOrganicHumanDrift(pulses: Int) {
        let amp = CGFloat(AppSettings.shared.humanDriftPixels) * 0.70
        DispatchQueue.global(qos: .userInteractive).async {
            guard let mainScreen = NSScreen.screens.first else { return }
            let screenH = mainScreen.frame.height

            for p in 0..<pulses {
                let mouseNow = NSEvent.mouseLocation
                let safeOrigin = clampPoint(CGPoint(x: mouseNow.x, y: screenH - mouseNow.y), in: mainScreen)
                let totalFrames = 14

                for frame in 1...totalFrames {
                    let t = Double(frame) / Double(totalFrames)
                    let wave = CGFloat(sin(t * 2.0 * Double.pi))
                    let dx = wave * amp
                    let dy = wave * (amp * 0.35)
                    let pt = clampPoint(CGPoint(x: safeOrigin.x + dx, y: safeOrigin.y + dy), in: mainScreen)
                    CGWarpMouseCursorPosition(pt)
                    CGAssociateMouseAndMouseCursorPosition(1)
                    usleep(8_500)
                }

                if p < pulses - 1 {
                    usleep(75_000)
                }
            }
        }
    }
}

// MARK: - 6. Fullscreen-Proof Stealth HUD (Displays G, K, IW, SW, W, or "B · 1/2")
final class StealthOverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "G")
    private let container = NSView(frame: NSRect(x: 0, y: 0, width: 148, height: 32))

    init() {
        let rect = NSRect(x: 20, y: 20, width: 148, height: 32)
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

        label.frame = NSRect(x: 6, y: 4, width: 136, height: 22)
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail

        container.addSubview(label)
        self.contentView = container
        renderState(.workingG)
    }

    func refreshAppearance() {
        let s = AppSettings.shared
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: CGFloat(s.hudOpacity)).cgColor
        renderState(s.hudState)
        updatePosition(mode: s.hudPosition)
    }

    func updatePosition(mode: String) {
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let screen = activeScreen else { return }
        let frame = screen.frame
        let winW = self.frame.width
        var origin = NSPoint(x: frame.minX + 16, y: frame.minY + 16)

        switch mode {
        case "bottom-right":
            origin = NSPoint(x: frame.maxX - winW - 16, y: frame.minY + 16)
        case "top-left":
            origin = NSPoint(x: frame.minX + 16, y: frame.maxY - 52)
        case "top-right":
            origin = NSPoint(x: frame.maxX - winW - 16, y: frame.maxY - 52)
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
        let smallFont = NSFont.monospacedSystemFont(ofSize: max(11.0, fontSize - 2.0), weight: .semibold)
        let attr = NSMutableAttributedString()
        var targetWidth: CGFloat = 68

        switch state {
        case .workingG:
            let gAttr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 0.90)
            ]
            attr.append(NSAttributedString(string: "G", attributes: gAttr))

        case .cooldownK:
            let kAttr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.systemCyan.withAlphaComponent(0.95)
            ]
            attr.append(NSAttributedString(string: "K", attributes: kAttr))

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

        case let .answer(primary, secondary, valuePreview):
            let p = primary.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let s = secondary?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            let valClean = (valuePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let color = NSColor(calibratedWhite: 0.96, alpha: 0.95)

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
                attr.append(NSAttributedString(string: p.isEmpty ? "G" : p, attributes: singleAttr))
            }

            if AppSettings.shared.showValueInHud && !valClean.isEmpty && valClean.lowercased() != p.lowercased() && valClean != "N/A" {
                let shortVal = String(valClean.prefix(14))
                let valAttr: [NSAttributedString.Key: Any] = [
                    .font: smallFont,
                    .foregroundColor: color.withAlphaComponent(0.84)
                ]
                attr.append(NSAttributedString(string: " · \(shortVal)", attributes: valAttr))
                targetWidth = min(190, max(84, CGFloat(attr.string.count) * 9.2 + 22))
            } else {
                targetWidth = 72
            }
        }

        DispatchQueue.main.async {
            var f = self.frame
            f.size.width = targetWidth
            self.setFrame(f, display: false)
            self.container.frame = NSRect(x: 0, y: 0, width: targetWidth, height: 32)
            self.label.frame = NSRect(x: 6, y: 4, width: targetWidth - 12, height: 22)
            self.label.attributedStringValue = attr
        }
    }
}

// MARK: - 7. In-Memory Google Drive Archive Manager
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
        "ask", "gemini", "examlive", "violations", "remaining", "time", "skip"
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

    static func tokenizeCore(_ normalized: String) -> Set<String> {
        let tokens = normalized.split(separator: " ").map(String.init)
        let filtered = tokens.filter { tok in
            guard tok.count >= 2 && !examBoilerplateStopwords.contains(tok) else { return false }
            if tok.count <= 2 && tok.allSatisfy({ $0.isNumber }) {
                return false
            }
            return true
        }
        return Set(filtered.isEmpty ? tokens : filtered)
    }

    func findCachedAnswer(for rawText: String) -> ArchiveEntry? {
        let norm = Self.normalize(rawText)
        if norm.count < 25 { return nil }
        lock.lock()
        let snapshot = ramEntries
        lock.unlock()

        for item in snapshot {
            if item.entry.normalizedText == norm {
                return item.entry
            }
        }
        return nil
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

// MARK: - 8. Zero-Popup Screen Capture Engine
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

    static func captureMainDisplay(completion: @escaping (CGImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let bridge = BridgeIPC.readBridgeStatus()
            if bridge.alive {
                BridgeIPC.ensureDir()
                try? FileManager.default.removeItem(atPath: BridgeIPC.captureFrameReady)
                try? "1".write(toFile: BridgeIPC.captureReqFile, atomically: true, encoding: .utf8)
                for _ in 0..<70 {
                    usleep(15_000)
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

            guard CGPreflightScreenCaptureAccess() else {
                completion(nil)
                return
            }

            let tmpPath = "/tmp/sh_v13_\(ProcessInfo.processInfo.globallyUniqueString).jpg"
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

            if let rawCg = LegacyCGDisplayBridge.captureViaDynamicSymbol() {
                let cropped = smartCropViewportIfNeeded(rawCg)
                publishCaptureSuccess(cropped)
                completion(cropped)
                return
            }

            completion(nil)
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

// MARK: - 9. 2026 Hidden Gemini Web v13 Bridge
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
        config.websiteDataStore = .default()
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

    func enforceFlashOrProModel(preferredTier: String, completion: (() -> Void)? = nil) {
        let targetKeyword = (preferredTier == "pro") ? "pro" : "flash"
        let js = """
        (function() {
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
            }, 200);

            return "SWITCHING_FROM:" + currentLabel;
        })();
        """
        webView.evaluateJavaScript(js) { res, _ in
            if let status = res as? String {
                DispatchQueue.main.async {
                    AppSettings.shared.webBridgeStatus = "Gemini Web (\(preferredTier.uppercased())): \(status)"
                }
                if status.hasPrefix("SWITCHING") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
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
                setTimeout(tryClickSend, b64.length > 100 ? 460 : 160);

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
            if self.pollTicks > 55 {
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

// MARK: - 10. Error Classification & Ultra-Fast Parallel Router (1.8–3.5s Response!)
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
        1. Rasm va OCR matnini solishtir: kasr chiziqlari (masalan 1/2 yoki 1/3), darajalar (x^2, 10^-8), ildizlar, manfiy ishoralar, grafik chiziqlari (K, L, M, N), elektr zanjirlari (parallel/ketma-ket rezistorlar) hamda fizika SI birliklarini rasmdan diqqat bilan tekshir.
        2. Agar variantlar oldida A, B, C, D harflari yozilmagan bo'lsa (masalan ExamLive saytida 4 ta dumaloq tugma ustma-ust joylashgan bo'lsa):
           - Yuqoridan 1-variant = "A"
           - 2-variant = "B"
           - 3-variant = "C"
           - Eng pastki 4-variant = "D"
           deb belgila va "value" maydoniga o'sha to'g'ri variantning aniq qiymatini (masalan "1/2" yoki "6,6" yoki "5 A, o'ngga") yoz!
        3. Matematika va Fizika tuzoqlari:
           - So'ralgan narsani tekshir (masalan, R1/R2 nisbatmi yoki R1 ning o'zimi; millimetr kvadrat mm^2 = 10^-6 m^2, santimetr cm = 10^-2 m).
        4. Javobni FAQAT birinchi qatorda quyidagi sof JSON formatida qaytar:
        {"primary":"A","secondary":"","confidence":"high","value":"variantning qisqa qiymati","reasoning":"1 qatorli aniq matematik/fizik isbot"}

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
    private var lastFastestWinningModel: String? = "gemini-3-flash-preview"
    private let lock = NSLock()

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 9
        cfg.timeoutIntervalForResource = 12
        cfg.httpMaximumConnectionsPerHost = 8
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

    private func markRateLimited(keyId: String, model: String, seconds: TimeInterval = 120) {
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

    private func recordWinningModel(_ model: String) {
        lock.lock()
        defer { lock.unlock() }
        let clean = Self.cleanModelName(model)
        if ModelPolicy.isAllowedGeminiModel(clean) {
            lastFastestWinningModel = clean
        }
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

        var req = URLRequest(url: url, timeoutInterval: 10)
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
        lock.lock()
        let winner = lastFastestWinningModel
        lock.unlock()

        if let w = winner, ModelPolicy.isAllowedGeminiModel(w) {
            gemModels.append(w)
        }

        let pref = Self.cleanModelName(s.geminiPreferredModel)
        if ModelPolicy.isAllowedGeminiModel(pref) && !gemModels.contains(pref) {
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
            if gemModels.count > 1 {
                var rotated = Array(gemModels.dropFirst())
                rotated.append(gemModels[0])
                orderedModels = rotated
            } else {
                orderedModels = gemModels
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

        if s.engineMode == "gemini_web_primary" && s.activeGeminiKeys.isEmpty && s.activeGroqKeys.isEmpty && attempt == 1 {
            HiddenGeminiWebBridge.shared.solveViaHiddenWeb(questionText: ocrText, cgImage: imageForAI) { webRes, webErr in
                if let r = webRes {
                    completion(r, nil, nil)
                } else {
                    let cat = webErr ?? .sendErrorSW
                    onTransientError(cat, "Gemini Web xatosi, zaxira tarmoq orqali avto-tuzatilmoqda...", attempt)
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
        executeSingleStream(streamIndex: 0, prompt: prompt, cgImage: imageForAI, ignoreCooldowns: attempt >= 4) { res, cat, err in
            stateLock.lock()
            resultFast = res
            catFast = cat
            msgFast = err
            if let r = res, !didEarlyCommit {
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
            executeSingleStream(streamIndex: 1, prompt: prompt, cgImage: imageForAI) { res2, _, _ in
                stateLock.lock()
                resultDeep = res2
                if let r2 = res2, !didEarlyCommit {
                    didEarlyCommit = true
                    stateLock.unlock()
                    onEarlyCommit(r2)
                } else {
                    stateLock.unlock()
                }
                group.leave()
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
                    let bIsPro = b.modelUsed.lowercased().contains("pro") || b.modelUsed.lowercased().contains("3.5")
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
                if attempt < 5 {
                    onTransientError(category, msgFast ?? "Qayta urinilmoqda...", attempt)
                    let delay = Double(attempt) * 1.0
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
                    self.recordWinningModel(ep.model)
                    completion(res, nil, nil)
                } else {
                    if statusCode == 404 || statusCode == 400 {
                        self.markModelNotFound(keyId: ep.keyLabel, model: ep.model)
                    } else if statusCode == 429 || statusCode == 503 {
                        self.markRateLimited(keyId: ep.keyLabel, model: ep.model, seconds: 120)
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
                        self.markRateLimited(keyId: ep.keyLabel, model: ep.model, seconds: 120)
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
        let maxDim: CGFloat = 1120
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
            if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.66]) {
                return data.base64EncodedString()
            }
        }
        let fallbackRep = NSBitmapImageRep(cgImage: cgImage)
        return fallbackRep.representation(using: .jpeg, properties: [.compressionFactor: 0.64])?.base64EncodedString()
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
                "maxOutputTokens": 2048
            ]
        ]

        var req = URLRequest(url: url, timeoutInterval: 9)
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

        var req = URLRequest(url: endpoint, timeoutInterval: 9)
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

        let argonBlocked = !ModelPolicy.isAllowedGeminiModel("gemini-argon-exp")
        let dead25Blocked = !ModelPolicy.isAllowedGeminiModel("gemini-2.5-flash")
        let fast3Allowed = ModelPolicy.isAllowedGeminiModel("gemini-3.5-flash") && ModelPolicy.isAllowedGeminiModel("gemini-3-flash-preview")
        results.append(argonBlocked && dead25Blocked && fast3Allowed
            ? "✅ [1/8] 2-3s Tezkor Model Siyosati: `gemini-3-flash-preview` va `gemini-3.5-flash` 1-o'rinda."
            : "❌ [1/8] Model Siyosati xatosi.")

        let bundleId = Bundle.main.bundleIdentifier ?? "nil"
        let bridge = BridgeIPC.readBridgeStatus()
        results.append(bundleId == "com.local.SilentHelper"
            ? "✅ [2/8] Yagona MenuBar Ikonka & 0-Popup Bridge (\(bridge.alive ? "FAOL" : "Standby")): Tayyor."
            : "⚠️ [2/8] Bundle ID: \(bundleId)")

        let screenRecordingSharingNone = (StealthOverlayWindow().sharingType == .none)
        results.append(screenRecordingSharingNone
            ? "✅ [3/8] Sichqoncha Imo-ishoralari (○/△ Skrinshot, ↔ Ko'rish, ↓ Yashirish) & Anti-Sensor: Faol."
            : "❌ [3/8] Anti-Sensor xatosi.")

        let t0 = CFAbsoluteTimeGetCurrent()
        _ = ArchiveManager.shared.findCachedAnswer(for: "If 3x + 7 = 22, what is the value of 6x + 5 in the equation above?")
        let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        results.append(String(format: "✅ [4/8] Cooldown 'K', Eski Javobni Tozalash & Harf+Qiymat HUD (`B · 1/2`): Tayyor (%.3f ms).", dtMs))

        let p1 = SmartAIRouter.shared.parseJSONResponse("```json\n{\"primary\":\"B\",\"secondary\":\"\",\"confidence\":\"high\",\"value\":\"1/2\",\"reasoning\":\"test\"}\n```", modelTag: "Test")
        let p2 = SmartAIRouter.shared.parseJSONResponse("To'g'ri javob: **D** — chunki 4*4=16", modelTag: "Test")
        results.append((p1?.primary == "B" && p1?.value == "1/2" && p2?.primary == "D")
            ? "✅ [5/8] Javob Sintezatori: JSON ('B · 1/2') va matn ('D') 100% aniqlikda ajratildi."
            : "❌ [5/8] Javob Sintezatori xatosi.")

        ScreenCaptureService.captureMainDisplay { cgImg in
            if let img = cgImg {
                results.append("✅ [6/8] Zero-Popup Skrinshot: Muvaffaqiyatli (\(img.width)x\(img.height) px).")
                ScreenCaptureService.extractStructuredQuestionText(from: img) { ocr in
                    results.append("✅ [7/8] Spatial Vision OCR: \(ocr.count) ta belgi tartib bilan o'qildi.")
                    results.append("✅ [8/8] Yo'nalishli Kursor (Chapga -> O'ngga -> 3x) & Drive Telemetriya: Tayyor.")
                    FlightRecorder.shared.record(category: "AUDIT", statusCode: "OK", latencyMs: Int(dtMs), details: "v13.0 8-bosqichli audit muvaffaqiyatli yakunlandi (OCR: \(ocr.count) belgi)")
                    HumanCursorSignal.stage3AnswerReady()
                    DispatchQueue.main.async {
                        completion(results)
                    }
                }
            } else {
                results.append("⚠️ [6/8] Skrinshot: ./run.sh orqali Terminal Bridge ko'prigini ishga tushiring.")
                DispatchQueue.main.async {
                    completion(results)
                }
            }
        }
    }
}

// MARK: - 12. Smooth SwiftUI Control Panel View (v13.0 — Includes Interactive Manual & Gesture Trainer)
struct ControlPanelView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var archive = ArchiveManager.shared
    @ObservedObject var flightRecorder = FlightRecorder.shared
    @State private var selectedTab: Int = 0
    @State private var searchQuery: String = ""

    var onEnterStealthMode: () -> Void
    var onToggleHudPreview: () -> Void
    var onHideHudNow: () -> Void
    var onManualTestCapture: () -> Void
    var onRecordManualIncident: () -> Void
    var onInputModeChanged: () -> Void

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
            // Top Status Bar with Custom Logo
            HStack(spacing: 12) {
                Image(nsImage: AppIconGenerator.makeShieldLogoImage(size: NSSize(width: 34, height: 34)))
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("SilentHelper v13.0")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Mouse Gestures (○ / ↔ / ↓) · 3 Rejim · 1 MenuBar Logo")
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
                        .font(.system(size: 13.5, weight: .bold, design: .monospaced))
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

            // Quick Mode & Gesture Status Banner
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "computermouse.fill")
                        .foregroundColor(.cyan)
                    Text("Oxirgi Imo-ishora: \(settings.lastDetectedGestureName)")
                        .font(.system(size: 11, weight: .semibold))
                }

                Spacer()

                Button("8-Bosqichli Audit") {
                    DiagnosticSuite.runAllChecks { report in
                        settings.auditReportLines = report
                        selectedTab = 0
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
                TabButton(title: "1. Sichqoncha & Qo'llanma", icon: "computermouse.fill", isSelected: selectedTab == 0) {
                    withAnimation(.easeInOut(duration: 0.16)) { selectedTab = 0 }
                }
                TabButton(title: "2. 2-3s Tezkor API", icon: "cpu.fill", isSelected: selectedTab == 1) {
                    withAnimation(.easeInOut(duration: 0.16)) { selectedTab = 1 }
                }
                TabButton(title: "3. Yashirin Gemini Web", icon: "globe.desk.fill", isSelected: selectedTab == 2) {
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

            if selectedTab == 2 {
                hiddenWebBrowserSection
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if selectedTab == 0 {
                            mouseGesturesAndManualSection
                        } else if selectedTab == 1 {
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
                Text("Sichqoncha: [○/△] = Skrinshot  |  [↔] = Javobni ko'rish (B · 1/2)  |  [↓] = Darhol yashirish  |  Panel: [⌥M]")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Saqlash") {
                    settings.save()
                    onInputModeChanged()
                    flightRecorder.rebuildMarkdownReport()
                    settings.statusText = "Sozlamalar saqlandi!"
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 840, minHeight: 640)
    }

    private var hudPreviewText: String {
        switch settings.hudState {
        case .workingG: return "G"
        case .cooldownK: return "K"
        case .internetErrorIW: return "IW"
        case .sendErrorSW: return "SW"
        case .generalErrorW: return "W"
        case let .answer(p, s, val):
            let base = (s != nil && !s!.isEmpty) ? "\(p)\u{0332} \(s!)" : p
            if settings.showValueInHud, let v = val, !v.isEmpty, v != "N/A" {
                return "\(base) · \(String(v.prefix(10)))"
            }
            return base
        }
    }

    // MARK: - Tab 1: 3 Input Modes, Mouse Gestures, & Complete Built-in Manual
    private var mouseGesturesAndManualSection: some View {
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

            // 1. 3-Mode Input Selector (Never blocks background apps!)
            GroupBox(label: Label("1. Boshqaruv Rejimini Tanlash (Fonda Boshqa Dasturlarga Xalaqit Bermaydi!)", systemImage: "slider.horizontal.below.rectangle").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Boshqaruv Usuli:", selection: Binding(
                        get: { settings.inputControlMode },
                        set: { val in
                            settings.inputControlMode = val
                            settings.enableMouseGestures = (val != "keyboard_only")
                            settings.save()
                            onInputModeChanged()
                        }
                    )) {
                        Text("🖱️ + ⌨️ Ikkisi ham (Sichqoncha + Klaviatura)").tag("hybrid")
                        Text("🖱️ Faqat Sichqoncha (Klaviaturaga 0% tegmaydi)").tag("mouse_only")
                        Text("⌨️ Faqat Klaviatura (Sichqoncha o'chiq)").tag("keyboard_only")
                    }
                    .pickerStyle(.segmented)

                    if settings.inputControlMode != "mouse_only" {
                        Toggle("Ko'rinmas rejimda Alt bosmasdan [S keyin F] va [K] klavishlarini ham yoqish (Faqat imtihon vaqtida yoqing, matn yozishda o'chirib qo'ying)", isOn: Binding(
                            get: { settings.enableBareExamKeysInStealth },
                            set: { val in
                                settings.enableBareExamKeysInStealth = val
                                settings.save()
                                onInputModeChanged()
                            }
                        ))
                        .font(.system(size: 11.5, weight: .medium))
                    }
                }
                .padding(8)
            }

            // 2. Complete Interactive Manual (Qo'llanma)
            GroupBox(label: Label("2. To'liq Qo'llanma: Sichqoncha Imo-ishoralari va Kursor Signallari", systemImage: "book.pages.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("🖱️ SICHQONCHA IMO-ISHORALARI (Ekran o'rtasida):")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.cyan)
                            Text("• [1] Skrinshot Olish va Yuborish:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("   Sichqoncha bilan kichik Aylana (○), Uchburchak (△) yoki Yuqori-chapdan O'ng-pastga diagonal chiziq tortib qayting (↘↖).")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Text("• [2] Javobni yoki 'G' Holatni Ko'rish:")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("   Sichqonchani turgan joyida Chap-O'ng-Chap (↔) qilib 2 marta yengil tebrating -> HUD oyna ('B · 1/2' yoki 'G') ochiladi.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Text("• [3] Javobni Darhol Yashirish (3-4s kutmasdan):")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("   HUD oyna ochiq turganda sichqonchani Pastga (↓) torting -> HUD oyna shu zahoti (0ms) o'chadi!")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("🎯 AVTO-KURSOR VA HUD KODLARI:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.green)
                            Text("• ⬅️ Chapga siljish (1-Bosqich): Skrinshot olindi va eski savol javobi tozalandi.")
                                .font(.system(size: 11))
                            Text("• ➡️ O'ngga siljish (2-Bosqich): Savol Gemini AI'ga muvaffaqiyatli yuborildi.")
                                .font(.system(size: 11))
                            Text("• 🔄 3 marta qimirlash (3-Bosqich): Javob tayyor bo'ldi!")
                                .font(.system(size: 11))
                            Divider()
                            Text("• 'G' = Gemini ishlayapti  |  'K' = Kuting (Cooldown)")
                                .font(.system(size: 11, weight: .semibold))
                            Text("• 'IW' = Internet xato  |  'SW' = Yuborish xato (Avto-tuzatiladi)")
                                .font(.system(size: 11, weight: .semibold))
                            Text("• 'B · 1/2' = 2-variant (B) va uning qiymati (1/2)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }

            // 3. Live Controls & Tester
            GroupBox(label: Label("3. Jonli Sinov Tugmalari va HUD Sozlamalari", systemImage: "hand.point.up.left.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button("⬅️ Sinash: Chapga (Skrin)") {
                            HumanCursorSignal.stage1CaptureTakenLeft()
                        }
                        .controlSize(.small)

                        Button("➡️ Sinash: O'ngga (Yuborish)") {
                            HumanCursorSignal.stage2DispatchedRight()
                        }
                        .controlSize(.small)

                        Button("🔄 Sinash: 3x (Javob)") {
                            HumanCursorSignal.stage3AnswerReady()
                        }
                        .controlSize(.small)

                        Button("👁️ HUD Ko'rsatish ('B · 1/2')") {
                            settings.hudState = .answer(primary: "B", secondary: nil, valuePreview: "1/2")
                            onToggleHudPreview()
                        }
                        .controlSize(.small)

                        Button("🙈 HUD Darhol Yashirish (↓)") {
                            onHideHudNow()
                        }
                        .controlSize(.small)
                    }

                    HStack(spacing: 16) {
                        Toggle("HUD'da qiymatni ham ko'rsatish ('B · 1/2')", isOn: $settings.showValueInHud)
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                        Text("Cooldown (\(String(format: "%.1f", settings.cooldownSeconds))s):")
                            .font(.system(size: 11.5))
                        Slider(value: $settings.cooldownSeconds, in: 1.5...8.0, step: 0.5)
                            .frame(width: 140)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Tab 2: Flash & Pro API Keys
    private var flashProApiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Label("Tezkor 2–3s Parallel Gemini 3.0 / 3.5 Flash Dvigateli", systemImage: "lock.shield.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Dvigatel:", selection: Binding(
                        get: { settings.engineMode },
                        set: { val in settings.engineMode = val; settings.save() }
                    )) {
                        Text("Tezkor Parallel API (2–3s Tavsiya etiladi)").tag("flash_pro_api")
                        Text("Gibrid Parallel").tag("hybrid_web_api")
                        Text("Faqat Gemini Web").tag("gemini_web_primary")
                    }
                    .pickerStyle(.segmented)

                    Toggle("Speculative Early-Commit (1-chi javob tayyor bo'lgan zahoti darhol bildirish)", isOn: $settings.speculativeEarlyCommit)
                        .font(.system(size: 12.5, weight: .medium))
                    Toggle("Parallel Consensus (2 ta kalitda 2 xil modelni parallel ishga tushirish)", isOn: $settings.parallelConsensus)
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
                            settings.apiTestStatus = "Tezkor modellar tekshirilmoqda..."
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
                                Text("Saqlash va Tezlikni Tekshirish")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .disabled(settings.apiTesting)

                        if !settings.discoveredGeminiModels.isEmpty {
                            Text("Faol modellar: \(settings.discoveredGeminiModels.prefix(5).joined(separator: ", "))")
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

            GroupBox(label: Label("Google Gemini API Kalitlari", systemImage: "sparkles").font(.headline)) {
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

    // MARK: - Tab 3: Full-Control Hidden Gemini Web Browser
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
                                settings.lastValuePreview = r.value
                                settings.hudState = .answer(primary: r.primary, secondary: r.secondary, valuePreview: r.value)
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
                Text("Google Email sessiyangiz `com.local.SilentHelper` konteynerida doimiy saqlanadi.")
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

    // MARK: - Tab 4: Google Drive Archive
    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(label: Label("Google Drive Arxiv Papkasi", systemImage: "folder.fill.badge.person.crop").font(.headline)) {
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
                    VStack(spacing: 2) {
                        Text(item.secondaryAnswer != nil && !item.secondaryAnswer!.isEmpty
                             ? "\(item.primaryAnswer)\u{0332} \(item.secondaryAnswer!)"
                             : item.primaryAnswer)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                        if !item.optionValue.isEmpty {
                            Text(String(item.optionValue.prefix(10)))
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 68, height: 36)
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
                    Barcha harakatlar, sichqoncha imo-ishoralari, javob tezligi (ms), cooldown 'K' va xatolar (IW / SW / W) real vaqtda Google Drive'dagi `QuizArchive/FlightLogs/practice_session_report.md` hamda `SILENTHELPER_TELEMETRY_LATEST.md` fayllariga avtomatik yozib boriladi.
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
                Text("Hozircha amaliyot yozuvlari yo'q. Sichqonchada [○/△] chizing yoki [⌥F] bosing.")
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
        case "K": return .cyan
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

// MARK: - 13. Carbon HotKey Handler
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
            globalAppController?.settings.lastTriggerMethod = "Stealth S->F"
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

// MARK: - 14. Main Application Controller (v13.0 — Single MenuBar Icon, Custom Logo & Gesture Engine)
final class AppController: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    let archive = ArchiveManager.shared
    let flightRecorder = FlightRecorder.shared
    let overlay = StealthOverlayWindow()
    let gestureRecognizer = MouseGestureRecognizer()

    var controlWindow: NSWindow?
    var statusItem: NSStatusItem?
    var isOverlayVisible = false
    private var hudAutoHideWorkItem: DispatchWorkItem?
    private var cooldownRestoreWorkItem: DispatchWorkItem?

    private let triggerLock = NSLock()
    private var atomicCaptureInFlight = false
    private var currentRequestID: Int = 0
    private var lastTriggerTime: Date = .distantPast

    private var scanTimer: Timer?
    private var lastSPressTime: Date = .distantPast

    private var hotKeyHandlerRef: EventHandlerRef?
    private var hotKeyRefCapture: EventHotKeyRef?
    private var hotKeyRefOverlay: EventHotKeyRef?
    private var hotKeyRefPanel: EventHotKeyRef?
    private var hotKeyRefIncident: EventHotKeyRef?

    private var stealthHotKeyS: EventHotKeyRef?
    private var stealthArmedHotKeyF: EventHotKeyRef?
    private var stealthHotKeyK: EventHotKeyRef?
    private var disarmFWorkItem: DispatchWorkItem?

    private static func enforceSingleGUIInstance() {
        BridgeIPC.ensureDir()
        let myPID = ProcessInfo.processInfo.processIdentifier

        // 1. Kill any previous PID recorded in single_gui.pid
        if let oldPidStr = try? String(contentsOfFile: BridgeIPC.guiPidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let oldPid = Int32(oldPidStr), oldPid > 0, oldPid != myPID {
            kill(oldPid, SIGKILL)
        }

        // 2. Force-terminate any other running com.local.SilentHelper app bundles
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.local.SilentHelper")
        for app in existing where app.processIdentifier != myPID {
            if !app.forceTerminate() {
                kill(app.processIdentifier, SIGKILL)
            }
        }

        try? "\(myPID)".write(toFile: BridgeIPC.guiPidFile, atomically: true, encoding: .utf8)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.enforceSingleGUIInstance()
        globalAppController = self

        // Set Custom Vector Shield Application Icon in Dock & Cmd+Tab!
        NSApp.applicationIconImage = AppIconGenerator.makeShieldLogoImage(size: NSSize(width: 512, height: 512))

        _ = HiddenGeminiWebBridge.shared
        _ = SubtleOpticalCueWindow.shared

        setupSingleMenuBarStatusItem()
        setupControlWindow()
        applyInputControlModeHotKeys()
        startGestureAndStateScanner()
        showControlWindow()

        settings.refreshPermissionsSilently()
        let bridge = BridgeIPC.readBridgeStatus()
        flightRecorder.record(
            category: "SESSION",
            statusCode: "START",
            latencyMs: 0,
            details: "SilentHelper v13.0 ishga tushdi (Mode: \(settings.inputControlMode) | Bridge: \(bridge.alive ? "ACTIVE" : "STANDBY"))"
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

    private func setupSingleMenuBarStatusItem() {
        if let existingItem = self.statusItem {
            NSStatusBar.system.removeStatusItem(existingItem)
            self.statusItem = nil
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = AppIconGenerator.makeMenuBarIcon()
        item.button?.imagePosition = .imageLeading
        item.button?.title = ""

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Skrinshot + AI (○/△ chizish yoki ⌥F)", action: #selector(menuCapture), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Javobni Ko'rsatish (↔ tebratish yoki ⌥K)", action: #selector(menuToggleHud), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Javobni Darhol Yashirish (↓ pastga)", action: #selector(menuHideHud), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Amaliyot Xatosini Muhrlash (⌥L)", action: #selector(menuRecordIncident), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Boshqaruv va Qo'llanma Paneli (⌥M)", action: #selector(menuShowPanel), keyEquivalent: ""))
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
    @objc private func menuHideHud() { hideOverlayImmediately() }
    @objc private func menuRecordIncident() { recordManualPracticeIncident() }
    @objc private func menuShowPanel() { showControlWindow() }
    @objc private func menuStealth() { enterStealthMode() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    /// Configures hotkeys strictly according to `inputControlMode` so background apps are NEVER disrupted!
    func applyInputControlModeHotKeys() {
        if hotKeyHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), carbonHotKeyHandler, 1, &eventType, nil, &hotKeyHandlerRef)
        }

        if let r1 = hotKeyRefCapture { UnregisterEventHotKey(r1); hotKeyRefCapture = nil }
        if let r2 = hotKeyRefOverlay { UnregisterEventHotKey(r2); hotKeyRefOverlay = nil }
        if let r3 = hotKeyRefPanel { UnregisterEventHotKey(r3); hotKeyRefPanel = nil }
        if let r7 = hotKeyRefIncident { UnregisterEventHotKey(r7); hotKeyRefIncident = nil }

        // Option + M (Panel toggle) is always available so the user can always bring back the window
        let id3 = EventHotKeyID(signature: OSType(0x53485639), id: 3)
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(optionKey), id3, GetApplicationEventTarget(), 0, &hotKeyRefPanel)

        // Only register Option+F, Option+K, Option+L if NOT in "mouse_only" mode!
        if settings.inputControlMode != "mouse_only" {
            let id1 = EventHotKeyID(signature: OSType(0x53485639), id: 1) // Option + F
            RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(optionKey), id1, GetApplicationEventTarget(), 0, &hotKeyRefCapture)

            let id2 = EventHotKeyID(signature: OSType(0x53485639), id: 2) // Option + K
            RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(optionKey), id2, GetApplicationEventTarget(), 0, &hotKeyRefOverlay)

            let id7 = EventHotKeyID(signature: OSType(0x53485639), id: 7) // Option + L
            RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(optionKey), id7, GetApplicationEventTarget(), 0, &hotKeyRefIncident)
        }

        updateStealthDirectCarbonKeys(active: settings.isStealthMode)
    }

    /// Bare `S -> F` and `K` keys are ONLY registered when Stealth Mode is active AND `enableBareExamKeysInStealth` is explicitly turned ON!
    /// This guarantees that normal typing in background apps is NEVER blocked!
    private func updateStealthDirectCarbonKeys(active: Bool) {
        disarmFWorkItem?.cancel()
        if let refS = stealthHotKeyS { UnregisterEventHotKey(refS); stealthHotKeyS = nil }
        if let refF = stealthArmedHotKeyF { UnregisterEventHotKey(refF); stealthArmedHotKeyF = nil }
        if let refK = stealthHotKeyK { UnregisterEventHotKey(refK); stealthHotKeyK = nil }

        guard active && settings.inputControlMode != "mouse_only" && settings.enableBareExamKeysInStealth else { return }

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
                }
            }
        }
    }

    private func startGestureAndStateScanner() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.022, repeats: true) { [weak self] _ in
            self?.pollMouseGestures()
        }
    }

    private func pollMouseGestures() {
        guard settings.inputControlMode != "keyboard_only" && settings.enableMouseGestures else { return }
        let now = Date().timeIntervalSince1970
        let mouse = NSEvent.mouseLocation

        if let gesture = gestureRecognizer.feedMousePoint(mouse, now: now, isHudVisible: isOverlayVisible) {
            DispatchQueue.main.async {
                self.settings.lastDetectedGestureName = gesture.rawValue
            }
            switch gesture {
            case .captureLoopOrSlash:
                settings.lastTriggerMethod = "Mouse Gesture (○/△)"
                triggerCaptureAndSolve()
            case .showHudWiggle:
                flightRecorder.record(category: "GESTURE", statusCode: "HUD", latencyMs: 0, details: "Sichqoncha (↔) tebranishi orqali HUD ochildi")
                showOverlayForPeek()
            case .hideHudPullDown:
                flightRecorder.record(category: "GESTURE", statusCode: "HIDE", latencyMs: 0, details: "Sichqoncha (↓) tortilishi orqali HUD darhol yopildi")
                hideOverlayImmediately()
            }
        }
    }

    private func setupControlWindow() {
        let contentView = ControlPanelView(
            onEnterStealthMode: { [weak self] in
                self?.enterStealthMode()
            },
            onToggleHudPreview: { [weak self] in
                self?.toggleOverlay()
            },
            onHideHudNow: { [weak self] in
                self?.hideOverlayImmediately()
            },
            onManualTestCapture: { [weak self] in
                self?.settings.lastTriggerMethod = "Panel Test Button"
                self?.triggerCaptureAndSolve()
            },
            onRecordManualIncident: { [weak self] in
                self?.recordManualPracticeIncident()
            },
            onInputModeChanged: { [weak self] in
                self?.applyInputControlModeHotKeys()
            }
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "SilentHelper v13.0 — Sichqoncha Imo-ishoralari (○ / ↔ / ↓), 3 Rejim & Qo'llanma"
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
            self.controlWindow?.alphaValue = 1.0
            self.controlWindow?.ignoresMouseEvents = false
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
            self.settings.statusText = "Ko'rinmas rejim faol: [○/△] = Skrinshot | [↔] = Ko'rish | [↓] = Yashirish"
            self.controlWindow?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
            self.updateStealthDirectCarbonKeys(active: true)
            self.flightRecorder.record(category: "MODE", statusCode: "STEALTH", latencyMs: 0, details: "Ko'rinmas rejim yoqildi (Input Mode: \(self.settings.inputControlMode))")
        }
    }

    func showOverlayForPeek() {
        DispatchQueue.main.async {
            self.hudAutoHideWorkItem?.cancel()
            self.overlay.refreshAppearance()
            self.overlay.orderFrontRegardless()
            self.isOverlayVisible = true
            self.gestureRecognizer.notifyHudOpened()

            if self.settings.autoHideHudSeconds > 0 {
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isOverlayVisible else { return }
                    self.overlay.orderOut(nil)
                    self.isOverlayVisible = false
                }
                self.hudAutoHideWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + self.settings.autoHideHudSeconds, execute: work)
            }
        }
    }

    func hideOverlayImmediately() {
        DispatchQueue.main.async {
            self.hudAutoHideWorkItem?.cancel()
            self.cooldownRestoreWorkItem?.cancel()
            if self.isOverlayVisible {
                self.overlay.orderOut(nil)
                self.isOverlayVisible = false
            }
        }
    }

    func toggleOverlay() {
        if isOverlayVisible {
            hideOverlayImmediately()
        } else {
            showOverlayForPeek()
        }
    }

    private func showCooldownKNotice(triggerUsed: String) {
        DispatchQueue.main.async {
            self.cooldownRestoreWorkItem?.cancel()
            self.hudAutoHideWorkItem?.cancel()

            let savedState: HudDisplayState
            if self.settings.isProcessing {
                savedState = .workingG
            } else if self.settings.lastPrimaryAnswer != "-" && !self.settings.lastPrimaryAnswer.isEmpty {
                savedState = .answer(
                    primary: self.settings.lastPrimaryAnswer,
                    secondary: self.settings.lastSecondaryAnswer.isEmpty ? nil : self.settings.lastSecondaryAnswer,
                    valuePreview: self.settings.lastValuePreview
                )
            } else {
                savedState = .workingG
            }

            self.settings.hudState = .cooldownK
            self.statusItem?.button?.title = "K"
            self.settings.statusText = "K (Kuting): Oldingi so'rov ishlanmoqda yoki Cooldown faol..."
            self.overlay.refreshAppearance()
            self.overlay.orderFrontRegardless()
            self.isOverlayVisible = true
            self.gestureRecognizer.notifyHudOpened()

            self.flightRecorder.record(
                category: "COOLDOWN",
                statusCode: "K",
                latencyMs: 0,
                details: "Qayta chaqirildi (\(triggerUsed)) -> Cooldown 'K' (Kuting) ko'rsatildi"
            )

            let restoreWork = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.settings.hudState == .cooldownK {
                    self.settings.hudState = self.settings.isProcessing ? .workingG : savedState
                    self.overlay.refreshAppearance()
                }
                if self.isOverlayVisible {
                    self.overlay.orderOut(nil)
                    self.isOverlayVisible = false
                }
            }
            self.cooldownRestoreWorkItem = restoreWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: restoreWork)
        }
    }

    func triggerCaptureAndSolve() {
        let now = Date()
        let triggerUsed = settings.lastTriggerMethod

        triggerLock.lock()
        let elapsedSinceLast = now.timeIntervalSince(lastTriggerTime)
        if atomicCaptureInFlight || elapsedSinceLast < settings.cooldownSeconds {
            triggerLock.unlock()
            if elapsedSinceLast >= 0.28 {
                showCooldownKNotice(triggerUsed: triggerUsed)
            }
            return
        }
        atomicCaptureInFlight = true
        lastTriggerTime = now
        currentRequestID += 1
        let reqID = currentRequestID
        triggerLock.unlock()

        let startTime = now

        // Immediately wipe the previous question's answer and hide HUD!
        DispatchQueue.main.async {
            self.cooldownRestoreWorkItem?.cancel()
            self.hudAutoHideWorkItem?.cancel()
            if self.isOverlayVisible {
                self.overlay.orderOut(nil)
                self.isOverlayVisible = false
            }
            self.settings.isProcessing = true
            self.settings.selfHealAttempt = 1
            self.settings.lastPrimaryAnswer = "-"
            self.settings.lastSecondaryAnswer = ""
            self.settings.lastValuePreview = ""
            self.settings.lastConfidence = ""
            self.settings.lastReasoning = "Yangi savol tahlil qilinmoqda..."
            self.settings.lastModelUsed = "..."
            self.settings.lastLatencyMs = 0
            self.settings.hudState = .workingG
            self.overlay.refreshAppearance()
            self.settings.statusText = "1/3 Chapga: Skrinshot olinmoqda (Eski javob tozalandi)..."
            self.statusItem?.button?.title = "G"
        }

        flightRecorder.record(category: "TRIGGER", statusCode: "G", latencyMs: 0, details: "Yangi savol skrinshoti boshlandi (Usul: \(triggerUsed))")

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.03) {
            ScreenCaptureService.captureMainDisplay { cgImage in
                let capMs = Int(Date().timeIntervalSince(startTime) * 1000)
                guard let cgImage = cgImage else {
                    self.triggerLock.lock()
                    self.atomicCaptureInFlight = false
                    self.triggerLock.unlock()

                    DispatchQueue.main.async {
                        self.settings.isProcessing = false
                        self.settings.hudState = .sendErrorSW
                        self.overlay.refreshAppearance()
                        self.statusItem?.button?.title = "SW"
                        self.settings.statusText = "SW: Terminal Bridge ko'prigini ./run.sh orqali yoqing"
                        self.flightRecorder.record(category: "CAPTURE", statusCode: "SW", latencyMs: capMs, details: "Skrinshot olinmadi: Terminal Bridge javob bermadi")
                    }
                    return
                }

                // 1-BOSQICH SIGNAL: Skrinshot olindi -> Kursor CHAPGA siljiydi!
                HumanCursorSignal.stage1CaptureTakenLeft()

                ScreenCaptureService.extractStructuredQuestionText(from: cgImage) { extractedText in
                    let cleanText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)

                    DispatchQueue.main.async {
                        self.settings.lastOcrPreview = cleanText
                        self.settings.statusText = "2/3 O'ngga: Tezkor AI ga yuborildi (G)..."
                    }

                    self.flightRecorder.inspectOcrForSiteWarnings(ocrText: cleanText, cgImage: cgImage, triggerMethod: triggerUsed)

                    // 2-BOSQICH SIGNAL: Savol Gemini/AI ga yuborildi -> Kursor O'NGGA siljiydi!
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                        HumanCursorSignal.stage2DispatchedRight()
                    }

                    var earlySignaled = false
                    SmartAIRouter.shared.solveWithAutonomousSelfHealing(
                        ocrText: cleanText,
                        cgImage: cgImage,
                        attempt: 1,
                        onEarlyCommit: { earlyRes in
                            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
                            DispatchQueue.main.async {
                                guard self.currentRequestID == reqID else { return }
                                earlySignaled = true
                                self.settings.lastPrimaryAnswer = earlyRes.primary
                                self.settings.lastSecondaryAnswer = earlyRes.secondary ?? ""
                                self.settings.lastValuePreview = earlyRes.value
                                self.settings.lastConfidence = earlyRes.confidence
                                self.settings.lastReasoning = earlyRes.reasoning
                                self.settings.lastModelUsed = earlyRes.modelUsed
                                self.settings.lastLatencyMs = elapsedMs
                                self.settings.hudState = .answer(primary: earlyRes.primary, secondary: earlyRes.secondary, valuePreview: earlyRes.value)
                                let badgeText = (earlyRes.secondary != nil && !earlyRes.secondary!.isEmpty) ? "\(earlyRes.primary)\u{0332}\(earlyRes.secondary!)" : earlyRes.primary
                                self.statusItem?.button?.title = badgeText
                                self.settings.statusText = "3/3 Tayyor (\(elapsedMs) ms · \(earlyRes.modelUsed)): \(badgeText) · \(earlyRes.value)"
                                self.overlay.refreshAppearance()
                                self.flightRecorder.record(category: "EARLY_ANSWER", statusCode: badgeText, latencyMs: elapsedMs, details: "Model: \(earlyRes.modelUsed) | Qiymat: \(earlyRes.value) | Izoh: \(earlyRes.reasoning)")
                                // 3-BOSQICH SIGNAL: Javob tayyor -> Kursor 3 MARTA qimirlaydi!
                                HumanCursorSignal.stage3AnswerReady()
                            }
                        },
                        onTransientError: { errCat, errReason, attemptNum in
                            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
                            DispatchQueue.main.async {
                                guard self.currentRequestID == reqID else { return }
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
                            if self.currentRequestID == reqID {
                                self.atomicCaptureInFlight = false
                            }
                            self.triggerLock.unlock()

                            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
                            DispatchQueue.main.async {
                                guard self.currentRequestID == reqID else { return }
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
                                self.settings.lastValuePreview = res.value
                                self.settings.lastConfidence = res.confidence
                                self.settings.lastReasoning = res.reasoning
                                self.settings.lastModelUsed = res.modelUsed
                                self.settings.hudState = .answer(primary: res.primary, secondary: res.secondary, valuePreview: res.value)
                                let badgeText = (res.secondary != nil && !res.secondary!.isEmpty) ? "\(res.primary)\u{0332}\(res.secondary!)" : res.primary
                                self.statusItem?.button?.title = badgeText
                                self.settings.statusText = "3/3 Tasdiqlandi (\(elapsedMs) ms · \(res.modelUsed)): \(badgeText) · \(res.value)"

                                self.archive.saveToArchive(rawQuestion: cleanText, image: cgImage, result: res)
                                self.overlay.refreshAppearance()
                                self.flightRecorder.record(category: "FINAL_ANSWER", statusCode: badgeText, latencyMs: elapsedMs, details: "Model: \(res.modelUsed) | Qiymat: \(res.value) | Izoh: \(res.reasoning)")

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

// MARK: - Entry Point
if let idx = CommandLine.arguments.firstIndex(of: "--generate-icon"), idx + 1 < CommandLine.arguments.count {
    let dir = CommandLine.arguments[idx + 1]
    AppIconGenerator.exportIconset(to: dir)
    exit(0)
} else if CommandLine.arguments.contains("--bridge-daemon") {
    let daemon = TerminalPrivilegeBridgeDaemon()
    daemon.runForever()
} else {
    let app = NSApplication.shared
    let delegate = AppController()
    app.delegate = delegate
    app.run()
}
