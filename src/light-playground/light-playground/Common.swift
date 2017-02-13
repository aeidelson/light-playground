import Foundation
import CoreGraphics

/// This file contains helpers used across the codebase.

public struct Light {
    let pos: CGPoint
    let color: LightColor
}

/// A common object that can be used in the declaration of shapes.
public struct ShapeAttributes {

    public init(
        absorption: FractionalLightColor = FractionalLightColor.zero,
        diffusion: CGFloat = 0,
        indexOfRefraction: CGFloat = 0,
        translucent: Bool = false
    ) {
        self.absorption = absorption
        self.diffusion = diffusion
        self.indexOfRefraction = indexOfRefraction
        self.translucent = translucent
    }

    /// Percentage of the light to absorb per color. A value of zero will result in no absorption.
    public let absorption: FractionalLightColor

    /// A value from 0 to 1 indicating how much to deviate from the angle of reflection.
    public let diffusion: CGFloat

    public let indexOfRefraction: CGFloat

    /// Shapes with no volume (like walls) can't be translucent (the tracer doesn't handle this case gracefully yet).
    public let translucent: Bool
}

public struct Wall {
    public init(
        pos1: CGPoint,
        pos2: CGPoint,
        shapeAttributes: ShapeAttributes
    ) {
        self.pos1 = pos1
        self.pos2 = pos2
        self.shapeAttributes = shapeAttributes

        // Do some of the calculations needed for ray tracing, ahead of time:
        self.slope = safeDivide((pos2.y - pos1.y), (pos2.x - pos1.x))
        self.yIntercept = pos1.y - slope * pos1.x
        self.xRange = (min(pos1.x, pos2.x)-0.5)...(max(pos1.x, pos2.x)+0.5)
        self.yRange = (min(pos1.y, pos2.y)-0.5)...(max(pos1.y, pos2.y)+0.5)

        let dx = pos2.x - pos1.x
        let dy = pos2.y - pos1.y
        self.normals = (
            CGVector(dx: -dy, dy: dx),
            CGVector(dx: dy, dy: -dx))
    }

    let pos1, pos2: CGPoint
    let shapeAttributes: ShapeAttributes

    /// Some precalculated variables to save re-calculating when tracing.
    let slope: CGFloat
    let yIntercept: CGFloat
    let xRange: ClosedRange<CGFloat>
    let yRange: ClosedRange<CGFloat>
    let normals: (CGVector, CGVector)
}

public struct CircleShape {
    let pos: CGPoint
    let radius: CGFloat

    let shapeAttributes: ShapeAttributes
}

public struct SimulationLayout {
    public let exposure: CGFloat
    public let lights: [Light]
    public let walls: [Wall]
    public let circleShapes: [CircleShape]
}

public struct LightColor {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    /// Multiplies each component by the value, safe-guarding against overflow issues.
    func multiplyBy(_ x: CGFloat) -> LightColor {
        let newR = CGFloat(r) * x
        let newG = CGFloat(g) * x
        let newB = CGFloat(b) * x

        return LightColor(
            r: UInt8(min(max(newR, 0), 255)),
            g: UInt8(min(max(newG, 0), 255)),
            b: UInt8(min(max(newB, 0), 255))
        )
    }

    /// Multiplies by a fractional light color. Skips any safe-guarding since the FractionalLightColor is guarenteed
    /// to be [0, 1] for each color.
    func multiplyBy(_ x: FractionalLightColor) -> LightColor {
        return LightColor(
            r: UInt8(CGFloat(r) * x.r),
            g: UInt8(CGFloat(g) * x.g),
            b: UInt8(CGFloat(b) * x.b)
        )
    }
}

public struct FractionalLightColor {
    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        precondition(r >= 0 && r <= 1.0)
        precondition(g >= 0 && g <= 1.0)
        precondition(b >= 0 && b <= 1.0)

