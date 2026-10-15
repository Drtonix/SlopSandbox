import CBox2D
import CoreGraphics
import Darwin
import Foundation
import SlopCore

private let sdlInitVideo: UInt32 = 0x0000_0020
private let sdlWindowShown: UInt32 = 0x0000_0004
private let sdlRendererAccelerated: UInt32 = 0x0000_0002
private let sdlRendererPresentVSync: UInt32 = 0x0000_0004

private let sdlQuitEvent: UInt32 = 0x100
private let sdlKeyDownEvent: UInt32 = 0x300
private let sdlMouseMotionEvent: UInt32 = 0x400
private let sdlMouseButtonDownEvent: UInt32 = 0x401
private let sdlMouseButtonUpEvent: UInt32 = 0x402
private let sdlMouseWheelEvent: UInt32 = 0x403

private let sdlButtonLeftMask: UInt32 = 1 << 0
private let sdlButtonMiddleMask: UInt32 = 1 << 1
private let sdlButtonRightMask: UInt32 = 1 << 2
private let sdlButtonLeftCode: UInt8 = 1
private let sdlButtonMiddleCode: UInt8 = 2
private let sdlButtonRightCode: UInt8 = 3

private let kmodShift: UInt16 = 0x0003
private let kmodControl: UInt16 = 0x00C0
private let kmodOption: UInt16 = 0x0300
private let kmodCommand: UInt16 = 0x0C00

private let scanQ: UInt16 = 20
private let scanW: UInt16 = 26
private let scanC: UInt16 = 6
private let scanEscape: UInt16 = 41

private struct Camera2D {
    var center: CGPoint
    var zoom: CGFloat
    var viewport: CGSize
    var pixelsPerMeter: CGFloat

    var scale: CGFloat {
        pixelsPerMeter * zoom
    }

    func worldToScreen(_ world: CGPoint) -> CGPoint {
        CGPoint(
            x: (world.x - center.x) * scale + viewport.width * 0.5,
            y: (world.y - center.y) * scale + viewport.height * 0.5
        )
    }

    func screenToWorld(_ screen: CGPoint) -> CGPoint {
        CGPoint(
            x: (screen.x - viewport.width * 0.5) / scale + center.x,
            y: (screen.y - viewport.height * 0.5) / scale + center.y
        )
    }

    mutating func panByScreenDelta(_ delta: CGVector) {
        center.x -= delta.dx / scale
        center.y -= delta.dy / scale
    }

    mutating func zoomByWheel(_ wheel: CGFloat, anchorScreen: CGPoint) {
        guard wheel != 0 else { return }
        let before = screenToWorld(anchorScreen)
        let factor = pow(1.08, wheel)
        zoom = min(6.0, max(0.15, zoom * factor))
        let after = screenToWorld(anchorScreen)
        center.x += before.x - after.x
        center.y += before.y - after.y
    }
}

