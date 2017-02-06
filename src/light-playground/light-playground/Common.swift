import Foundation
import CoreGraphics

/// This file contains helpers used across the codebase.

public struct Light {
    let pos: CGPoint
    let color: LightColor
}

/// A common object that can be used in the declaration of shapes with volume.
public struct VolumeAttributes {
    public let indexOfRefraction: CGFloat
}

/// A common object that can be used in the declaration of the surface of shapes.
public struct SurfaceAttributes {
    /// Percentage of the light to absorb (rather than reflect). A value of zero will result in no absorption.
    let absorption: CGFloat

    /// A value from 0 to 1 indicating how much to deviate from the angle of reflection.
    let diffusion: CGFloat
}

public struct Wall {
    let pos1, pos2: CGPoint

    let surfaceAttributes: SurfaceAttributes
}

public struct CircleShape {
    let pos: CGPoint
    let radius: CGFloat

    let surfaceAttributes: SurfaceAttributes
    let volumeAttributes: VolumeAttributes
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

public typealias Token = String

func NewToken() -> Token {
    return UUID().uuidString
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

func dotProduct(_ v1: CGVector, _ v2: CGVector) -> CGFloat {
    return v1.dx * v2.dx + v1.dy * v2.dy
}

func magnitude(_ v: CGVector) -> CGFloat {
    return sqrt(pow(v.dx, 2) + pow(v.dy, 2))
}

func normalize(_ v: CGVector) -> CGVector {
    let m = magnitude(v)
    return CGVector(
        dx: v.dx / m,
        dy: v.dy / m)
}

/// Returns the angle between two vectors (in radians).
func angle(_ v1: CGVector, _ v2: CGVector) -> CGFloat {
    return acos(dotProduct(v1, v2) / (magnitude(v1) * magnitude(v2)))
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
