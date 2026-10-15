import CoreGraphics
import Foundation
import SlopCore

typealias GameCore = WaveModel

extension GameCore {
    func makeSnapshot() -> DrawSnapshot {
        let viewport = snapshotViewportSize()
        let size = viewport.width > 1 && viewport.height > 1 ? viewport : CGSize(width: 1000, height: 560)

        let accent: DrawSnapshot.ColorValue = theme == .dark ? .white : .black
        let background: DrawSnapshot.ColorValue = theme == .dark ? .black : .white
        let selection = DrawSnapshot.ColorValue(r: 0.2, g: 0.7, b: 1.0, a: 1)
        let fillOpacity: CGFloat = theme == .dark ? 0.08 : 0.06

        // Геометрия всегда точная: пиксели делает PixelRenderer, рисуя сцену
        // в маленькую картинку. Округлять вершины здесь незачем.
        let pixelStep: CGFloat = 1

        func snap(_ value: CGFloat) -> CGFloat {
            guard pixelStep > 1 else { return value }
            return (value / pixelStep).rounded(.toNearestOrAwayFromZero) * pixelStep
        }

        func snap(_ point: CGPoint) -> CGPoint {
            CGPoint(x: snap(point.x), y: snap(point.y))
        }

        func rotate(_ point: CGPoint, angle: CGFloat) -> CGPoint {
            let c = cos(angle)
            let s = sin(angle)
            return CGPoint(x: point.x * c - point.y * s, y: point.x * s + point.y * c)
        }

        func worldPoint(local: CGPoint, center: CGPoint, angle: CGFloat) -> CGPoint {
            let p = rotate(local, angle: angle)
            return snap(CGPoint(x: center.x + p.x, y: center.y + p.y))
        }

        func appendPolygon(
            _ array: inout [DrawSnapshot.Primitive],
            _ points: [CGPoint],
            fill: DrawSnapshot.ColorValue?,
            stroke: DrawSnapshot.Stroke?
        ) {
            guard points.count > 1 else { return }
            array.append(.polygon(.init(points: points, fill: fill, stroke: stroke)))
        }

        var primitives: [DrawSnapshot.Primitive] = []
        let centerY = snap(surfaceBaselineY(in: size))

        var surfacePoints: [CGPoint] = [CGPoint(x: 0, y: centerY)]
        if samples.count > 1 {
            let width = max(size.width, 1)
            let step: CGFloat = pixelationEnabled ? max(2, pixelStep * 0.5) : 4
            for x in stride(from: CGFloat(0), through: size.width, by: step) {
                let normalizedX = x / width
                let sampleIndex = normalizedX * CGFloat(samples.count - 1)
                let left = min(Int(sampleIndex), samples.count - 1)
                let right = min(left + 1, samples.count - 1)
                let fraction = sampleIndex - CGFloat(left)
                let displacement: CGFloat
                if sceneLocation == .water {
                    displacement = samples[left] + (samples[right] - samples[left]) * fraction
                } else {
                    displacement = 0
                }
                surfacePoints.append(snap(CGPoint(x: x, y: centerY + displacement)))
            }
        } else {
            surfacePoints.append(CGPoint(x: size.width, y: centerY))
        }

        if sceneLocation == .water {
            var fill = surfacePoints
            fill.append(snap(CGPoint(x: size.width, y: size.height)))
            fill.append(snap(CGPoint(x: 0, y: size.height)))
            appendPolygon(&primitives, fill, fill: accent.alpha(fillOpacity), stroke: nil)
        } else {
            primitives.append(
                .rect(
                    .init(
                        rect: CGRect(x: 0, y: centerY, width: size.width, height: max(1, size.height - centerY)),
                        cornerRadius: 0,
                        fill: accent.alpha(fillOpacity),
                        stroke: nil
                    )
                )
            )
        }

        let halfSquare = squareSize * 0.5
        let bodyStrokeWidth: CGFloat = pixelationEnabled ? max(1.0, round(pixelStep * 0.35)) : 2.5
        let selectionStrokeWidth: CGFloat = pixelationEnabled ? max(2.0, round(pixelStep * 0.55)) : 4.5
        let selectionDash: [CGFloat] = pixelationEnabled
            ? [max(3, round(pixelStep * 0.8)), max(2, round(pixelStep * 0.5))]
            : [6, 4]

        for body in bodyDrawStates {
            let stroke = DrawSnapshot.Stroke(color: accent, width: bodyStrokeWidth)
            let selectedStroke = DrawSnapshot.Stroke(color: selection.alpha(0.7), width: selectionStrokeWidth, dash: selectionDash)
            let baseFill = accent.alpha(fillOpacity)

            let featurePalette: [(Bool, DrawSnapshot.ColorValue)] = [
                (body.isBouncy, .init(r: 0.33, g: 0.88, b: 0.52, a: 1)),
                (body.isSlippery, .init(r: 0.39, g: 0.68, b: 0.97, a: 1)),
                (body.isSticky, .init(r: 0.96, g: 0.76, b: 0.25, a: 1)),
                (body.isGlass, theme == .dark ? .white : .black),
                (body.isThruster, .init(r: 0.94, g: 0.34, b: 0.31, a: 1)),
            ]
            var count: CGFloat = 0
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            for item in featurePalette where item.0 {
                count += 1
                r += item.1.r
                g += item.1.g
                b += item.1.b
            }
            let featureFill: DrawSnapshot.ColorValue? = {
                guard count > 0 else { return nil }
                return .init(r: r / count, g: g / count, b: b / count, a: min(0.3, 0.16 + 0.05 * (count - 1)))
            }()

            switch body.shape {
            case .cube:
                let local = [
                    CGPoint(x: -halfSquare, y: -halfSquare),
                    CGPoint(x: halfSquare, y: -halfSquare),
                    CGPoint(x: halfSquare, y: halfSquare),
                    CGPoint(x: -halfSquare, y: halfSquare),
                ]
                let world = local.map { worldPoint(local: $0, center: body.center, angle: body.angle) }
                appendPolygon(&primitives, world, fill: baseFill, stroke: nil)
                if let featureFill { appendPolygon(&primitives, world, fill: featureFill, stroke: nil) }
                appendPolygon(&primitives, world, fill: nil, stroke: stroke)
                if body.isSelected { appendPolygon(&primitives, world, fill: nil, stroke: selectedStroke) }
            case .circle:
                let center = snap(body.center)
                primitives.append(.circle(.init(center: center, radius: circleRadius, fill: baseFill, stroke: nil)))
                if let featureFill {
                    primitives.append(.circle(.init(center: center, radius: circleRadius, fill: featureFill, stroke: nil)))
                }
                primitives.append(.circle(.init(center: center, radius: circleRadius, fill: nil, stroke: stroke)))
                if body.isSelected {
                    primitives.append(.circle(.init(center: center, radius: circleRadius, fill: nil, stroke: selectedStroke)))
                }
            case .polygon:
                guard let local = body.localVertices, local.count > 1 else { continue }
                let world = local.map { worldPoint(local: $0, center: body.center, angle: body.angle) }
                appendPolygon(&primitives, world, fill: baseFill, stroke: nil)
                if let featureFill { appendPolygon(&primitives, world, fill: featureFill, stroke: nil) }
                appendPolygon(&primitives, world, fill: nil, stroke: stroke)
                if body.isSelected { appendPolygon(&primitives, world, fill: nil, stroke: selectedStroke) }
            }

            if body.isThruster {
                let exhaustY: CGFloat = {
                    switch body.shape {
                    case .cube: return halfSquare
                    case .circle: return circleRadius
                    case .polygon: return body.localVertices?.map(\.y).max() ?? halfSquare
                    }
                }()
                let nozzleWidth = max(10, squareSize * 0.24)
                let nozzleHeight = max(4, squareSize * 0.08)
                let nozzle = [
                    CGPoint(x: -nozzleWidth * 0.5, y: exhaustY - nozzleHeight * 0.7),
                    CGPoint(x: nozzleWidth * 0.5, y: exhaustY - nozzleHeight * 0.7),
                    CGPoint(x: nozzleWidth * 0.5, y: exhaustY + nozzleHeight * 0.3),
                    CGPoint(x: -nozzleWidth * 0.5, y: exhaustY + nozzleHeight * 0.3),
                ].map { worldPoint(local: $0, center: body.center, angle: body.angle) }

                let nozzleStroke = DrawSnapshot.Stroke(
                    color: accent.alpha(body.isThrusterActive ? 0.98 : 0.55),
                    width: max(1.0, bodyStrokeWidth * 0.45)
                )
                appendPolygon(
                    &primitives,
                    nozzle,
                    fill: accent.alpha(body.isThrusterActive ? 0.82 : 0.35),
                    stroke: nozzleStroke
                )
            }

            if body.isWheel {
                let center = snap(body.center)
                primitives.append(.circle(.init(center: center, radius: 6, fill: nil, stroke: .init(color: accent, width: 1.4))))
                primitives.append(.circle(.init(center: center, radius: 1.5, fill: accent, stroke: nil)))
            }
        }

        for chunk in waterChunkDrawStates {
            let speed = hypot(chunk.velocity.dx, chunk.velocity.dy)
            if chunk.tailLength > 0.1, speed > 0.001 {
                let dir = CGVector(dx: chunk.velocity.dx / speed, dy: chunk.velocity.dy / speed)
                let tail = CGPoint(x: chunk.center.x - dir.dx * chunk.tailLength, y: chunk.center.y - dir.dy * chunk.tailLength)
                primitives.append(
                    .line(
                        .init(
                            points: [snap(chunk.center), snap(tail)],
                            stroke: .init(color: accent.alpha(chunk.opacity * 0.55), width: max(0.6, chunk.radius * 0.45))
                        )
                    )
                )
            }
            primitives.append(
                .circle(
                    .init(
                        center: snap(chunk.center),
                        radius: chunk.radius,
                        fill: accent.alpha(chunk.opacity),
                        stroke: .init(color: accent.alpha(min(1, chunk.opacity + 0.18)), width: max(0.5, chunk.radius * 0.22))
                    )
                )
            )
        }

        let glassBase: DrawSnapshot.ColorValue = theme == .dark ? .init(r: 1, g: 1, b: 1, a: 0.72) : .init(r: 0, g: 0, b: 0, a: 0.62)
        let glassEdge: DrawSnapshot.ColorValue = theme == .dark ? .init(r: 1, g: 1, b: 1, a: 0.95) : .init(r: 0, g: 0, b: 0, a: 0.9)

        for shard in glassShardDrawStates {
            let speed = hypot(shard.velocity.dx, shard.velocity.dy)
            if speed > 0.18 {
                let nx = shard.velocity.dx / max(0.001, speed)
                let ny = shard.velocity.dy / max(0.001, speed)
                let end = CGPoint(
                    x: shard.center.x - nx * shard.radius * shard.stretch * 2.4,
                    y: shard.center.y - ny * shard.radius * shard.stretch * 2.4
                )
                primitives.append(
                    .line(
                        .init(
                            points: [snap(shard.center), snap(end)],
                            stroke: .init(color: glassBase.alpha(shard.opacity * 0.45), width: max(0.45, shard.radius * 0.35))
                        )
                    )
                )
            }

            let w = shard.radius * (1.2 + shard.stretch * 0.9)
            let h = shard.radius * (0.48 + shard.stretch * 0.35)
            let local: [CGPoint]
            switch shard.kind {
            case 0:
                local = [CGPoint(x: -w * 0.9, y: 0), CGPoint(x: w * 0.7, y: -h * 0.7), CGPoint(x: w * 0.45, y: h * 0.78)]
            case 1:
                local = [CGPoint(x: 0, y: -h), CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), CGPoint(x: -w, y: 0)]
            default:
                local = [CGPoint(x: -w, y: -h * 0.42), CGPoint(x: w, y: -h * 0.42), CGPoint(x: w, y: h * 0.42), CGPoint(x: -w, y: h * 0.42)]
            }
            let world = local.map {
                let p = rotate($0, angle: shard.angle)
                return snap(CGPoint(x: shard.center.x + p.x, y: shard.center.y + p.y))
            }
            appendPolygon(
                &primitives,
                world,
                fill: glassBase.alpha(shard.opacity),
                stroke: .init(color: glassEdge.alpha(min(1, shard.opacity + 0.18)), width: max(0.55, shard.radius * 0.2))
            )
        }