private final class SDL2API {
    typealias InitFn = @convention(c) (UInt32) -> Int32
    typealias QuitFn = @convention(c) () -> Void
    typealias CreateWindowFn = @convention(c) (UnsafePointer<CChar>?, Int32, Int32, Int32, Int32, UInt32) -> UnsafeMutableRawPointer?
    typealias DestroyWindowFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias CreateRendererFn = @convention(c) (UnsafeMutableRawPointer?, Int32, UInt32) -> UnsafeMutableRawPointer?
    typealias DestroyRendererFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias SetDrawColorFn = @convention(c) (UnsafeMutableRawPointer?, UInt8, UInt8, UInt8, UInt8) -> Int32
    typealias RenderClearFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias RenderPresentFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias RenderDrawLineFn = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32, Int32, Int32) -> Int32
    typealias PollEventFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias GetMouseStateFn = @convention(c) (UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> UInt32
    typealias GetModStateFn = @convention(c) () -> UInt16
    typealias GetTicksFn = @convention(c) () -> UInt32
    typealias DelayFn = @convention(c) (UInt32) -> Void
    typealias GetErrorFn = @convention(c) () -> UnsafePointer<CChar>?

    let handle: UnsafeMutableRawPointer
    let initialize: InitFn
    let shutdown: QuitFn
    let createWindow: CreateWindowFn
    let destroyWindow: DestroyWindowFn
    let createRenderer: CreateRendererFn
    let destroyRenderer: DestroyRendererFn
    let setDrawColor: SetDrawColorFn
    let renderClear: RenderClearFn
    let renderPresent: RenderPresentFn
    let renderDrawLine: RenderDrawLineFn
    let pollEvent: PollEventFn
    let getMouseState: GetMouseStateFn
    let getModState: GetModStateFn
    let getTicks: GetTicksFn
    let delay: DelayFn
    let getError: GetErrorFn

    init?() {
        let candidates = [
            "/opt/homebrew/lib/libSDL2.dylib",
            "/usr/local/lib/libSDL2.dylib",
            "/Library/Frameworks/SDL2.framework/SDL2",
            "libSDL2-2.0.0.dylib",
            "libSDL2.dylib",
        ]
        var loaded: UnsafeMutableRawPointer?
        for path in candidates {
            loaded = dlopen(path, RTLD_NOW | RTLD_LOCAL)
            if loaded != nil { break }
        }
        guard let handle = loaded else { return nil }

        func load<T>(_ symbol: String, as type: T.Type) -> T? {
            guard let raw = dlsym(handle, symbol) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }

        guard
            let initialize = load("SDL_Init", as: InitFn.self),
            let shutdown = load("SDL_Quit", as: QuitFn.self),
            let createWindow = load("SDL_CreateWindow", as: CreateWindowFn.self),
            let destroyWindow = load("SDL_DestroyWindow", as: DestroyWindowFn.self),
            let createRenderer = load("SDL_CreateRenderer", as: CreateRendererFn.self),
            let destroyRenderer = load("SDL_DestroyRenderer", as: DestroyRendererFn.self),
            let setDrawColor = load("SDL_SetRenderDrawColor", as: SetDrawColorFn.self),
            let renderClear = load("SDL_RenderClear", as: RenderClearFn.self),
            let renderPresent = load("SDL_RenderPresent", as: RenderPresentFn.self),
            let renderDrawLine = load("SDL_RenderDrawLine", as: RenderDrawLineFn.self),
            let pollEvent = load("SDL_PollEvent", as: PollEventFn.self),
            let getMouseState = load("SDL_GetMouseState", as: GetMouseStateFn.self),
            let getModState = load("SDL_GetModState", as: GetModStateFn.self),
            let getTicks = load("SDL_GetTicks", as: GetTicksFn.self),
            let delay = load("SDL_Delay", as: DelayFn.self),
            let getError = load("SDL_GetError", as: GetErrorFn.self)
        else {
            dlclose(handle)
            return nil
        }

        self.handle = handle
        self.initialize = initialize
        self.shutdown = shutdown
        self.createWindow = createWindow
        self.destroyWindow = destroyWindow
        self.createRenderer = createRenderer
        self.destroyRenderer = destroyRenderer
        self.setDrawColor = setDrawColor
        self.renderClear = renderClear
        self.renderPresent = renderPresent
        self.renderDrawLine = renderDrawLine
        self.pollEvent = pollEvent
        self.getMouseState = getMouseState
        self.getModState = getModState
        self.getTicks = getTicks
        self.delay = delay
        self.getError = getError
    }

    deinit {
        dlclose(handle)
    }

    func errorMessage() -> String {
        guard let raw = getError() else { return "unknown SDL error" }
        return String(cString: raw)
    }
}

private final class SDLInputCollector {
    private var previousButtons: Set<InputState.Button> = []
    private var previousMousePos: CGPoint?

    private func inputButton(fromSDL buttonCode: UInt8) -> InputState.Button? {
        switch buttonCode {
        case sdlButtonLeftCode: return .left
        case sdlButtonRightCode: return .right
        case sdlButtonMiddleCode: return .middle
        default: return nil
        }
    }