        self.r = r
        self.g = g
        self.b = b
    }

    /// Returns a new FractionalLightColor with whatever is left per-color.
    public func remainder() -> FractionalLightColor {
        return FractionalLightColor(
            r: 1 - self.r,
            g: 1 - self.g,
            b: 1 - self.b)
    }

    public let r: CGFloat
    public let g: CGFloat
    public let b: CGFloat

    public static let zero = FractionalLightColor(r: 0, g: 0, b: 0)
    public static let total = FractionalLightColor(r: 1, g: 1, b: 1)
}

public struct LightSegment {
    public let p0: CGPoint
    public let p1: CGPoint
    public let color: LightColor
}

extension CGVector {
    /// Creates a new vector, rotated 180.
    public func reverse() -> CGVector {
        return CGVector(
            dx: -dx,
            dy: -dy)
    }
}

func serialOperationQueue() -> OperationQueue {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
}

func concurrentOperationQueue(_ maxConcurrentOperations: Int) -> OperationQueue {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = maxConcurrentOperations
    return queue
}

func safeDivide(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let c = a / b
    if c.isInfinite {
        return 9999999
    }
    return c
}

func safeDividef(_ a: Float, _ b: Float) -> Float {
    let c = a / b
    if c.isInfinite {
        return 9999999
    }
    return c
}

func measure(_ label: String, block: () -> Void) {
    let start = Date()

    block()

    let end = Date()

    simLog("Time to execute \(label): \(end.timeIntervalSince(start) * 1000) ms")
}

struct MeasureTime {
    public init(_ message: String) {
        self.start = Date()
        self.message = message
    }

    public func record() {
        simLog("Time to execute \(message): \(Date().timeIntervalSince(start) * 1000) ms")
    }

    private let start: Date
    private let message: String
}

/// Used to aggregate different calls to the same block of code.
/// Doesn't handle async at all, should always be used from the same thread.
class AggregateMeasureTime {
    public init(_ message: String) {
        self.message = message
        self.totalMs = 0
        self.measureCount = 0
    }

    public func start() {
        startTime = Date()
    }

    public func stop() {
        guard let startTime = startTime else { preconditionFailure() }
        measureCount += 1
        totalMs += UInt64((Date().timeIntervalSince(startTime) * 1000).rounded())
    }

    public func complete() {
        simLog("Time to execute \(message): avg: \(Double(totalMs) / Double(measureCount)) count: \(measureCount)")
    }

    private let message: String
    private var startTime: Date?
    private var totalMs: UInt64
    private var measureCount: UInt64
}

func simLog(_ label: String) {
    Swift.print("\(Date().timeIntervalSince1970): \(label)")
}

func dotProduct(_ v1: CGVector, _ v2: CGVector) -> CGFloat {
    return v1.dx * v2.dx + v1.dy * v2.dy
}

func magnitude(_ v: CGVector) -> CGFloat {
    return sqrt(sq(v.dx) + sq(v.dy))
}

/// Returns the angle of v2 relative to v1 (in radians).
func angle(_ v1: CGVector, _ v2: CGVector) -> CGFloat {
    return atan2(v2.dy, v2.dx) - atan2(v1.dy, v1.dx)
}

func absoluteAngle(_ v: CGVector) -> CGFloat{
    return atan2(v.dx, v.dy)
}

func rotate(_ v: CGVector, _ angle: CGFloat) -> CGVector {
    return CGVector(
        dx: v.dx * cos(angle) - v.dy * sin(angle),
        dy: v.dx * sin(angle) + v.dy * cos(angle)
    )
}

func advance(p: CGPoint, by v: CGFloat, towards direction: CGVector) -> CGPoint {
    let m = magnitude(direction)
    return CGPoint(
        x: p.x + (v * direction.dx / m),
        y: p.y + (v * direction.dy / m)
    )
}

func sq(_ x: CGFloat) -> CGFloat {
    return pow(x, 2)
}
