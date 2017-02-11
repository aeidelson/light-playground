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
        absorption: CGFloat = 0,
        diffusion: CGFloat = 0,
        indexOfRefraction: CGFloat = 0,
        translucent: Bool = false
    ) {
        self.absorption = absorption
        self.diffusion = diffusion
        self.indexOfRefraction = indexOfRefraction
        self.translucent = translucent
    }

    /// Percentage of the light to absorb (rather than reflect). A value of zero will result in no absorption.
    public let absorption: CGFloat

    /// A value from 0 to 1 indicating how much to deviate from the angle of reflection.
    public let diffusion: CGFloat

    public let indexOfRefraction: CGFloat

    /// Shapes with no volume (like walls) can't be translucent (the tracer doesn't handle this case gracefully yet).
    public let translucent: Bool
}

public struct Wall {
    let pos1, pos2: CGPoint

    let shapeAttributes: ShapeAttributes
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
}

public struct LightSegment {
    public let p0: CGPoint
    public let p1: CGPoint
    public let color: LightColor
}

// A vector that is normalized on initialization.
struct NormalizedVector {
    public init(dx: CGFloat, dy: CGFloat) {
        let mag = sqrt(sq(dx) + sq(dy))

        self.dx = dx / mag
        self.dy = dy / mag
    }

    let dx: CGFloat
    let dy: CGFloat
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

func simLog(_ label: String) {
    Swift.print("\(Date().timeIntervalSince1970): \(label)")
}

func dotProduct(_ v1: NormalizedVector, _ v2: NormalizedVector) -> CGFloat {
    return v1.dx * v2.dx + v1.dy * v2.dy
}

func magnitude(_ v: NormalizedVector) -> CGFloat {
    return sqrt(sq(v.dx) + sq(v.dy))
}

func normalize(_ v: NormalizedVector) -> NormalizedVector {
    let m = magnitude(v)
    return NormalizedVector(
        dx: v.dx / m,
        dy: v.dy / m)
}

/// Returns the angle of v2 relative to v1 (in radians).
func angle(_ v1: NormalizedVector, _ v2: NormalizedVector) -> CGFloat {
    return atan2(v2.dy, v2.dx) - atan2(v1.dy, v1.dx)
}

func absoluteAngle(_ v: NormalizedVector) -> CGFloat{
    return atan2(v.dx, v.dy)
}

func rotate(_ v: NormalizedVector, _ angle: CGFloat) -> NormalizedVector {
    return NormalizedVector(
        dx: v.dx * cos(angle) - v.dy * sin(angle),
        dy: v.dx * sin(angle) + v.dy * cos(angle)
    )
}

func sq(_ x: CGFloat) -> CGFloat {
    return pow(x, 2)
}

/// This holds a reference to the pool object and provides an interface to get a weak reference.
class PoolObject<T: AnyObject> {
    fileprivate init(value: T, pool: ReusablePool<T>) {
        self.valueInternal = value
        self.pool = pool
    }

    deinit {
        precondition(valueInternal == nil, "release() must be called before the pool object is deallocated,")
    }

    public func release() {
        guard let unwrapedValue = valueInternal else { preconditionFailure() }
        pool?.add(unwrapedValue)
        valueInternal = nil
    }

    public weak var valueWeak: T? {
        return valueInternal

    }

    /// This will hold a strong reference until release is called.
    private var valueInternal: T?

    private weak var pool: ReusablePool<T>?
}

class ReusablePool<T: AnyObject> {
    init(producer: @escaping () -> T) {
        self.producer = producer
    }

    func borrow() -> PoolObject<T> {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        let value: T
        if freed.count > 0 {
            value = freed.removeLast()
        } else {
            value = producer()
        }
        return PoolObject(value: value, pool: self)
    }

    func add(_ v: T) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        freed.append(v)
    }

    private var freed = [T]()
    private let producer: () -> T
}