    func poll(api: SDL2API) -> (InputState, Bool) {
        var input = InputState()
        var shouldQuit = false
        var eventMouseDown: Set<InputState.Button> = []
        var eventMouseUp: Set<InputState.Button> = []

        var eventStorage = [UInt8](repeating: 0, count: 64)
        while eventStorage.withUnsafeMutableBytes({ api.pollEvent($0.baseAddress) }) == 1 {
            let type = eventStorage.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
            }
            switch type {
            case sdlQuitEvent:
                shouldQuit = true
            case sdlKeyDownEvent:
                let repeatFlag = eventStorage.withUnsafeBytes { raw in
                    raw.loadUnaligned(fromByteOffset: 13, as: UInt8.self)
                }
                if repeatFlag == 0 {
                    let scan = eventStorage.withUnsafeBytes { raw in
                        raw.loadUnaligned(fromByteOffset: 16, as: Int32.self)
                    }
                    if scan >= 0, scan <= Int32(UInt16.max) {
                        input.keysDown.insert(UInt16(scan))
                    }
                }
            case sdlMouseMotionEvent:
                let x = eventStorage.withUnsafeBytes { raw in
                    raw.loadUnaligned(fromByteOffset: 20, as: Int32.self)
                }
                let y = eventStorage.withUnsafeBytes { raw in
                    raw.loadUnaligned(fromByteOffset: 24, as: Int32.self)
                }
                input.mousePos = CGPoint(x: CGFloat(x), y: CGFloat(y))
                input.mouseMoved = true
            case sdlMouseButtonDownEvent, sdlMouseButtonUpEvent:
                let buttonCode = eventStorage.withUnsafeBytes { raw in
                    raw.loadUnaligned(fromByteOffset: 16, as: UInt8.self)
                }
                if let button = inputButton(fromSDL: buttonCode) {
                    if type == sdlMouseButtonDownEvent {
                        eventMouseDown.insert(button)
                    } else {
                        eventMouseUp.insert(button)
                    }
                }
                let x = eventStorage.withUnsafeBytes { raw in
                    raw.loadUnaligned(fromByteOffset: 20, as: Int32.self)
                }
                let y = eventStorage.withUnsafeBytes { raw in
                    raw.loadUnaligned(fromByteOffset: 24, as: Int32.self)
                }
                input.mousePos = CGPoint(x: CGFloat(x), y: CGFloat(y))
            case sdlMouseWheelEvent:
                let wheelY = eventStorage.withUnsafeBytes { raw in
                    raw.loadUnaligned(fromByteOffset: 20, as: Int32.self)
                }
                input.wheel += CGFloat(wheelY)
            default:
                break
            }
        }

        var mx: Int32 = 0
        var my: Int32 = 0
        let buttonMask = api.getMouseState(&mx, &my)
        let currentMousePos = CGPoint(x: CGFloat(mx), y: CGFloat(my))
        input.mousePos = currentMousePos
        input.mouseMoved = input.mouseMoved || previousMousePos != currentMousePos
        previousMousePos = currentMousePos

        var currentButtons = Set<InputState.Button>()
        if (buttonMask & sdlButtonLeftMask) != 0 { currentButtons.insert(.left) }
        if (buttonMask & sdlButtonRightMask) != 0 { currentButtons.insert(.right) }
        if (buttonMask & sdlButtonMiddleMask) != 0 { currentButtons.insert(.middle) }

        input.buttons = currentButtons
        input.mouseDown = currentButtons.subtracting(previousButtons).union(eventMouseDown)
        input.mouseUp = previousButtons.subtracting(currentButtons).union(eventMouseUp)
        previousButtons = currentButtons

        let mods = api.getModState()
        input.modifiers = InputState.Modifiers(
            shift: (mods & kmodShift) != 0,
            control: (mods & kmodControl) != 0,
            option: (mods & kmodOption) != 0,
            command: (mods & kmodCommand) != 0
        )
        input.timestamp = Date().timeIntervalSinceReferenceDate
        return (input, shouldQuit)
    }

    func heldState(from input: InputState) -> InputState {
        var held = InputState()
        held.mousePos = input.mousePos
        held.buttons = input.buttons
        held.modifiers = input.modifiers
        held.timestamp = input.timestamp
        return held
    }
}

private final class SDLGameCore {
    private enum Shape {
        case box(halfWidth: Float, halfHeight: Float)
        case circle(radius: Float)
    }

    private struct BodyRecord {
        var id: b2BodyId
        var shape: Shape
        var isDynamic: Bool
    }

    private let worldId: b2WorldId
    private let canvasSize: CGSize
    private let pixelsPerMeter: CGFloat = 60
    private let groundYWorld: CGFloat

    private var records: [BodyRecord] = []
    private var grabbedBody: b2BodyId = b2_nullBodyId
    private var dragOffset = CGVector.zero
    private var previousGrabWorldPoint: CGPoint?

    init(canvasSize: CGSize) {
        self.canvasSize = canvasSize
        self.groundYWorld = (canvasSize.height - 80) / pixelsPerMeter

        var worldDef = b2DefaultWorldDef()
        worldDef.gravity = b2Vec2(x: 0, y: 15.0)
        worldId = b2CreateWorld(&worldDef)

        makeBounds()
        spawnDefaultSet()
    }

    deinit {
        if b2World_IsValid(worldId) {
            b2DestroyWorld(worldId)
        }
    }

