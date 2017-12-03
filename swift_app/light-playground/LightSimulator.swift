import CoreGraphics
import Metal

/// A context object which instances used throughout the the simulator.
struct LightSimulatorContext {

    /// All information needed to render using metal.
    /// Will be nil if the device doesn't support metal.
    let metalContext: MetalContext?
}

struct MetalContext {
    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device

        guard let library = device.makeDefaultLibrary() else { return nil }

        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.commandQueue = commandQueue

        guard let imagePreprocessingPipelineState = try? device.makeComputePipelineState(
            function: library.makeFunction(name: "preprocessing_kernel")!) else { return nil }
        self.imagePreprocessingPipelineState = imagePreprocessingPipelineState

        // Create and configure the pipeline descriptor.
        renderPipelineDescriptor = MTLRenderPipelineDescriptor()

        /// Setup each render channel
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .r32Float
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one

        renderPipelineDescriptor.colorAttachments[1].pixelFormat = .r32Float
        renderPipelineDescriptor.colorAttachments[1].isBlendingEnabled = true
        renderPipelineDescriptor.colorAttachments[1].rgbBlendOperation = .add
        renderPipelineDescriptor.colorAttachments[1].sourceRGBBlendFactor = .one
        renderPipelineDescriptor.colorAttachments[1].destinationRGBBlendFactor = .one

        renderPipelineDescriptor.colorAttachments[2].pixelFormat = .r32Float
        renderPipelineDescriptor.colorAttachments[2].isBlendingEnabled = true
        renderPipelineDescriptor.colorAttachments[2].rgbBlendOperation = .add
        renderPipelineDescriptor.colorAttachments[2].sourceRGBBlendFactor = .one
        renderPipelineDescriptor.colorAttachments[2].destinationRGBBlendFactor = .one

        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_shader")
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_shader")

        guard let renderPipelineState = try? device.makeRenderPipelineState(descriptor: renderPipelineDescriptor) else {
            return nil }
        self.renderPipelineState = renderPipelineState
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderPipelineDescriptor: MTLRenderPipelineDescriptor
    let renderPipelineState: MTLRenderPipelineState
    let imagePreprocessingPipelineState: MTLComputePipelineState
}

public final class LightSimulator {
    public required init(
        simulationSize: CGSize,
        initialExposure: CGFloat
    ) {
        self.simulationSize = simulationSize
        self.context = LightSimulatorContext(metalContext: MetalContext())

        self.simulatorQueue = serialOperationQueue()
        self.simulatorQueue.qualityOfService = .userInteractive
        self.tracerQueue = concurrentOperationQueue(tracerQueueConcurrency)
        self.tracerQueue.qualityOfService = .userInitiated
        self.exposure = initialExposure

        // Metal is a lot faster, so we bump the trace size.
        if context.metalContext == nil {
            self.standardTracerSize = 20_000
        } else {
            self.standardTracerSize = 100_000
        }

        self.currentLayout = SimulationLayout(
            version: 0,
            lights: [],
            walls: [],
            circleShapes: [],
            polygonShapes: [])

        self.rootGrid = createLightGrid(
            logRenderType: true,
            context: context,
            simulationSize: simulationSize,
            renderImageProperties: RenderImageProperties(exposure: initialExposure))
        self.rootGrid.snapshotHandler = { [weak self] snapshot in
            guard let strongSelf = self else { return }
            strongSelf.snapshotHandler(snapshot)
        }
    }

    public func restartSimulation(layout: SimulationLayout, isInteractive: Bool) {
        precondition(Thread.isMainThread)

        // The simulation is restarted on a background thread so we don't hold up the UI.
        simulatorQueue.addOperation { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.currentLayout = layout

            /// Setup a new queue.
            strongSelf.tracerQueue.cancelAllOperations()
            strongSelf.tracerQueue = concurrentOperationQueue(strongSelf.tracerQueueConcurrency)
            strongSelf.tracerQueue.qualityOfService = .userInitiated

            // The render properties depend on the lights, which may have changed.
            // The LightGrid should only update the image if a significant value changes.
            strongSelf.rootGrid.renderProperties = strongSelf.currentRenderProperties()

            if layout.lights.isEmpty {
                strongSelf.resetLightGrid(updateImage: true)
                return
            } else {
                // Skip updating the image so the user doesn't see a blank grid.
                // It will be updated when the next trace completes.
                strongSelf.resetLightGrid(updateImage: false)
            }

            if isInteractive {
                strongSelf.enqueueInteractiveTracer()
            } else {
                strongSelf.finalTraceSegmentsLeft = strongSelf.finalMaxSegmentsToTrace
                strongSelf.enqueueFinalTracersIfNeeded()
            }
        }
    }

