import Foundation
import CoreGraphics

// Encapsulates the accumulated light trace grid and provides related functions. Is thread-safe.
class LightGrid {
    public init(
        context: CPULightSimulatorContext,
        generateImage: Bool,
        size: CGSize
    ) {
        self.context = context
        self.width = Int(size.width.rounded())
        self.height = Int(size.height.rounded())
        self.totalPixels = width * height
        self.generateImage = generateImage
        self.data = Array<LightGridPixel>(repeating: LightGridPixel(r: 0, g: 0, b: 0), count: totalPixels)
    }

    public func reset() {
        for i in 0..<totalPixels {
            data[i].r = 0
            data[i].g = 0
            data[i].b = 0
        }
        totalSegmentCount = 0

        updateImage()
    }

    public func drawSegments(segments: [LightSegment], lowQuality: Bool) {
        if lowQuality {
            for segment in segments {
                BresenhamLightGridSegmentDraw.drawSegment(
                    gridWidth: width,
                    gridHeight: height,
                    data: &data,
                    segment: segment)
            }
        } else {
            for segment in segments {
                WuLightGridSegmentDraw.drawSegment(
                    gridWidth: width,
                    gridHeight: height,
                    data: &data,
                    segment: segment)
            }
        }

        totalSegmentCount += segments.count

        updateImage()
    }

    public func aggregrate(grids: [LightGrid]) {
        for grid in grids {
            precondition(grid.width == width)
            precondition(grid.height == height)

            for i in 0..<totalPixels {
                data[i].r += grid.data[i].r
                data[i].g += grid.data[i].g
                data[i].b += grid.data[i].b
            }
            totalSegmentCount += grid.totalSegmentCount
        }
        updateImage()
    }