    func update(dt: Double, input: InputState, camera: Camera2D) {
        applyInput(input: input, dt: dt, camera: camera)
        b2World_Step(worldId, Float(dt), 6)
    }

    func makeSnapshot() -> DrawSnapshot {
        let bg = DrawSnapshot.ColorValue(r: 0.03, g: 0.03, b: 0.035, a: 1)
        let accent = DrawSnapshot.ColorValue.white
        let groundFill = DrawSnapshot.ColorValue(r: 0.12, g: 0.13, b: 0.15, a: 0.85)

        var primitives: [DrawSnapshot.Primitive] = []
        let worldWidth = canvasSize.width / pixelsPerMeter
        let worldHeight = canvasSize.height / pixelsPerMeter
        primitives.append(
            .rect(
                .init(
                    rect: CGRect(
                        x: -2,
                        y: groundYWorld,
                        width: worldWidth + 4,
                        height: max(0.01, worldHeight - groundYWorld + 2)
                    ),
                    cornerRadius: 0,
                    fill: groundFill,
                    stroke: nil
                )
            )
        )
        primitives.append(
            .line(
                .init(
                    points: [CGPoint(x: -2, y: groundYWorld), CGPoint(x: worldWidth + 2, y: groundYWorld)],
                    stroke: .init(color: accent, width: 2)
                )
            )
        )

        for record in records where b2Body_IsValid(record.id) {
            let position = b2Body_GetPosition(record.id)
            let center = CGPoint(x: CGFloat(position.x), y: CGFloat(position.y))
            let rotation = b2Body_GetRotation(record.id)

            switch record.shape {
            case .circle(let radius):
                let strokeColor: DrawSnapshot.ColorValue = (record.id.index1 == grabbedBody.index1 && record.id.generation == grabbedBody.generation)
                    ? DrawSnapshot.ColorValue(r: 0.22, g: 0.72, b: 1.0, a: 1)
                    : accent
                primitives.append(
                    .circle(
                        .init(
                            center: center,
                            radius: CGFloat(radius),
                            fill: DrawSnapshot.ColorValue(r: 1, g: 1, b: 1, a: 0.05),
                            stroke: .init(color: strokeColor, width: 2)
                        )
                    )
                )
            case .box(let halfWidth, let halfHeight):
                let local = [
                    CGPoint(x: -CGFloat(halfWidth), y: -CGFloat(halfHeight)),
                    CGPoint(x: CGFloat(halfWidth), y: -CGFloat(halfHeight)),
                    CGPoint(x: CGFloat(halfWidth), y: CGFloat(halfHeight)),
                    CGPoint(x: -CGFloat(halfWidth), y: CGFloat(halfHeight)),
                ]
                let world = local.map { localPoint in
                    rotated(localPoint, rot: rotation, center: center)
                }
                let strokeColor: DrawSnapshot.ColorValue = (record.id.index1 == grabbedBody.index1 && record.id.generation == grabbedBody.generation)
                    ? DrawSnapshot.ColorValue(r: 0.22, g: 0.72, b: 1.0, a: 1)
                    : accent
                primitives.append(
                    .polygon(
                        .init(
                            points: world,
                            fill: DrawSnapshot.ColorValue(r: 1, g: 1, b: 1, a: 0.05),
                            stroke: .init(color: strokeColor, width: 2)
                        )
                    )
                )
            }
        }

        return DrawSnapshot(background: bg, primitives: primitives)
    }

    private func makeBounds() {
        let wallThickness: Float = 0.35
        let floorHeight: Float = 0.45
        let worldWidth = Float(canvasSize.width / pixelsPerMeter)
        let worldHeight = Float(canvasSize.height / pixelsPerMeter)
        let floorY = Float(groundYWorld) + floorHeight

        _ = createStaticBox(center: b2Vec2(x: worldWidth * 0.5, y: floorY), halfW: worldWidth * 0.55, halfH: floorHeight)
        _ = createStaticBox(center: b2Vec2(x: -wallThickness, y: worldHeight * 0.5), halfW: wallThickness, halfH: worldHeight * 0.7)
        _ = createStaticBox(center: b2Vec2(x: worldWidth + wallThickness, y: worldHeight * 0.5), halfW: wallThickness, halfH: worldHeight * 0.7)
    }

