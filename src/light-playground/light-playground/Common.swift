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

    var latest: T? {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        return latestInternal
    }

    public func subscribe(onQueue: DispatchQueue, callback: @escaping (T) -> Void) -> String {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        let token = NewToken()
        subsribers[token] = (onQueue, callback)
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

        for subscriber in subsribers.values {
            let onQueue = subscriber.0
            let block = subscriber.1

            onQueue.async {
                block(value)
            }
        }
    }

    // MARK: Private

    private var latestInternal: T?
    private var subsribers: [Token: (DispatchQueue, (T) -> Void)] = [:]
}
