import Metal
import CoreGraphics

/// An implementation of LightGrid which draws primarily using Metal.

final class MetalLightGrid: LightGrid {
    public init(
        context: LightSimulatorContext,
        size: CGSize,
        initialRenderProperties: RenderImageProperties
    ) {
        self.context = context
        self.metalContext = context.metalContext!
        self.width = Int(size.width.rounded())
        self.height = Int(size.height.rounded())
        self.renderProperties = initialRenderProperties


        // Make the textures used for storing the image state.

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false)

        textureDescriptor.storageMode = .shared

        self.rMetalTextureOld = metalContext.device.makeTexture(descriptor: textureDescriptor)!
        self.rMetalTextureCurrent = metalContext.device.makeTexture(descriptor: textureDescriptor)!
        self.gMetalTextureOld = metalContext.device.makeTexture(descriptor: textureDescriptor)!
        self.gMetalTextureCurrent = metalContext.device.makeTexture(descriptor: textureDescriptor)!
        self.bMetalTextureOld = metalContext.device.makeTexture(descriptor: textureDescriptor)!
        self.bMetalTextureCurrent = metalContext.device.makeTexture(descriptor: textureDescriptor)!
    }


    // MARK: LightGrid
    
    public func reset() {
        // Wipe each of the "current" textures.
        let emptyBytes = [Float](repeatElement(0, count: height * width))

        rMetalTextureCurrent.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: emptyBytes,
            bytesPerRow: MemoryLayout<Float32>.size * width)
        gMetalTextureCurrent.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: emptyBytes,
            bytesPerRow: MemoryLayout<Float32>.size * width)
        bMetalTextureCurrent.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: emptyBytes,
            bytesPerRow: MemoryLayout<Float32>.size * width)

        // Reset any variables we need to.
        totalSegmentCount = 0

        // Send out an updated image.
        updateImage()
    }

    public func drawSegments(layout: SimulationLayout, segments: [LightSegment], lowQuality: Bool) {
        // Swap the old and current textures so we can re-use the previous texture as the source.
        swap(&rMetalTextureOld, &rMetalTextureCurrent)
        swap(&gMetalTextureOld, &gMetalTextureCurrent)
        swap(&bMetalTextureOld, &bMetalTextureCurrent)

        // Before drawing the new segments, texture's brightness is reduced using a compute kernel.

        // How much to multiply the old texture by before drawing the new segments on top.
        let baseImageBrightness: Float32 =
            Float32(totalSegmentCount) / Float(totalSegmentCount + UInt64(segments.count))

        let preprocessParameters: [Float32] = [baseImageBrightness]
        let preprocessParametersBuffer = metalContext.device.makeBuffer(
            bytes: preprocessParameters,
            length: MemoryLayout<Float32>.size * preprocessParameters.count,
            options: [])

        let preprocessCommandBuffer = metalContext.commandQueue.makeCommandBuffer()!
        let preprocessEncoder = preprocessCommandBuffer.makeComputeCommandEncoder()!
        preprocessEncoder.setComputePipelineState(metalContext.imagePreprocessingPipelineState)
        preprocessEncoder.setBuffer(preprocessParametersBuffer, offset: 0, index: 0)
        preprocessEncoder.setTexture(rMetalTextureOld, index: 0)
        preprocessEncoder.setTexture(rMetalTextureCurrent, index: 1)
        preprocessEncoder.setTexture(gMetalTextureOld, index: 2)
        preprocessEncoder.setTexture(gMetalTextureCurrent, index: 3)
        preprocessEncoder.setTexture(bMetalTextureOld, index: 4)
        preprocessEncoder.setTexture(bMetalTextureCurrent, index: 5)

        // TODO: Figure out what these dimensions should actually be.
        let threadExecutionWidth =
            metalContext.imagePreprocessingPipelineState.threadExecutionWidth
        let maxTotalThreadsPerThreadgroup =
            metalContext.imagePreprocessingPipelineState.maxTotalThreadsPerThreadgroup
        let threadsPerThreadGroup = MTLSizeMake(
            threadExecutionWidth,
            maxTotalThreadsPerThreadgroup / threadExecutionWidth,
            1)
        let threadgroupsPerGrid = MTLSizeMake(
            (width + threadsPerThreadGroup.width - 1) / threadsPerThreadGroup.width,
            (height + threadsPerThreadGroup.height - 1) / threadsPerThreadGroup.height,
            1)
        preprocessEncoder.dispatchThreadgroups(
            threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        preprocessEncoder.endEncoding()
        preprocessCommandBuffer.commit()

        // After the preprocessing, draw the segments in a render pass.

        let renderCommandBuffer = metalContext.commandQueue.makeCommandBuffer()!
        let renderPassDescriptor = MTLRenderPassDescriptor()

        renderPassDescriptor.colorAttachments[0].texture = rMetalTextureCurrent
        renderPassDescriptor.colorAttachments[0].loadAction = .load
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[1].texture = gMetalTextureCurrent
        renderPassDescriptor.colorAttachments[1].loadAction = .load
        renderPassDescriptor.colorAttachments[1].storeAction = .store
        renderPassDescriptor.colorAttachments[2].texture = bMetalTextureCurrent
        renderPassDescriptor.colorAttachments[2].loadAction = .load
        renderPassDescriptor.colorAttachments[2].storeAction = .store

        let renderEncoder = renderCommandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(metalContext.renderPipelineState)
        // The y-axis is flipped to match our own coord system.
        renderEncoder.setViewport(MTLViewport(
            originX: 0,
            originY: Double(height),
            width: Double(width),
            height: -Double(height),
            znear: 0,
            zfar: 1
        ))

        // Create the vertex and color inputs to the render pass.
        let numOfVerts = segments.count * 2
        var positions = [Float32](repeatElement(0.0, count: numOfVerts * 4))
        var colors = [Float32](repeatElement(0.0, count: numOfVerts * 4))

        let newSegmentBrightness = 1 / Float(UInt64(segments.count) + totalSegmentCount)

        var i = 0
        while i < segments.count {
            let segment = segments[i]

            // The brightness is adjusted so diagonal lines are as heavily weighted as horizontal ones.
            var dx = abs(Float(segment.pos2.x) - Float(segment.pos1.x))
            var dy = abs(Float(segment.pos2.y) - Float(segment.pos1.y))
            // TODO: Figure out if this swapping is necessary?
            if dy > dx {
                swap(&dx, &dy)
            }
            // Save ourselves a lot of trouble by avoiding zero-values.
            if abs(dx) < 0.01 {
                dx = 0.01
            }
            let updatedBrightness = abs(sqrtf(dx*dx + dy*dy) / dx) * newSegmentBrightness

            // The position and color arrays are populated
            var vertexIndex = i * 2 * 4

            let p1 = gridToMetalCoord(segment.pos1)
            let p2 = gridToMetalCoord(segment.pos2)

            // First vert
            // TODO: Move the float calculating to the LightColor to avoid re-calculating these values.
            positions[vertexIndex + 0] = Float(p1.x)
            positions[vertexIndex + 1] = Float(p1.y)
            positions[vertexIndex + 2] = 0
            positions[vertexIndex + 3] = 1
            colors[vertexIndex + 0] = Float(segment.color.r) / Float(UInt8.max) * updatedBrightness
            colors[vertexIndex + 1] = Float(segment.color.g) / Float(UInt8.max) * updatedBrightness
            colors[vertexIndex + 2] = Float(segment.color.b) / Float(UInt8.max) * updatedBrightness
            colors[vertexIndex + 3] = 0

            // Seccond vert
            vertexIndex += 4
            positions[vertexIndex + 0] = Float(p2.x)
            positions[vertexIndex + 1] = Float(p2.y)
            positions[vertexIndex + 2] = 0
            positions[vertexIndex + 3] = 1
            colors[vertexIndex + 0] = Float(segment.color.r) / Float(UInt8.max) * updatedBrightness
            colors[vertexIndex + 1] = Float(segment.color.g) / Float(UInt8.max) * updatedBrightness
            colors[vertexIndex + 2] = Float(segment.color.b) / Float(UInt8.max) * updatedBrightness
            colors[vertexIndex + 3] = 0

            i += 1
        }

        // Set the values on the encoder and do do the drawing.
        let positionBuffer = metalContext.device.makeBuffer(
            bytes: positions,
            length: positions.count * MemoryLayout<Float>.size,
            options: [])

        let colorBuffer = metalContext.device.makeBuffer(
            bytes: colors,
            length: colors.count * MemoryLayout<Float32>.size,
            options: [])

        renderEncoder.setVertexBuffer(positionBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)

        renderEncoder.drawPrimitives(
            type: .line,
            vertexStart: 0,
            vertexCount: numOfVerts,
            instanceCount: 1)

        renderEncoder.endEncoding()

        renderCommandBuffer.commit()

        renderCommandBuffer.waitUntilCompleted()

        // Record the new segment count and update the image.
        totalSegmentCount += UInt64(segments.count)
        updateImage()
    }

    // Converts from our to the Metal coordinate space.
    private func gridToMetalCoord(_ pos: CGPoint) -> (x: Float, y: Float) {
        let metalDim = Float(2)
        let metalOrigin = metalDim / 2

        return (
            x: (Float(pos.x) / Float(width)) * metalDim - metalOrigin,
            y: (Float(pos.y) / Float(height)) * metalDim - metalOrigin
        )
        
    }


    public var renderProperties: RenderImageProperties {
        didSet {
            updateImage()
        }
    }

    public var snapshotHandler: (SimulationSnapshot) -> Void = { _ in }

    // MARK: Private

    private func updateImage() {
        // Read each texture
        var redTextureReadBuffer = [Float32](repeatElement(0, count: width * height))
        rMetalTextureCurrent.getBytes(
            &redTextureReadBuffer,
            bytesPerRow: MemoryLayout<Float32>.size * width,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0)

        var greenTextureReadBuffer = [Float32](repeatElement(0, count: width * height))
        gMetalTextureCurrent.getBytes(
            &greenTextureReadBuffer,
            bytesPerRow: MemoryLayout<Float32>.size * width,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0)

        var blueTextureReadBuffer = [Float32](repeatElement(0, count: width * height))
        bMetalTextureCurrent.getBytes(
            &blueTextureReadBuffer,
            bytesPerRow: MemoryLayout<Float32>.size * width,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0)

        // Write the textures to the corresponding image channel on the rendered image.
        let exposure = Float(renderProperties.exposure)
        let bufferSize = width * height * 4
        let imagePixelBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        var i = 0
        while i < width * height {
            let redValue = UInt8(Float(UInt8.max) * min(redTextureReadBuffer[i] * exposure, 1.0))
            let greenValue = UInt8(Float(UInt8.max) * min(greenTextureReadBuffer[i] * exposure, 1.0))
            let blueValue = UInt8(Float(UInt8.max) * min(blueTextureReadBuffer[i] * exposure, 1.0))

            let imageIndex = i * 4
            imagePixelBuffer[imageIndex + 0] = redValue
            imagePixelBuffer[imageIndex + 1] = greenValue
            imagePixelBuffer[imageIndex + 2] = blueValue

            i += 1
        }

        let imageDataProvider = CGDataProvider(
            data: NSData(
                bytesNoCopy: UnsafeMutableRawPointer(imagePixelBuffer),
                length: bufferSize,
                freeWhenDone: true))

        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 4 * 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            // Alpha is ignored.
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: imageDataProvider!,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent)

        if let imageUnwrapped = image {
            snapshotHandler(SimulationSnapshot(image: imageUnwrapped, totalLightSegmentsTraced: totalSegmentCount))
        }
    }

    private let width: Int
    private let height: Int
    private var totalSegmentCount = UInt64(0)

    private let context: LightSimulatorContext
    private let metalContext: MetalContext

    // MARK: Metal textures

    /// We use one texture per channel, to allow for more bits per channel. There are also two textures maintained
    /// per channel since Metal doesn't apparently allow reading and writing to the same texture on iOS.

    private var rMetalTextureOld: MTLTexture
    private var rMetalTextureCurrent: MTLTexture

    private var gMetalTextureOld: MTLTexture
    private var gMetalTextureCurrent: MTLTexture

    private var bMetalTextureOld: MTLTexture
    private var bMetalTextureCurrent: MTLTexture
}