    private func spawnDefaultSet() {
        let baseY = Float(groundYWorld - 2.0)
        for i in 0..<5 {
            let x = Float(4 + i) * 1.3
            _ = spawnBox(at: b2Vec2(x: x, y: baseY - Float(i) * 0.08), halfW: 0.45, halfH: 0.45)
        }
        for i in 0..<3 {
            let x = Float(10 + i) * 1.1
            _ = spawnCircle(at: b2Vec2(x: x, y: baseY - 0.3), radius: 0.48)
        }
    }

    private func applyInput(input: InputState, dt: Double, camera: Camera2D) {
        if input.keysDown.contains(scanQ), let pos = input.mousePos {
            _ = spawnBox(at: worldVec(from: pos, camera: camera), halfW: 0.45, halfH: 0.45)
        }
        if input.keysDown.contains(scanW), let pos = input.mousePos {
            _ = spawnCircle(at: worldVec(from: pos, camera: camera), radius: 0.48)
        }
        if input.keysDown.contains(scanC) {
            resetDynamicBodies()
        }

        if let mousePos = input.mousePos {
            let mouseWorld = camera.screenToWorld(mousePos)

            if input.mouseDown.contains(.left) {
                if let body = dynamicBody(at: mouseWorld) {
                    grabbedBody = body
                    let p = b2Body_GetPosition(body)
                    let center = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
                    dragOffset = CGVector(dx: center.x - mouseWorld.x, dy: center.y - mouseWorld.y)
                    previousGrabWorldPoint = center
                }
            }

            if input.mouseDown.contains(.right), let body = dynamicBody(at: mouseWorld) {
                destroyBody(body)
            }

            if !b2Body_IsValid(grabbedBody) {
                grabbedBody = b2_nullBodyId
            }

            if b2Body_IsValid(grabbedBody), input.buttons.contains(.left) {
                let target = CGPoint(x: mouseWorld.x + dragOffset.dx, y: mouseWorld.y + dragOffset.dy)
                let current = b2Body_GetPosition(grabbedBody)
                let deltaX = Float(target.x) - current.x
                let deltaY = Float(target.y) - current.y
                let gain: Float = 18
                b2Body_SetLinearVelocity(grabbedBody, b2Vec2(x: deltaX * gain, y: deltaY * gain))
                b2Body_SetAngularVelocity(grabbedBody, 0)
                previousGrabWorldPoint = target
            }

            if input.mouseUp.contains(.left), b2Body_IsValid(grabbedBody) {
                if let previousGrabWorldPoint, dt > 0 {
                    let mouseTarget = CGPoint(x: mouseWorld.x + dragOffset.dx, y: mouseWorld.y + dragOffset.dy)
                    let vx = Float((mouseTarget.x - previousGrabWorldPoint.x) / dt)
                    let vy = Float((mouseTarget.y - previousGrabWorldPoint.y) / dt)
                    b2Body_SetLinearVelocity(grabbedBody, b2Vec2(x: vx, y: vy))
                }
                grabbedBody = b2_nullBodyId
                previousGrabWorldPoint = nil
            }
        }
    }

    private func dynamicBody(at point: CGPoint) -> b2BodyId? {
        for record in records.reversed() where record.isDynamic && b2Body_IsValid(record.id) {
            if contains(record: record, worldPoint: point) {
                return record.id
            }
        }
        return nil
    }

    private func contains(record: BodyRecord, worldPoint: CGPoint) -> Bool {
        let bodyPos = b2Body_GetPosition(record.id)
        let dx = Float(worldPoint.x) - bodyPos.x
        let dy = Float(worldPoint.y) - bodyPos.y
        let rot = b2Body_GetRotation(record.id)

        switch record.shape {
        case .circle(let radius):
            let distanceSq = dx * dx + dy * dy
            return distanceSq <= radius * radius
        case .box(let halfWidth, let halfHeight):
            let localX = rot.c * dx + rot.s * dy
            let localY = -rot.s * dx + rot.c * dy
            return abs(localX) <= halfWidth && abs(localY) <= halfHeight
        }
    }

    @discardableResult
    private func spawnBox(at worldPoint: b2Vec2, halfW: Float, halfH: Float) -> b2BodyId {
        var bodyDef = b2DefaultBodyDef()
        bodyDef.type = b2_dynamicBody
        bodyDef.position = worldPoint
        let bodyId = b2CreateBody(worldId, &bodyDef)
        guard b2Body_IsValid(bodyId) else { return b2_nullBodyId }

        var shapeDef = b2DefaultShapeDef()
        shapeDef.density = 1.0
        shapeDef.material.friction = 0.78
        shapeDef.material.restitution = 0.06
        var poly = b2MakeBox(halfW, halfH)
        let shapeId = b2CreatePolygonShape(bodyId, &shapeDef, &poly)
        guard b2Shape_IsValid(shapeId) else {
            b2DestroyBody(bodyId)
            return b2_nullBodyId
        }

        records.append(.init(id: bodyId, shape: .box(halfWidth: halfW, halfHeight: halfH), isDynamic: true))
        return bodyId
    }