    private func updateImage() {
        guard generateImage else { return }

        let exposure = Float(0.55) // TODO: Move to constant

        let brightness: Float
        if totalSegmentCount == 0 {
            brightness = 0
        } else {
            brightness = calculateBrightness(segmentCount: totalSegmentCount, exposure: exposure)
        }

        let bufferSize = totalPixels * componentsPerPixel
        let imagePixelBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

        for i in 0..<totalPixels {
            imagePixelBuffer[i * componentsPerPixel + 0] = UInt8(min(Float(data[i].r) * brightness, 255))
            imagePixelBuffer[i * componentsPerPixel + 1] = UInt8(min(Float(data[i].g) * brightness, 255))
            imagePixelBuffer[i * componentsPerPixel + 2] = UInt8(min(Float(data[i].b) * brightness, 255))
        }

        let imageDataProvider = CGDataProvider(
            data: NSData(
                bytesNoCopy: UnsafeMutableRawPointer(imagePixelBuffer),
                length: bufferSize,
                freeWhenDone: true))

        let bitsPerPixel = componentsPerPixel * bitsPerComponent

        let image = CGImage(
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

         if let imageUnwrapped = image {
            imageHandler(imageUnwrapped)
        }
    }

    public let width: Int
    public let height: Int

    public var imageHandler: (CGImage) -> Void = { _ in }

    // MARK: Fileprivate

    /// These are intended to be read when aggregrating grids.
    fileprivate let totalPixels: Int
    fileprivate var data: [LightGridPixel]
    fileprivate var totalSegmentCount = 0

    // MARK: Private

    private let generateImage: Bool

    private let context: CPULightSimulatorContext

    // MARK: Variables for generating images.

    private let componentsPerPixel = 4
    private let bitsPerComponent = 8
}

private func calculateBrightness(segmentCount: Int, exposure: Float)  -> Float {
    return Float(exp(1 + 10 * exposure)) / Float(segmentCount)
}

/// Represents a single pixel in the light grid.
fileprivate struct LightGridPixel {
    public var r: UInt32
    public var g: UInt32
    public var b: UInt32
}

/// Returns the index of the pixel, and is a 0-based index.
@inline(__always) private func indexFromLocation(_ gridWidth: Int, _ gridHeight: Int, _ x: Int, _ y: Int) -> Int {
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

        // Figure out the color for the segment.
        var dxFloat = abs(Float(segment.p1.x) - Float(segment.p0.x))
        var dyFloat = abs(Float(segment.p1.y) - Float(segment.p0.y))
        if dyFloat > dxFloat {
            swap(&dxFloat, &dyFloat)
        }

        let br = safeDividef(sqrtf(dxFloat*dxFloat + dyFloat*dyFloat), dxFloat)
        let colorR = UInt32(Float(segment.color.r) * br)
        let colorG = UInt32(Float(segment.color.g) * br)
        let colorB = UInt32(Float(segment.color.b) * br)

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
            data[index].r += colorR
            data[index].g += colorG
            data[index].b += colorB

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
    @inline(__always) private static func plot(
        gridWidth: Int,
        gridHeight: Int,
        data: inout [LightGridPixel],
        x: Int,
        y: Int,
        color: (Float, Float, Float),
        br: Float
    ) {
        let index = indexFromLocation(gridWidth, gridHeight, x, y)
        let initialPixel = data[index]

        data[index].r = initialPixel.r + UInt32(color.0 * br)
        data[index].g = initialPixel.g + UInt32(color.1 * br)
        data[index].b = initialPixel.b + UInt32(color.2 * br)
    }

    @inline(__always) private static func ipart(_ x: Float) -> Int {
        return Int(x)
    }

    @inline(__always) private static func round(_ x: Float) -> Int {
        return ipart(x + 0.5)
    }

    @inline(__always) private static func fpart(_ x: Float) -> Float {
        if x < 0 {
            return 1 - (x - floor(x))
        }
        return x - floor(x)
    }

    @inline(__always) private static func rfpart(_ x: Float) -> Float {
        return 1 - fpart(x)
    }

    // An optimization for cases where we want both the rfpart and the fpart.
    @inline(__always) private static func rffpart(_ x: Float) -> (rfpart: Float, fpart: Float) {
        let fp = fpart(x)
        return (
            rfpart: 1 - fp,
            fpart: fp
        )
    }

    static func drawSegment(
        gridWidth: Int,
        gridHeight: Int,
        data: inout [LightGridPixel],
        segment: LightSegment
    ) {
        var x0 = Float(segment.p0.x)
        var y0 = Float(segment.p0.y)
        var x1 = Float(segment.p1.x)
        var y1 = Float(segment.p1.y)

        // As an optimization, we convert the color to float once.
        let lightColorFloat = (Float(segment.color.r), Float(segment.color.g), Float(segment.color.b))


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
        let gradient = dy / dx

        let brCoeff = safeDividef(sqrtf(dx*dx + dy*dy), dx)


        var xend = round(x0)
        var yend = y0 + gradient * (Float(xend) - x0)
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
                color: lightColorFloat,
                br: rfpart(yend) * xgap * brCoeff)
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: ypxl1+1,
                y: xpxl1,
                color: lightColorFloat,
                br: fpart(yend) * xgap * brCoeff)
        } else {
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: xpxl1,
                y: ypxl1,
                color: lightColorFloat,
                br: rfpart(yend) * xgap * brCoeff)
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: xpxl1,
                y: ypxl1+1,
                color: lightColorFloat,
                br: fpart(yend) * xgap * brCoeff)
        }

        var intery = yend + gradient

        // Second endpoint
        xend = round(x1)
        yend = y1 + gradient * (Float(xend) - x1)
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
                color: lightColorFloat,
                br: rfpart(yend) * xgap * brCoeff)
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: ypxl2+1,
                y: xpxl2,
                color: lightColorFloat,
                br: fpart(yend) * xgap * brCoeff)
        } else {
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: xpxl2,
                y: ypxl2,
                color: lightColorFloat,
                br: rfpart(yend) * xgap * brCoeff)
            plot(
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                data: &data,
                x: xpxl2,
                y: ypxl2+1,
                color: lightColorFloat,
                br: fpart(yend) * xgap * brCoeff)
        }

        // Main loop. This is called a lot, so should be made as efficient as possible.

        if steep {
            // For efficiency, we use the a while loop rather than the normal swift range.
            var x = (xpxl1 + 1)
            while x <= (xpxl2 - 1) {
                let precalcIpart = ipart(intery)
                let parts = rffpart(intery)
                plot(
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    data: &data,
                    x: precalcIpart,
                    y: x,
                    color: lightColorFloat,
                    br: parts.rfpart * brCoeff)
                plot(
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    data: &data,
                    x: precalcIpart+1,
                    y: x,
                    color: lightColorFloat,
                    br: parts.fpart * brCoeff)
                intery = intery + gradient

                x += 1
            }
        } else {
            // For efficiency, we use the a while loop rather than the normal swift range.
            var x = (xpxl1 + 1)
            while x <= (xpxl2 - 1) {
                let precalcIpart = ipart(intery)
                let parts = rffpart(intery)
                plot(
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    data: &data,
                    x: x,
                    y: precalcIpart,
                    color: lightColorFloat,
                    br: parts.rfpart * brCoeff)
                plot(
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    data: &data,
                    x: x,
                    y: precalcIpart+1,
                    color: lightColorFloat,
                    br: parts.fpart * brCoeff)
                intery = intery + gradient

                x += 1
            }
        }
    }
}
