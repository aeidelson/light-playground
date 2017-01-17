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
            BresenhamLightGridSegmentDraw.drawSegment(
                gridWidth: width,
                gridHeight: height,
                data: &data,
                segment: segment)
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

        let bufferSize = totalPixels * componentsPerPixel
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

/// Returns the index of the pixel, and is a 0-based index.
private func indexFromLocation(_ gridWidth: Int, _ gridHeight: Int, _ x: Int, _ y: Int) -> Int {
    #if DEBUG
        precondition(x >= 0)
        precondition(x < gridWidth)
        precondition(y >= 0)
        precondition(y < gridHeight)
    #endif

    return y * gridWidth + x
}

/// A private class to contain all the nasty line drawing code.
/// Taken almost directly from:
/// https://github.com/ssloy/tinyrenderer/wiki/Lesson-1:-Bresenham%E2%80%99s-Line-Drawing-Algorithm
private class BresenhamLightGridSegmentDraw {
    static func drawSegment(
        gridWidth: Int,
        gridHeight: Int,
        data: inout [LightGridPixel],
        segment: LightSegment
    ) {
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
            let index = steep ?
                indexFromLocation(gridWidth, gridHeight, y, x) :
                indexFromLocation(gridWidth, gridHeight, x, y)
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

/// A private class to contain all the nasty line drawing code.
/// Taken almost directly from: http://rosettacode.org/wiki/Xiaolin_Wu%27s_line_algorithm#C
private class WuLightGridSegmentDraw {
    private static func plot(
        gridWidth: Int,
        gridHeight: Int,
        data: inout [LightGridPixel],
        x: Int,
        y: Int,
        color: LightColor,
        br: CGFloat
    ) {
        let index = indexFromLocation(gridWidth, gridHeight, x, y)
        data[index].r += UInt64(CGFloat(color.r) * br)
        data[index].g += UInt64(CGFloat(color.g) * br)
        data[index].b += UInt64(CGFloat(color.b) * br)
    }

    private static func ipart(_ x: CGFloat) -> Int {
        return Int(x)
    }

    private static func round(_ x: CGFloat) -> Int {
        return ipart(x + 0.5)
    }

    private static func fpart(_ x: CGFloat) -> CGFloat {
        if x < 0 {
            return 1 - (x - floor(x))
        }
        return x - floor(x)
    }

    private static func rfpart(_ x: CGFloat) -> CGFloat {
        return 1 - fpart(x)
    }

    static func drawSegment(
        gridWidth: Int,
        gridHeight: Int,
        data: inout [LightGridPixel],
        segment: LightSegment
    ) {
        var x0 = segment.p0.x
        var y0 = segment.p0.y
        var x1 = segment.p1.x
        var y1 = segment.p1.y

        let steep = abs(y1 - y0) > abs(x1 - x0)

        if steep {
            swap(&x0, &y0)
            swap(&x1, &y1)
        }

        if x0 > x1 {
            swap(&x0, &x1)
            swap(&y0, &y1)
        }

        // First endpoint
        let dx = x1 - x0
        let dy = y1 - y0
        let gradient = dy / dx // TODO: Safe divide?

        var xend = round(x0)
        var yend = y0 + gradient * (CGFloat(xend) - x0)
        var xgap = rfpart(x0 + 0.5)
        let xpxl1 = xend
        let ypxl1 = ipart(yend)

        if steep {
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: ypxl1,
                y: xpxl1,
                color: segment.color,
                br: rfpart(yend) * xgap)
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: ypxl1+1,
                y: xpxl1,
                color: segment.color,
                br: fpart(yend) * xgap)
        } else {
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: xpxl1,
                y: ypxl1,
                color: segment.color,
                br: rfpart(yend) * xgap)
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: xpxl1,
                y: ypxl1+1,
                color: segment.color,
                br: fpart(yend) * xgap)
        }

        var intery = yend + gradient

        // Second endpoint
        xend = round(x1)
        yend = y1 + gradient * (CGFloat(xend) - x1)
        xgap = fpart(x1 + 0.5)
        let xpxl2 = xend
        let ypxl2 = ipart(yend)

        if steep {
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: ypxl2,
                y: xpxl2,
                color: segment.color,
                br: rfpart(yend) * xgap)

            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: ypxl2+1,
                y: xpxl2,
                color: segment.color,
                br: fpart(yend) * xgap)
        } else {
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: xpxl2,
                y: ypxl2,
                color: segment.color,
                br: rfpart(yend) * xgap)
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: xpxl2,
                y: ypxl2+1,
                color: segment.color,
                br: fpart(yend) * xgap)
        }

        // Main loop
        if steep {
            for x in (xpxl1 + 1)...(xpxl2 - 1) {
                plot(
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    data: &data,
                    x: ipart(intery),
                    y: x,
                    color: segment.color,
                    br: rfpart(intery))
                plot(
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    data: &data,
                    x: ipart(intery)+1,
                    y: x,
                    color: segment.color,
                    br: fpart(intery))
                intery = intery + gradient
            }
        } else {
            for x in (xpxl1 + 1)...(xpxl2 - 1) {
                plot(
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    data: &data,
                    x: x,
                    y: ipart(intery),
                    color: segment.color,
                    br: rfpart(intery))
                plot(
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    data: &data,
                    x: x,
                    y: ipart(intery)+1,
                    color: segment.color,
                    br: fpart(intery))
                intery = intery + gradient
            }
        }
    }
}