        for particle in thrusterParticleDrawStates {
            let glow = DrawSnapshot.ColorValue(r: 1.0, g: 0.2 + 0.35 * particle.heat, b: 0.12, a: particle.opacity * 0.45)
            let core = DrawSnapshot.ColorValue(r: 1.0, g: 0.35 + 0.45 * particle.heat, b: 0.15 + 0.12 * (1 - particle.heat), a: particle.opacity)
            primitives.append(.circle(.init(center: snap(particle.center), radius: particle.radius * 1.9, fill: glow, stroke: nil)))
            primitives.append(.circle(.init(center: snap(particle.center), radius: particle.radius, fill: core, stroke: nil)))
        }

        for drop in stickyDripParticleDrawStates {
            let glow = DrawSnapshot.ColorValue(r: 1.0, g: 0.88, b: 0.38, a: drop.opacity * 0.36)
            let core = DrawSnapshot.ColorValue(r: 0.95, g: 0.8, b: 0.3, a: drop.opacity * 0.96)
            primitives.append(.circle(.init(center: snap(drop.center), radius: drop.radius * 1.45, fill: glow, stroke: nil)))
            primitives.append(.circle(.init(center: snap(drop.center), radius: drop.radius * 0.72, fill: core, stroke: nil)))
        }

        if let selectionRect {
            primitives.append(
                .rect(
                    .init(
                        rect: CGRect(
                            x: snap(selectionRect.minX),
                            y: snap(selectionRect.minY),
                            width: snap(selectionRect.width),
                            height: snap(selectionRect.height)
                        ),
                        cornerRadius: 0,
                        fill: nil,
                        stroke: .init(color: selection.alpha(0.7), width: 1.4, dash: [6, 4])
                    )
                )
            )
        }

