import Foundation

/// Замеры физики без окна: насколько она похожа на настоящую.
/// Запуск: SlopSandbox --physics. Единицы — точки экрана и секунды.
@MainActor
enum PhysicsProbe {
    static let size = CGSize(width: 1100, height: 640)
    static let fps: CGFloat = 60

    static func scene(_ location: GameCore.SceneLocation) -> GameCore {
        let m = GameCore()
        m.setViewportSize(size)
        m.sceneLocation = location
        m.resetScene()
        m.debugClearBodies()
        return m
    }

    static func run() -> Int {
        // 1. Падение кубика с высоты 400 точек: время и ускорение.
        do {
            let m = scene(.land)
            let ground = m.debugGroundY
            let start = CGPoint(x: 550, y: ground - 28 - 400)
            let id = m.debugPlace(circle: false, at: start)
            var steps = 0
            while steps < 600, let s = m.debugState(id), s.center.y < ground - 28 - 1 {
                m.advance(steps: 1); steps += 1
            }
            let t = CGFloat(steps) / fps
            print(String(format: "падение 400 точек: %.2f с, ускорение ≈ %.0f точек/с²", t, 2 * 400 / (t * t)))
        }
        // 2. Башня из шести кубиков: снос верхнего за 5 секунд.
        do {
            let m = scene(.land)
            let ground = m.debugGroundY
            var ids: [UUID] = []
            for k in 0..<6 {
                ids.append(m.debugPlace(circle: false, at: CGPoint(x: 550, y: ground - 28 - CGFloat(k) * 56)))
            }
            m.advance(steps: 300)
            let top = m.debugState(ids.last!)!
            print(String(format: "башня: верх сдвинулся на %.1f точки, наклон %.1f°, высота %.0f из %.0f",
                         top.center.x - 550, top.angle * 180 / .pi, ground - top.center.y, 5.5 * 56))
        }
        // 3. Шар с начальной скоростью: сколько прокатился и крутится ли.
        do {
            let m = scene(.land)
            let ground = m.debugGroundY
            let id = m.debugPlace(circle: true, at: CGPoint(x: 200, y: ground - 28), velocity: CGVector(dx: 6, dy: 0))
            var trace: [String] = []
            for k in 0..<12 {
                m.advance(steps: 10)
                if let s = m.debugState(id) {
                    trace.append(String(format: "%d:x%.0f v%.0f w%.2f", (k + 1) * 10, s.center.x, s.velocity.dx * fps, s.spin * fps))
                }
            }
            print("  " + trace.joined(separator: "  "))
            let s = m.debugState(id)!
            print(String(format: "шар за 2 с: прошёл %.0f точек, повернулся на %.0f° (качение даёт %.0f°), скорость %.1f",
                         s.center.x - 200, s.angle * 180 / .pi, (s.center.x - 200) / 28 * 180 / .pi, s.velocity.dx * fps))
        }
        // 4. Бросок: быстрая скорость не должна срезаться.
        do {
            let m = scene(.land)
            let id = m.debugPlace(circle: false, at: CGPoint(x: 200, y: 200), velocity: CGVector(dx: 30, dy: -20))
            m.advance(steps: 1)
            let s = m.debugState(id)!
            print(String(format: "бросок 1800,-1200 точек/с: после шага %.0f,%.0f", s.velocity.dx * fps, s.velocity.dy * fps))
        }
        // 5. Кручение: быстро вращающийся кубик.
        do {
            let m = scene(.land)
            let id = m.debugPlace(circle: false, at: CGPoint(x: 550, y: 200))
            _ = id
            print("кручение: см. ограничение угловой скорости в коде")
        }
        return 0
    }
}
