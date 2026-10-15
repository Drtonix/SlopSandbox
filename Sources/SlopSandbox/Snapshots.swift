import AppKit
import SwiftUI

/// Снимки сцен без окна: физика прогоняется шагами, экран рисуется в PNG.
/// Нужны, чтобы проверять игру, не открывая её.
@MainActor
enum Snapshots {
    static let size = CGSize(width: 1100, height: 640)

    static func run(into folder: String) -> Int {
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for location in [GameCore.SceneLocation.water, .land] {
            let model = GameCore()
            model.setViewportSize(size)
            model.sceneLocation = location
            model.resetScene()
            for n in 0..<6 {
                if n % 2 == 0 { model.addCube() } else { model.addCircle() }
            }
            // Кадр каждые полсекунды игрового времени, шесть секунд.
            for frame in 0..<12 {
                save(model, dir.appendingPathComponent(
                    String(format: "%@-%02d.png", location.rawValue, frame)))
                model.advance(steps: 30)
            }
            print(location.rawValue, model.debugBodies())
        }
        // Вода: куча из 14 предметов падает разом.
        do {
            let model = GameCore()
            model.setViewportSize(size)
            model.sceneLocation = .water
            model.resetScene()
            model.debugClearBodies()
            for k in 0..<14 {
                model.debugPlace(circle: k % 3 == 1,
                                 at: CGPoint(x: 470 + CGFloat(k % 4) * 58, y: 60 + CGFloat(k / 4) * 60),
                                 angle: CGFloat(k) * 0.3)
            }
            for frame in 0..<12 {
                save(model, dir.appendingPathComponent(String(format: "pile-%02d.png", frame)))
                model.advance(steps: 20)
            }
            print("куча в воде:", model.debugOverlaps())
        }
        // Пиксельный режим: вода с телами при двух разрешениях.
        for resolution in [CGFloat(160), 80] {
            let model = GameCore()
            model.setViewportSize(size)
            model.sceneLocation = .water
            model.resetScene()
            for n in 0..<5 { if n % 2 == 0 { model.addCube() } else { model.addCircle() } }
            model.advance(steps: 90)
            model.pixelationEnabled = true
            model.pixelationGrid = resolution
            save(model, dir.appendingPathComponent("pixel-\(Int(resolution)).png"))
        }
        // Суша: башня из кубиков, в неё летит тяжёлый шар.
        do {
            let model = GameCore()
            model.setViewportSize(size)
            model.sceneLocation = .land
            model.resetScene()
            model.debugClearBodies()
            let ground = model.debugGroundY
            for row in 0..<5 {
                for col in 0..<2 {
                    model.debugPlace(circle: false, at: CGPoint(x: 700 + CGFloat(col) * 57,
                                                                y: ground - 28 - CGFloat(row) * 57))
                }
            }
            model.debugPlace(circle: true, at: CGPoint(x: 150, y: ground - 200),
                             velocity: CGVector(dx: 16, dy: -6))
            for frame in 0..<12 {
                save(model, dir.appendingPathComponent(String(format: "tower-%02d.png", frame)))
                model.advance(steps: 12)
            }
        }
        // Панель управления: вкладки по очереди, во всю высоту.
        let model = GameCore()
        model.setViewportSize(size)
        for tab in GameCore.QuickPanelTab.allCases {
            model.quickPanelTab = tab
            let panel = WaveControlsPanel(wave: model, height: 1200, width: 360).content
                .frame(width: 360)
                .background(Color(white: 0.1))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: panel)
            renderer.scale = 1
            if let image = renderer.cgImage {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("panel-\(tab.rawValue).png"))
            }
        }
        return 0
    }

    static func save(_ model: GameCore, _ url: URL) {
        // Только сцена: слой мыши — NSView, а их ImageRenderer не рисует.
        let snapshot = model.makeSnapshot()
        if model.pixelationEnabled {
            let block = PixelRenderer.block(width: size.width, resolution: model.pixelationGrid)
            if let small = PixelRenderer().image(of: snapshot, size: size, block: block) {
                let view = Image(decorative: small, scale: 1).interpolation(.none).resizable()
                    .frame(width: size.width, height: size.height)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                if let image = renderer.cgImage {
                    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
                }
                return
            }
        }
        let view = Canvas { context, canvas in
            AppleRenderer2D().draw(snapshot: snapshot, in: &context, canvasSize: canvas)
        }.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
