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

/// Can be used to manage subscribers to a stream of data.
final public class Observable<T> {

    // TODO: This could deadlock if accessed from onQueue while `waitUntilAllOperationsAreFinished` is being called!
    var latest: T? {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        return latestInternal
    }

    public func subscribe(
        onQueue: OperationQueue,
        maxAsyncOperationCount: Int = 30,
        block: @escaping (T) -> Void
    ) -> String {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        let token = NewToken()
        subsribers[token] = (onQueue: onQueue, maxAsyncOperationCount: maxAsyncOperationCount, block: block)
        return token
    }

    public func unsubscribe(token: Token) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        subsribers.removeValue(forKey: token)
    }

    public func notify(_ value: T) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        latestInternal = value

        // TODO: This has the potential to starve a subscriber because another subscriber has too many operations.
        // Could we do better?
        for subscriber in subsribers.values {
            if subscriber.onQueue.operationCount > subscriber.maxAsyncOperationCount {
                subscriber.onQueue.waitUntilAllOperationsAreFinished()
            }

            subscriber.onQueue.addOperation {
                subscriber.block(value)
            }
        }
    }

    // MARK: Private

    private var latestInternal: T?
    private var subsribers: [Token: (
        onQueue: OperationQueue,
        maxAsyncOperationCount: Int,
        block: (T) -> Void)] = [:]
}

func serialOperationQueue() -> OperationQueue {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
}

func safeDivide(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let c = a / b
    if c.isInfinite {
        return 9999999
    }
    return c
}
