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
    public func subscribe(
        onQueue: OperationQueue,
        maxAsyncOperationCount: Int = 5,
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

        for subscriber in subsribers.values {
            let operation = BlockOperation {
                subscriber.block(value)
            }

            subscriber.onQueue.addOperations(
                [operation],
                // TODO: This may end up favoring short-lived operations too much?
                waitUntilFinished: subscriber.onQueue.operationCount > subscriber.maxAsyncOperationCount)
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

    Swift.print("Time to execute \(label): \(Date().timeIntervalSince(start) * 1000) ms")
}

/* TODO: Remove these if it turns out we actually don't need them.

/// Due to some memory issues with swift not deallocating the segment array when using NSOperations queues, we
/// manually manage memory for the array. We also include a seperate varable to record the actual number of segments
/// traced, since the array could be larger.
typealias LightSegmentTraceResult = (
    segmentsActuallyTraced: Int,
    array: UnsafeArrayWrapper<LightSegment>)



struct UnsafeArrayWrapper<T> {
    // An id uniquely identifying this array. Used for internal tracking.
    fileprivate let id: String

    public let count: Int
    public let ptr: UnsafeMutablePointer<T>
}

/// A thread-safe object for managing allocations and deallocations of a type.
/// Is useful for keeping large buffers around for when we need them again.
class UnsafeArrayManager<T> {
    init() { }

    func create(size: Int, fillWith: T) -> UnsafeArrayWrapper<T> {
        //print("Create size \(size)")

        objc_sync_enter(freeArrays)
        defer { objc_sync_exit(freeArrays) }

        if var arraysForSize = freeArrays[size], arraysForSize.count > 0 {
            let arrayToReturn = arraysForSize.removeLast()

            for i in 0..<arrayToReturn.count {
                arrayToReturn.ptr[i] = fillWith
            }

            inUseArrays[arrayToReturn.id] = arrayToReturn
            return arrayToReturn
        } else {
            let ptr = UnsafeMutablePointer<T>.allocate(capacity: size)
            ptr.initialize(to: fillWith, count: size)
            let arrayToReturn = UnsafeArrayWrapper<T>(
                id: UUID().uuidString,
                count: size,
                ptr: ptr)

            inUseArrays[arrayToReturn.id] = arrayToReturn
            return arrayToReturn
        }
    }

    func release(array: UnsafeArrayWrapper<T>) {
        //print("Release size \(array.count)")

        objc_sync_enter(freeArrays)
        defer { objc_sync_exit(freeArrays) }

        /* TODO: There seems to be some reuse problems, so for now we just deallocate arrays.
        if var arraysForSize = freeArrays[array.count] {
            arraysForSize.append(array)
        } else {
            freeArrays[array.count] = [array]
        }
         */

        inUseArrays.removeValue(forKey: array.id)
        array.ptr.deallocate(capacity: array.count)
    }

    /// Called when we want to free all arrays. Should only be called if we know they aren't in use anymore (i.e. after
    /// the simulation has been canceled and the operation queue drained).
    func releaseAll() {
        //print("Release all")

        objc_sync_enter(freeArrays)
        defer { objc_sync_exit(freeArrays) }

        for arrayToRelease in inUseArrays.values {
            /* TODO: There seems to be some reuse problems, so for now we just deallocate arrays.
            if var arraysForSize = freeArrays[arrayToRelease.count] {
                arraysForSize.append(arrayToRelease)
            } else {
                freeArrays[arrayToRelease.count] = [arrayToRelease]
            }
            */

            arrayToRelease.ptr.deallocate(capacity: arrayToRelease.count)
        }

        inUseArrays.removeAll()
    }

    // Used to track in-use arrays, in case we need to free them all. Keyed on the array's id.
    private var inUseArrays = [String: UnsafeArrayWrapper<T>]()

    private var freeArrays = [Int : [UnsafeArrayWrapper<T>]]()
}
*/