    @discardableResult
    private func spawnCircle(at worldPoint: b2Vec2, radius: Float) -> b2BodyId {
        var bodyDef = b2DefaultBodyDef()
        bodyDef.type = b2_dynamicBody
        bodyDef.position = worldPoint
        let bodyId = b2CreateBody(worldId, &bodyDef)
        guard b2Body_IsValid(bodyId) else { return b2_nullBodyId }

        var shapeDef = b2DefaultShapeDef()
        shapeDef.density = 1.0
        shapeDef.material.friction = 0.22
        shapeDef.material.restitution = 0.08
        var circle = b2Circle()
        circle.center = b2Vec2(x: 0, y: 0)
        circle.radius = radius
        let shapeId = b2CreateCircleShape(bodyId, &shapeDef, &circle)
        guard b2Shape_IsValid(shapeId) else {
            b2DestroyBody(bodyId)
            return b2_nullBodyId
        }

        records.append(.init(id: bodyId, shape: .circle(radius: radius), isDynamic: true))
        return bodyId
    }

    @discardableResult
    private func createStaticBox(center: b2Vec2, halfW: Float, halfH: Float) -> b2BodyId {
        var bodyDef = b2DefaultBodyDef()
        bodyDef.type = b2_staticBody
        bodyDef.position = center
        let bodyId = b2CreateBody(worldId, &bodyDef)
        guard b2Body_IsValid(bodyId) else { return b2_nullBodyId }

        var shapeDef = b2DefaultShapeDef()
        shapeDef.density = 0
        shapeDef.material.friction = 0.7
        var poly = b2MakeBox(halfW, halfH)
        let shapeId = b2CreatePolygonShape(bodyId, &shapeDef, &poly)
        guard b2Shape_IsValid(shapeId) else {
            b2DestroyBody(bodyId)
            return b2_nullBodyId
        }

        records.append(.init(id: bodyId, shape: .box(halfWidth: halfW, halfHeight: halfH), isDynamic: false))
        return bodyId
    }

    private func resetDynamicBodies() {
        let dynamicIDs = records.filter(\.isDynamic).map(\.id)
        for id in dynamicIDs where b2Body_IsValid(id) {
            b2DestroyBody(id)
        }
        records.removeAll(where: \.isDynamic)
        grabbedBody = b2_nullBodyId
        previousGrabWorldPoint = nil
        spawnDefaultSet()
    }

    private func destroyBody(_ bodyId: b2BodyId) {
        guard b2Body_IsValid(bodyId) else { return }
        b2DestroyBody(bodyId)
        records.removeAll { $0.id.index1 == bodyId.index1 && $0.id.generation == bodyId.generation }
        if grabbedBody.index1 == bodyId.index1, grabbedBody.generation == bodyId.generation {
            grabbedBody = b2_nullBodyId
            previousGrabWorldPoint = nil
        }
    }

    private func worldVec(from screen: CGPoint, camera: Camera2D) -> b2Vec2 {
        let point = camera.screenToWorld(screen)
        return b2Vec2(x: Float(point.x), y: Float(point.y))
    }

    private func rotated(_ local: CGPoint, rot: b2Rot, center: CGPoint) -> CGPoint {
        let x = CGFloat(rot.c) * local.x - CGFloat(rot.s) * local.y
        let y = CGFloat(rot.s) * local.x + CGFloat(rot.c) * local.y
        return CGPoint(x: center.x + x, y: center.y + y)
    }
}

private struct SDLSnapshotRenderer {
    let api: SDL2API
    let renderer: UnsafeMutableRawPointer

