import Foundation
import CoreGraphics

/// This file contains helpers used across the codebase.

public struct Light {
    let pos: CGPoint
}

public struct Wall {
    let pos1, pos2: CGPoint
}

public struct SimulationLayout {
    public let lights: [Light]
    public let walls: [Wall]
}

public struct LightColor {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8
    /// TODO: Does it make sense to also include intensity?
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