        if drawingPreviewPoints.count > 1 {
            var preview = drawingPreviewPoints.map(snap)
            if drawingPreviewClosed, let first = preview.first {
                preview.append(first)
            }
            primitives.append(.line(.init(points: preview, stroke: .init(color: accent.alpha(0.8), width: 1.6, dash: [6, 4]))))
        }

        if weldToolEnabled, let cursor = weldCursorPoint {
            primitives.append(.circle(.init(center: snap(cursor), radius: 4, fill: accent, stroke: nil)))
        }

        if weldToolEnabled, let pending = weldPendingPoint {
            let p = snap(pending)
            primitives.append(.circle(.init(center: p, radius: 6, fill: nil, stroke: .init(color: accent, width: 1.4))))
            if let cursor = weldCursorPoint {
                primitives.append(
                    .line(
                        .init(
                            points: [p, snap(cursor)],
                            stroke: .init(color: accent.alpha(0.5), width: 1.2, dash: [5, 5])
                        )
                    )
                )
            }
        }

        if wheelToolEnabled, let cursor = wheelCursorPoint {
            let center = snap(cursor)
            primitives.append(.circle(.init(center: center, radius: 7, fill: nil, stroke: .init(color: accent.alpha(0.9), width: 1.2))))
            primitives.append(.circle(.init(center: center, radius: 2, fill: accent.alpha(0.9), stroke: nil)))
        }

