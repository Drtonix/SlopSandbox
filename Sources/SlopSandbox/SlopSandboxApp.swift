import AppKit
import CBox2D
import Foundation
import SwiftUI

@main
final class SlopSandboxApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    static func main() {
        if CommandLine.arguments.contains("--smoke-test") {
            let exitCode = runSmokeTest()
            Foundation.exit(Int32(exitCode))
        }

        if let at = CommandLine.arguments.firstIndex(of: "--snapshot"),
           at + 1 < CommandLine.arguments.count {
            _ = NSApplication.shared
            Foundation.exit(Int32(Snapshots.run(into: CommandLine.arguments[at + 1])))
        }

        if CommandLine.arguments.contains("--physics") {
            _ = NSApplication.shared
            Foundation.exit(Int32(PhysicsProbe.run()))
        }

        let app = NSApplication.shared
        let delegate = SlopSandboxApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = Self.makeMenu()

        let contentView = WaveScreen()
            .frame(minWidth: 900, minHeight: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.title = "SlopSandbox"
        window.collectionBehavior.insert(.fullScreenPrimary)
        // Размер и место окна переживают перезапуск.
        window.setFrameAutosaveName("main")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    /// Строка меню как у обычного приложения: без неё не работает даже ⌘Q.
    private static func makeMenu() -> NSMenu {
        let ru = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
        func tr(_ r: String, _ e: String) -> String { ru ? r : e }
        let name = "SlopSandbox"
        let bar = NSMenu()

        let appItem = NSMenuItem(); bar.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: tr("О программе \(name)", "About \(name)"),
                    action: #selector(SlopSandboxApp.showAbout), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: tr("Скрыть \(name)", "Hide \(name)"),
                    action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: tr("Скрыть остальные", "Hide Others"),
                                 action: #selector(NSApplication.hideOtherApplications(_:)),
                                 keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: tr("Показать все", "Show All"),
                    action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: tr("Завершить \(name)", "Quit \(name)"),
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let windowItem = NSMenuItem(); bar.addItem(windowItem)
        let window = NSMenu(title: tr("Окно", "Window"))
        window.addItem(withTitle: tr("Свернуть", "Minimize"),
                       action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let full = window.addItem(withTitle: tr("Во весь экран", "Enter Full Screen"),
                                  action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]
        windowItem.submenu = window
        NSApp.windowsMenu = window
        return bar
    }

    @objc func showAbout() {
        let credits = NSMutableAttributedString(string: "DrTonix · ", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(NSAttributedString(string: "bdub.space", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .link: URL(string: "https://bdub.space")!]))
        // Поддержать: те же ссылки и кошелёк, что во всех открытых приложениях.
        let ru = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
        let plain: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        credits.append(NSAttributedString(string: ru ? "\n\nПоддержать\n" : "\n\nSupport\n", attributes: plain))
        let links = [("DonationAlerts", "https://www.donationalerts.com/r/bdub"),
                     ("DALINK", "https://dalink.to/bdub"),
                     ("CloudTips", "https://pay.cloudtips.ru/p/4a29ea73")]
        for (name, url) in links {
            credits.append(NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .link: URL(string: url)!]))
            credits.append(NSAttributedString(string: "      ", attributes: plain))
        }
        // Кошелёк — ссылкой, но щелчок копирует адрес (см. AboutLinks), а не открывает.
        credits.append(NSAttributedString(string: "USDT TRC-20", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .link: AboutLinks.copy]))
        let centered = NSMutableParagraphStyle(); centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        // Текст панели — NSTextView без своего делегата: ставим свой, чтобы
        // щелчок по адресу копировал его.
        for window in NSApp.windows where window.isVisible {
            var stack: [NSView] = window.contentView.map { [$0] } ?? []
            while let view = stack.popLast() {
                if let text = view as? NSTextView, text.string.contains("USDT TRC-20") {
                    text.delegate = AboutLinks.shared
                }
                stack += view.subviews
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private static func runSmokeTest() -> Int {
        var worldDef = b2DefaultWorldDef()
        worldDef.gravity = b2Vec2(x: 0, y: 9.8)
        let worldId = b2CreateWorld(&worldDef)
        guard b2World_IsValid(worldId) else { return 1 }
        defer { b2DestroyWorld(worldId) }

        var allBodies: [b2BodyId] = []
        allBodies.reserveCapacity(20)
        var controlBodies: [b2BodyId] = []
        controlBodies.reserveCapacity(5)

        func makeStaticBox(centerX: Float, centerY: Float, halfW: Float, halfH: Float) -> Bool {
            var bodyDef = b2DefaultBodyDef()
            bodyDef.type = b2_staticBody
            bodyDef.position = b2Vec2(x: centerX, y: centerY)
            let bodyId = b2CreateBody(worldId, &bodyDef)
            guard b2Body_IsValid(bodyId) else { return false }
            var shapeDef = b2DefaultShapeDef()
            shapeDef.density = 0
            var poly = b2MakeBox(halfW, halfH)
            let shapeId = b2CreatePolygonShape(bodyId, &shapeDef, &poly)
            guard b2Shape_IsValid(shapeId) else { return false }
            allBodies.append(bodyId)
            return true
        }

        func makeDynamicSquare(centerX: Float, centerY: Float, half: Float) -> b2BodyId {
            var bodyDef = b2DefaultBodyDef()
            bodyDef.type = b2_dynamicBody
            bodyDef.position = b2Vec2(x: centerX, y: centerY)
            let bodyId = b2CreateBody(worldId, &bodyDef)
            guard b2Body_IsValid(bodyId) else { return b2_nullBodyId }
            var shapeDef = b2DefaultShapeDef()
            shapeDef.density = 1.0
            shapeDef.material.friction = 0.5
            shapeDef.material.restitution = 0.12
            var poly = b2MakeBox(half, half)
            let shapeId = b2CreatePolygonShape(bodyId, &shapeDef, &poly)
            guard b2Shape_IsValid(shapeId) else { return b2_nullBodyId }
            return bodyId
        }

        func makeDynamicCircle(centerX: Float, centerY: Float, radius: Float) -> b2BodyId {
            var bodyDef = b2DefaultBodyDef()
            bodyDef.type = b2_dynamicBody
            bodyDef.position = b2Vec2(x: centerX, y: centerY)
            let bodyId = b2CreateBody(worldId, &bodyDef)
            guard b2Body_IsValid(bodyId) else { return b2_nullBodyId }
            var shapeDef = b2DefaultShapeDef()
            shapeDef.density = 1.0
            shapeDef.material.friction = 0.35
            shapeDef.material.restitution = 0.1
            var circle = b2Circle()
            circle.center = b2Vec2(x: 0, y: 0)
            circle.radius = radius
            let shapeId = b2CreateCircleShape(bodyId, &shapeDef, &circle)
            guard b2Shape_IsValid(shapeId) else { return b2_nullBodyId }
            return bodyId
        }

        // 10 static bodies (ground, walls, top and platforms).
        let staticSetup: [(Float, Float, Float, Float)] = [
            (0, 12.0, 40.0, 0.5),   // floor
            (-40.0, 0.0, 0.5, 20.0), // left wall
            (40.0, 0.0, 0.5, 20.0),  // right wall
            (0.0, -18.0, 40.0, 0.5), // top
            (-12.0, 9.5, 3.0, 0.4),
            (-4.0, 8.0, 2.5, 0.35),
            (4.0, 7.0, 2.8, 0.35),
            (11.0, 10.0, 2.6, 0.35),
            (-16.0, 5.5, 2.2, 0.3),
            (16.0, 6.2, 2.2, 0.3),
        ]
        for body in staticSetup {
            guard makeStaticBox(centerX: body.0, centerY: body.1, halfW: body.2, halfH: body.3) else {
                return 1
            }
        }

        // 10 dynamic bodies (mix circles and squares).
        for i in 0..<10 {
            let x = Float(-10 + i * 2)
            let y = Float(-8 + (i % 3))
            let bodyId: b2BodyId
            if i % 2 == 0 {
                bodyId = makeDynamicSquare(centerX: x, centerY: y, half: 0.6)
            } else {
                bodyId = makeDynamicCircle(centerX: x, centerY: y, radius: 0.62)
            }
            guard b2Body_IsValid(bodyId) else { return 1 }
            allBodies.append(bodyId)
            if controlBodies.count < 5 {
                controlBodies.append(bodyId)
            }
        }

        guard allBodies.count == 20, controlBodies.count == 5 else { return 1 }

        let dt: Float = 1.0 / 60.0
        let totalSteps = 5 * 60
        for _ in 0..<totalSteps {
            b2World_Step(worldId, dt, 4)
        }

        func isFinite(_ value: Float) -> Bool {
            value.isFinite && !value.isNaN
        }

        var kineticEnergyTotal: Double = 0
        for bodyId in allBodies {
            guard b2Body_IsValid(bodyId) else { return 1 }
            let v = b2Body_GetLinearVelocity(bodyId)
            let w = b2Body_GetAngularVelocity(bodyId)
            if !isFinite(v.x) || !isFinite(v.y) || !isFinite(w) { return 1 }
            let mass = max(0, Double(b2Body_GetMass(bodyId)))
            let inertia = max(0, Double(b2Body_GetRotationalInertia(bodyId)))
            let speedSq = Double(v.x * v.x + v.y * v.y)
            kineticEnergyTotal += 0.5 * mass * speedSq + 0.5 * inertia * Double(w * w)
        }

        if !kineticEnergyTotal.isFinite || allBodies.isEmpty { return 1 }

        var controls: [[String: Any]] = []
        controls.reserveCapacity(controlBodies.count)
        for (index, bodyId) in controlBodies.enumerated() {
            guard b2Body_IsValid(bodyId) else { return 1 }
            let p = b2Body_GetPosition(bodyId)
            let v = b2Body_GetLinearVelocity(bodyId)
            if !isFinite(p.x) || !isFinite(p.y) || !isFinite(v.x) || !isFinite(v.y) { return 1 }
            controls.append([
                "index": index,
                "position": ["x": Double(p.x), "y": Double(p.y)],
                "velocity": ["x": Double(v.x), "y": Double(v.y)],
            ])
        }

        let result: [String: Any] = [
            "bodyCount": allBodies.count,
            "kineticEnergyTotal": kineticEnergyTotal,
            "controls": controls,
        ]

        guard JSONSerialization.isValidJSONObject(result) else { return 1 }
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            let outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("smoke_result.json")
            try data.write(to: outURL, options: .atomic)
        } catch {
            return 1
        }

        return 0
    }
}


/// Щелчок по адресу кошелька в «О программе» копирует его; остальные ссылки
/// открываются как обычно.
final class AboutLinks: NSObject, NSTextViewDelegate {
    static let shared = AboutLinks()
    static let wallet = "TEzUu8mVuNS1faHGobMWifmvErTuKUSkPD"
    static let copy = URL(string: "copy:usdt")!

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard (link as? URL) == AboutLinks.copy else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AboutLinks.wallet, forType: .string)
        return true
    }
}
