import CoreGraphics
import Foundation

public struct DrawSnapshot {
    public struct ColorValue {
        public var r: CGFloat
        public var g: CGFloat
        public var b: CGFloat
        public var a: CGFloat

        public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }

        public func alpha(_ value: CGFloat) -> ColorValue {
            ColorValue(r: r, g: g, b: b, a: value)
        }

        public static let white = ColorValue(r: 1, g: 1, b: 1, a: 1)
        public static let black = ColorValue(r: 0, g: 0, b: 0, a: 1)
    }

    public struct Stroke {
        public var color: ColorValue
        public var width: CGFloat
        public var dash: [CGFloat]

        public init(color: ColorValue, width: CGFloat, dash: [CGFloat] = []) {
            self.color = color
            self.width = width
            self.dash = dash
        }
    }

    public struct Circle {
        public var center: CGPoint
        public var radius: CGFloat
        public var fill: ColorValue?
        public var stroke: Stroke?

        public init(center: CGPoint, radius: CGFloat, fill: ColorValue?, stroke: Stroke?) {
            self.center = center
            self.radius = radius
            self.fill = fill
            self.stroke = stroke
        }
    }

    public struct Rect {
        public var rect: CGRect
        public var cornerRadius: CGFloat
        public var fill: ColorValue?
        public var stroke: Stroke?

        public init(rect: CGRect, cornerRadius: CGFloat, fill: ColorValue?, stroke: Stroke?) {
            self.rect = rect
            self.cornerRadius = cornerRadius
            self.fill = fill
            self.stroke = stroke
        }
    }

    public struct Polygon {
        public var points: [CGPoint]
        public var fill: ColorValue?
        public var stroke: Stroke?

        public init(points: [CGPoint], fill: ColorValue?, stroke: Stroke?) {
            self.points = points
            self.fill = fill
            self.stroke = stroke
        }
    }

    public struct Line {
        public var points: [CGPoint]
        public var stroke: Stroke

        public init(points: [CGPoint], stroke: Stroke) {
            self.points = points
            self.stroke = stroke
        }
    }

    public struct Text {
        public enum Align {
            case center
            case topLeading
        }

        public var value: String
        public var position: CGPoint
        public var size: CGFloat
        public var color: ColorValue
        public var align: Align

        public init(value: String, position: CGPoint, size: CGFloat, color: ColorValue, align: Align) {
            self.value = value
            self.position = position
            self.size = size
            self.color = color
            self.align = align
        }
    }

    public enum Primitive {
        case circle(Circle)
        case rect(Rect)
        case polygon(Polygon)
        case line(Line)
        case text(Text)
    }

    public var background: ColorValue
    public var primitives: [Primitive]

    public init(background: ColorValue, primitives: [Primitive]) {
        self.background = background
        self.primitives = primitives
    }
}

public struct InputState {
    public enum Button: Hashable {
        case left
        case right
        case middle
    }

    public struct Modifiers: Equatable {
        public var shift = false
        public var control = false
        public var option = false
        public var command = false

        public init(
            shift: Bool = false,
            control: Bool = false,
            option: Bool = false,
            command: Bool = false
        ) {
            self.shift = shift
            self.control = control
            self.option = option
            self.command = command
        }
    }

    public var mousePos: CGPoint?
    public var mouseMoved = false
    public var mouseDown: Set<Button> = []
    public var mouseUp: Set<Button> = []
    public var buttons: Set<Button> = []
    public var wheel: CGFloat = 0
    public var keysDown: Set<UInt16> = []
    public var modifiers = Modifiers()
    public var timestamp: TimeInterval = 0

    public init() {}
}

public protocol Renderer2D {
    associatedtype RenderContext

    func drawLine(_ line: DrawSnapshot.Line, in context: inout RenderContext)
    func drawRect(_ rect: DrawSnapshot.Rect, in context: inout RenderContext)
    func drawCircle(_ circle: DrawSnapshot.Circle, in context: inout RenderContext)
    func drawPolygon(_ polygon: DrawSnapshot.Polygon, in context: inout RenderContext)
    func drawText(_ text: DrawSnapshot.Text, in context: inout RenderContext)
}