        if surfacePoints.count > 1 {
            primitives.append(.line(.init(points: surfacePoints, stroke: .init(color: accent, width: bodyStrokeWidth))))
        }

        return DrawSnapshot(background: background, primitives: primitives)
    }
}

extension GameCore {
    func update(dt: TimeInterval, input: InputState, in size: CGSize) {
        _ = dt
        let timestamp = input.timestamp > 0 ? input.timestamp : Date().timeIntervalSinceReferenceDate

        if input.modifiers.shift != isShiftModifierPressed() {
            setShiftModifier(input.modifiers.shift)
        }

        if input.mouseMoved || !input.mouseDown.isEmpty || !input.mouseUp.isEmpty {
            pointerMoved(
                to: input.mousePos,
                timestamp: timestamp,
                in: size,
                isShiftPressed: input.modifiers.shift
            )
        }

        if let location = input.mousePos {
            if input.mouseDown.contains(.left) {
                pointerDown(
                    at: location,
                    button: .left,
                    timestamp: timestamp,
                    in: size,
                    isShiftPressed: input.modifiers.shift
                )
            }
            if input.mouseDown.contains(.right) {
                pointerDown(
                    at: location,
                    button: .right,
                    timestamp: timestamp,
                    in: size,
                    isShiftPressed: input.modifiers.shift
                )
            }
            if input.mouseUp.contains(.left) {
                pointerUp(
                    at: location,
                    button: .left,
                    timestamp: timestamp,
                    in: size,
                    isShiftPressed: input.modifiers.shift
                )
            }
            if input.mouseUp.contains(.right) {
                pointerUp(
                    at: location,
                    button: .right,
                    timestamp: timestamp,
                    in: size,
                    isShiftPressed: input.modifiers.shift
                )
            }
        }

        let blockedBySystemModifiers = input.modifiers.command || input.modifiers.control || input.modifiers.option
        if !input.keysDown.isEmpty {
            for keyCode in input.keysDown.sorted() {
                _ = handleInputKeyDown(
                    keyCode: keyCode,
                    shiftPressed: input.modifiers.shift,
                    blockedBySystemModifiers: blockedBySystemModifiers
                )
            }
        }
    }
}