    func render(_ snapshot: DrawSnapshot, camera: Camera2D) {
        setColor(snapshot.background)
        _ = api.renderClear(renderer)

        for primitive in snapshot.primitives {
            switch primitive {
            case .line(let line):
                drawPolyline(points: line.points, stroke: line.stroke, camera: camera)
            case .rect(let rect):
                let worldPoints = [
                    CGPoint(x: rect.rect.minX, y: rect.rect.minY),
                    CGPoint(x: rect.rect.maxX, y: rect.rect.minY),
                    CGPoint(x: rect.rect.maxX, y: rect.rect.maxY),
                    CGPoint(x: rect.rect.minX, y: rect.rect.maxY),
                ]
                let points = worldPoints.map(camera.worldToScreen)
                if let fill = rect.fill {
                    fillPolygon(points: points, color: fill)
                }
                if let stroke = rect.stroke {
                    drawPolygon(points: points, stroke: stroke)
                }
            case .polygon(let polygon):
                let points = polygon.points.map(camera.worldToScreen)
                if let fill = polygon.fill {
                    fillPolygon(points: points, color: fill)
                }
                if let stroke = polygon.stroke {
                    drawPolygon(points: points, stroke: stroke)
                }
            case .circle(let circle):
                let center = camera.worldToScreen(circle.center)
                let radius = circle.radius * camera.scale
                if let fill = circle.fill {
                    fillCircle(center: center, radius: radius, color: fill)
                }
                if let stroke = circle.stroke {
                    drawCircle(center: center, radius: radius, stroke: stroke)
                }
            case .text:
                continue
            }
        }

        api.renderPresent(renderer)
    }

    private func drawPolyline(points: [CGPoint], stroke: DrawSnapshot.Stroke, camera: Camera2D) {
        guard points.count >= 2 else { return }
        setColor(stroke.color)
        let thickness = max(1, Int(round(stroke.width)))
        for i in 1..<points.count {
            drawThickLine(
                camera.worldToScreen(points[i - 1]),
                camera.worldToScreen(points[i]),
                thickness: thickness
            )
        }
    }

    private func drawPolygon(points: [CGPoint], stroke: DrawSnapshot.Stroke) {
        guard points.count >= 2 else { return }
        setColor(stroke.color)
        let thickness = max(1, Int(round(stroke.width)))
        for i in 0..<points.count {
            let next = (i + 1) % points.count
            drawThickLine(points[i], points[next], thickness: thickness)
        }
    }

    private func drawCircle(center: CGPoint, radius: CGFloat, stroke: DrawSnapshot.Stroke) {
        let circumference = max(1, 2 * .pi * radius)
        let segments = min(128, max(16, Int(circumference / 6)))
        guard segments > 2 else { return }
        setColor(stroke.color)
        let thickness = max(1, Int(round(stroke.width)))
        var points: [CGPoint] = []
        points.reserveCapacity(segments)
        for i in 0..<segments {
            let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
            points.append(
                CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
            )
        }
        for i in 0..<segments {
            let next = (i + 1) % segments
            drawThickLine(points[i], points[next], thickness: thickness)
        }
    }

    private func fillPolygon(points: [CGPoint], color: DrawSnapshot.ColorValue) {
        guard points.count >= 3 else { return }
        setColor(color)

        let minY = Int(floor(points.map(\.y).min() ?? 0))
        let maxY = Int(ceil(points.map(\.y).max() ?? 0))
        if minY > maxY { return }

        for y in minY...maxY {
            let scanY = CGFloat(y) + 0.5
            var intersections: [CGFloat] = []
            intersections.reserveCapacity(points.count)

            for i in 0..<points.count {
                let a = points[i]
                let b = points[(i + 1) % points.count]
                let crosses = (a.y <= scanY && b.y > scanY) || (b.y <= scanY && a.y > scanY)
                guard crosses else { continue }
                let t = (scanY - a.y) / (b.y - a.y)
                intersections.append(a.x + t * (b.x - a.x))
            }

            intersections.sort()
            var idx = 0
            while idx + 1 < intersections.count {
                let x1 = intersections[idx]
                let x2 = intersections[idx + 1]
                drawLine(CGPoint(x: x1, y: scanY), CGPoint(x: x2, y: scanY))
                idx += 2
            }
        }
    }

    private func fillCircle(center: CGPoint, radius: CGFloat, color: DrawSnapshot.ColorValue) {
        guard radius > 0.5 else { return }
        setColor(color)
        let r = Int(ceil(radius))
        for y in -r...r {
            let yy = CGFloat(y)
            let inside = radius * radius - yy * yy
            guard inside >= 0 else { continue }
            let dx = sqrt(inside)
            let py = center.y + yy
            drawLine(
                CGPoint(x: center.x - dx, y: py),
                CGPoint(x: center.x + dx, y: py)
            )
        }
    }

