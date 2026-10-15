import AppKit
import CoreGraphics
import SlopCore

/// Настоящий пиксельный режим: сцена рисуется в маленькую картинку без
/// сглаживания, а потом растягивается на окно без размытия. Округление
/// вершин до сетки, как было раньше, оставляло линии гладкими — пикселей
/// видно не было.
struct PixelRenderer {
    /// Размер пикселя в точках окна: ширина сцены делится на число пикселей.
    static func block(width: CGFloat, resolution: CGFloat) -> CGFloat {
        max(2, (width / max(16, resolution)).rounded())
    }

    func image(of snapshot: DrawSnapshot, size: CGSize, block: CGFloat) -> CGImage? {
        let w = max(1, Int((size.width / block).rounded(.up)))
        let h = max(1, Int((size.height / block).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Координаты сцены — от верхнего левого угла, как в окне.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1 / block, y: -1 / block)
        ctx.setShouldAntialias(false)
        ctx.setAllowsAntialiasing(false)
        ctx.interpolationQuality = .none

        ctx.setFillColor(cg(snapshot.background))
        ctx.fill(CGRect(origin: .zero, size: size))
        for primitive in snapshot.primitives {
            switch primitive {
            case .line(let line):
                guard let first = line.points.first else { continue }
                ctx.beginPath(); ctx.move(to: first)
                line.points.dropFirst().forEach { ctx.addLine(to: $0) }
                stroke(ctx, line.stroke, block: block)
            case .rect(let rect):
                let path = CGPath(roundedRect: rect.rect, cornerWidth: rect.cornerRadius,
                                  cornerHeight: rect.cornerRadius, transform: nil)
                paint(ctx, path, fill: rect.fill, stroke: rect.stroke, block: block)
            case .circle(let circle):
                let r = circle.radius
                let path = CGPath(ellipseIn: CGRect(x: circle.center.x - r, y: circle.center.y - r,
                                                    width: r * 2, height: r * 2), transform: nil)
                paint(ctx, path, fill: circle.fill, stroke: circle.stroke, block: block)
            case .polygon(let polygon):
                guard let first = polygon.points.first else { continue }
                let path = CGMutablePath()
                path.move(to: first)
                polygon.points.dropFirst().forEach { path.addLine(to: $0) }
                path.closeSubpath()
                paint(ctx, path, fill: polygon.fill, stroke: polygon.stroke, block: block)
            case .text:
                continue          // надписи в пиксельной сцене не нужны
            }
        }
        return ctx.makeImage()
    }

    private func cg(_ c: DrawSnapshot.ColorValue) -> CGColor {
        CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    private func paint(_ ctx: CGContext, _ path: CGPath, fill: DrawSnapshot.ColorValue?,
                       stroke line: DrawSnapshot.Stroke?, block: CGFloat) {
        if let fill {
            ctx.addPath(path); ctx.setFillColor(cg(fill)); ctx.fillPath()
        }
        if let line {
            ctx.addPath(path); stroke(ctx, line, block: block)
        }
    }

    private func stroke(_ ctx: CGContext, _ line: DrawSnapshot.Stroke, block: CGFloat) {
        // Контур — не тоньше одного пикселя, иначе без сглаживания он рвётся.
        ctx.setLineWidth(max(line.width, block))
        ctx.setStrokeColor(cg(line.color))
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.strokePath()
    }
}
