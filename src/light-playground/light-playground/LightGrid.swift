import Foundation
import CoreGraphics

// Encapsulates the accumulated light trace grid and provides related functions. Is thread-safe.
class LightGrid {
    public init(size: CGSize) {
        self.width = Int(size.width.rounded())
        self.height = Int(size.height.rounded())
        self.totalPixels = width * height
        self.data = Array(repeating: LightGridPixel(r: 0, g: 0, b: 0), count: totalPixels)
        //self.imagePixelBuffer = Array(repeating: 0, count: totalPixels * componentsPerPixel)
    }

    public func reset() {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        for i in 0..<totalPixels {
            data[i].r = 0
            data[i].g = 0
            data[i].b = 0
        }
    }

    public func drawSegments(segments: [LightSegment]) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        for segment in segments {
            // Taken almost directly from:
            // https://github.com/ssloy/tinyrenderer/wiki/Lesson-1:-Bresenham%E2%80%99s-Line-Drawing-Algorithm
            var steep = false
            var x0 = Int(segment.p0.x.rounded())
            var y0 = Int(segment.p0.y.rounded())
            var x1 = Int(segment.p1.x.rounded())
            var y1 = Int(segment.p1.y.rounded())

            if abs(x0 - x1) < abs(y0 - y1) {
                swap(&x0, &y0)
                swap(&x1, &y1)
                steep = true
            }
            if x0 > x1 {
                swap(&x0, &x1)
                swap(&y0, &y1)
            }
            let dx = x1 - x0
            let dy = y1 - y0
            let derror2 = abs(dy) * 2
            var error2 = 0
            var y = y0
            for x in x0...x1 {
                let index = steep ? indexFromLocation(y, x) : indexFromLocation(x, y)
                data[index].r += UInt64(segment.color.r)
                data[index].g += UInt64(segment.color.g)
                data[index].b += UInt64(segment.color.b)

                error2 += derror2
                if error2 > dx {
                    y += (y1 > y0 ? 1 : -1)
                    error2 -= dx * 2
                }
            }
        }
    }

    /// Adds the values of each pixel in each grid to this one.
    /// Crashes if they aren't all the same size.
    public func combine(grids: [LightGrid]) {
        for grid in grids {
            precondition(width == grid.width)
            precondition(height == grid.height)

            for i in 0..<totalPixels {
                data[i].r += grid.data[i].r
                data[i].g += grid.data[i].g
                data[i].b += grid.data[i].b
            }
        }
    }

    /// `brightness` is a constant to multiply times each pixel.
    public func renderImage(brightness: CGFloat) -> CGImage? {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        // Lazy-allocate the pixel buffer. This is done manually rather than using the `lazy` feature of swift because
        // that seems to make make memory access much slower.
        /*
        if imagePixelBuffer == nil {
            print("creating pixel buffer")
            let bufferSize = totalPixels * componentsPerPixel
            var buffer: [UInt8] = Array(repeating: 0, count: bufferSize)
            imagePixelBuffer = buffer
            imageDataProvider = CGDataProvider(data: NSData(bytes: &buffer, length: bufferSize))
        }
        guard var imagePixelBuffer = imagePixelBuffer else { preconditionFailure() }
 */

        let bufferSize = totalPixels * componentsPerPixel
        //var imagePixelBuffer: [UInt8] = Array(repeating: 0, count: bufferSize)

        let imagePixelBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

        for i in 0..<totalPixels {
            imagePixelBuffer[i * componentsPerPixel + 0] = UInt8(min(CGFloat(data[i].r) * brightness, 255))
            imagePixelBuffer[i * componentsPerPixel + 1] = UInt8(min(CGFloat(data[i].g) * brightness, 255))
            imagePixelBuffer[i * componentsPerPixel + 2] = UInt8(min(CGFloat(data[i].b) * brightness, 255))

        }

        let imageDataProvider = CGDataProvider(
            data: NSData(
                bytesNoCopy: UnsafeMutableRawPointer(imagePixelBuffer),
                length: bufferSize,
                freeWhenDone: true))

        //imageDataProvider = CGDataProvider(data: NSData(bytes: &imagePixelBuffer, length: totalPixels * componentsPerPixel))
        let bitsPerPixel = componentsPerPixel * bitsPerComponent

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: width * bitsPerPixel / 8,
            space: CGColorSpaceCreateDeviceRGB(),
            // Alpha is ignored.
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: imageDataProvider!,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent)
    }

    public let width: Int
    public let height: Int

    // MARK: File Private

    fileprivate let totalPixels: Int

    fileprivate var data: [LightGridPixel]

    // MARK: Private

    /// Returns the index of the pixel, and is a 0-based index.
    func indexFromLocation(_ x: Int, _ y: Int) -> Int {
        #if DEBUG
            precondition(x >= 0)
            precondition(x < width)
            precondition(y >= 0)
            precondition(y < height)
        #endif

        return y * width + x
    }

    // MARK: Variables for generating images.

    private let componentsPerPixel = 4
    private let bitsPerComponent = 8

    /// Only some grids will be used for actually generating images, lazy load the large pixel buffer.
    /// Lazy allocating is done manually since the lazy keyword in swift seems to severely slow things down.
    //private var imagePixelBuffer: [UInt8]?
    //private var imageDataProvider: CGDataProvider?
}

/// Represents a single pixel in the light grid.
fileprivate struct LightGridPixel {
    public var r: UInt64
    public var g: UInt64
    public var b: UInt64
}