    private func drawThickLine(_ a: CGPoint, _ b: CGPoint, thickness: Int) {
        if thickness <= 1 {
            drawLine(a, b)
            return
        }

        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.0001 else {
            drawLine(a, b)
            return
        }

        let nx = -dy / len
        let ny = dx / len
        let half = CGFloat(thickness - 1) * 0.5
        for i in 0..<thickness {
            let offset = CGFloat(i) - half
            let ox = nx * offset
            let oy = ny * offset
            drawLine(
                CGPoint(x: a.x + ox, y: a.y + oy),
                CGPoint(x: b.x + ox, y: b.y + oy)
            )
        }
    }

    private func drawLine(_ a: CGPoint, _ b: CGPoint) {
        _ = api.renderDrawLine(
            renderer,
            Int32(a.x.rounded()),
            Int32(a.y.rounded()),
            Int32(b.x.rounded()),
            Int32(b.y.rounded())
        )
    }

    private func setColor(_ color: DrawSnapshot.ColorValue) {
        _ = api.setDrawColor(
            renderer,
            UInt8(max(0, min(255, Int((color.r * 255).rounded())))),
            UInt8(max(0, min(255, Int((color.g * 255).rounded())))),
            UInt8(max(0, min(255, Int((color.b * 255).rounded())))),
            UInt8(max(0, min(255, Int((color.a * 255).rounded()))))
        )
    }
}

@main
enum SlopSandboxSDLApp {
    static func main() {
        guard let sdl = SDL2API() else {
            fputs("SDL2 not found. Install SDL2 and retry.\n", stderr)
            Foundation.exit(1)
        }

        guard sdl.initialize(sdlInitVideo) == 0 else {
            fputs("SDL_Init failed: \(sdl.errorMessage())\n", stderr)
            Foundation.exit(1)
        }
        defer { sdl.shutdown() }

        let width: Int32 = 1280
        let height: Int32 = 720
        let window = "SlopSandbox SDL".withCString { title in
            sdl.createWindow(title, 100, 80, width, height, sdlWindowShown)
        }
        guard let window else {
            fputs("SDL_CreateWindow failed: \(sdl.errorMessage())\n", stderr)
            Foundation.exit(1)
        }
        defer { sdl.destroyWindow(window) }

        let renderer = sdl.createRenderer(window, -1, sdlRendererAccelerated | sdlRendererPresentVSync)
        guard let renderer else {
            fputs("SDL_CreateRenderer failed: \(sdl.errorMessage())\n", stderr)
            Foundation.exit(1)
        }
        defer { sdl.destroyRenderer(renderer) }

        let game = SDLGameCore(canvasSize: CGSize(width: Int(width), height: Int(height)))
        let snapshotRenderer = SDLSnapshotRenderer(api: sdl, renderer: renderer)
        let inputCollector = SDLInputCollector()
        let viewport = CGSize(width: Int(width), height: Int(height))
        var camera = Camera2D(
            center: CGPoint(x: viewport.width / 120.0, y: viewport.height / 120.0),
            zoom: 1.0,
            viewport: viewport,
            pixelsPerMeter: 60.0
        )
        var lastPanMousePos: CGPoint?

        let fixedStep = 1.0 / 60.0
        var accumulator: Double = 0
        var lastTick = sdl.getTicks()
        var running = true

        while running {
            let currentTick = sdl.getTicks()
            let deltaTicks = currentTick &- lastTick
            lastTick = currentTick
            let frameDelta = min(0.05, Double(deltaTicks) / 1000.0)
            accumulator += frameDelta

            let (input, shouldQuit) = inputCollector.poll(api: sdl)
            if shouldQuit || input.keysDown.contains(scanEscape) {
                running = false
            }
            if let mouse = input.mousePos {
                if input.buttons.contains(.middle) {
                    if let last = lastPanMousePos {
                        camera.panByScreenDelta(CGVector(dx: mouse.x - last.x, dy: mouse.y - last.y))
                    }
                    lastPanMousePos = mouse
                } else {
                    lastPanMousePos = nil
                }
                camera.zoomByWheel(input.wheel, anchorScreen: mouse)
            } else {
                lastPanMousePos = nil
            }

            var stepInput = input
            while accumulator >= fixedStep {
                game.update(dt: fixedStep, input: stepInput, camera: camera)
                stepInput = inputCollector.heldState(from: input)
                accumulator -= fixedStep
            }

            let snapshot = game.makeSnapshot()
            snapshotRenderer.render(snapshot, camera: camera)
            sdl.delay(1)
        }
    }
}