    public func stop() {

    }

    public var snapshotHandler: (SimulationSnapshot) -> Void = { _ in }

    public var exposure: CGFloat {
        didSet {
            let renderProperties = currentRenderProperties()
            objc_sync_enter(self.rootGrid)
            self.rootGrid.renderProperties = renderProperties
            objc_sync_exit(self.rootGrid)
        }
    }

    private let finalMaxSegmentsToTrace = 5_000_000

    // MARK: Private

    private func currentRenderProperties()  -> RenderImageProperties {
        return RenderImageProperties(
            exposure: exp(1 + 10 * exposure) * CGFloat(currentLayout.lights.count)
        )
    }

    private func resetLightGrid(updateImage: Bool) {
        objc_sync_enter(self.rootGrid)
        defer { objc_sync_exit(self.rootGrid) }

        self.rootGrid.reset(updateImage: updateImage)

    }

    private func enqueueInteractiveTracer() {
        let tracer = Tracer.makeTracer(
            context: context,
            rootGrid: rootGrid,
            layout: currentLayout,
            simulationSize: simulationSize,
            segmentsToTrace: interactiveMaxSegmentsToTrace,
            interactiveTrace: true)
        // The operation is assigned the highest QoS.
        tracer.qualityOfService = .userInteractive
        tracerQueue.addOperation(tracer)
    }

    private func enqueueFinalTracersIfNeeded() {
        for _ in 0..<max((tracerQueueConcurrency - tracerQueue.operationCount), 0) {
            // The first operation is special-cased as being interactive.
            let tracerSize = takeNextFinalSegmentCount()

            guard tracerSize > 0 else { return }

            // A grid for this tracer to accumulate on.
            var tracer: Operation?
            tracer = Tracer.makeTracer(
                context: context,
                rootGrid: rootGrid,
                layout: currentLayout,
                simulationSize: simulationSize,
                segmentsToTrace: tracerSize,
                interactiveTrace: false)

            // The operation is assigned a QoS slightly lower than the interactive tracer.
            tracer?.qualityOfService = .userInitiated

            tracer?.completionBlock = { [weak self] in
                guard let strongTracer = tracer else { return }
                guard !strongTracer.isCancelled else { return }

                self?.simulatorQueue.addOperation { [weak self] in
                    self?.enqueueFinalTracersIfNeeded()
                }
            }

            tracerQueue.addOperation(tracer!)
        }
    }

    private let interactiveMaxSegmentsToTrace = 200
    private let standardTracerSize: Int
    private var finalTraceSegmentsLeft = 0

    private var finalTracerCount = 0
    private func takeNextFinalSegmentCount() -> Int {
        finalTracerCount += 1
        let segmentCount = standardTracerSize
        let actualSegmentCount = min(segmentCount, finalTraceSegmentsLeft)

        finalTraceSegmentsLeft -= actualSegmentCount
        return actualSegmentCount

    }

    private let simulationSize: CGSize
    private let context: LightSimulatorContext
    /// The queue to use for any top-level simulator logic.
    private let simulatorQueue: OperationQueue
    /// The queue to run traces on
    private var tracerQueue: OperationQueue
    private let tracerQueueConcurrency = ProcessInfo.processInfo.activeProcessorCount
    /// The grid that everything aggregrated to.
    private let rootGrid: LightGrid
    private var currentLayout: SimulationLayout
}

private func createLightGrid(
    logRenderType: Bool,
    context: LightSimulatorContext,
    simulationSize: CGSize,
    renderImageProperties: RenderImageProperties
) -> LightGrid {
    if context.metalContext == nil {
        if logRenderType {
            print("Couldn't connect to Metal, drawing using CPU.")
        }
        return CPULightGrid(
            context: context,
            size: simulationSize,
            initialRenderProperties: renderImageProperties)
    } else {
        if logRenderType {
            print("Drawing using Metal!")
        }
        return MetalLightGrid(
            context: context,
            size: simulationSize,
            initialRenderProperties: renderImageProperties)
    }
}
