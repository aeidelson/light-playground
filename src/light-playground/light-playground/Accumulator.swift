import Foundation
import CoreGraphics

protocol Accumulator {
    // Clear the accumulator state. Called when the simulation layout changes.
    func reset()

    var imageObservable: Observable<CGImage> { get }
}

class CPUAccumulator: Accumulator {
    init(
        context: CPULightSimulatorContext,
        accumulatorQueue: OperationQueue,
        simulationSize: CGSize,
        tracers: [Tracer]
    ) {
        self.context = context
        self.accumulatorQueue = accumulatorQueue
        self.grid = LightGrid(context: context, size: simulationSize)

        for tracer in tracers {
            // TODO: Unsubscribe using the returned token, on deinit.
            _ = tracer.incrementalSegmentsObservable.subscribe(
                onQueue: accumulatorQueue
            ) { [weak self] segmentResult in
                guard let strongSelf = self else { return }

                print(accumulatorQueue.operationCount)

                strongSelf.handleNewSegments(segmentResult)

                strongSelf.context.lightSegmentArrayManager.release(array: segmentResult.array)

            }
        }
    }

    // Clear the accumulator state. Called when the simulation layout changes.
    func reset() {
        // Run on the operation queue to prevent races.
        accumulatorQueue.addOperation { [weak self] in
            // Note: The current queue will be flushed automatically in LightSimulator, since `traceQueue` is managed
            // automatically.
            self?.grid.reset()
            self?.totalSegmentCount = 0
        }

    }

    var imageObservable = Observable<CGImage>()

    // MARK: Private

    private let context: CPULightSimulatorContext
    private let grid: LightGrid
    private var totalSegmentCount: Int = 0

    /// Will be called on background queue.
    private func handleNewSegments(_ segmentResult: LightSegmentTraceResult) {

        totalSegmentCount += segmentResult.segmentsActuallyTraced

        var image: CGImage?

        //print ("Drawing some segments")

        grid.drawSegments(segmentResult: segmentResult)
        let exposure = CGFloat(0.55) // TODO: Move to constant

        //print ("Rendering image")
        image = grid.renderImage(brightness: calculateBrightness(segmentCount: totalSegmentCount, exposure: exposure))

        if let imageUnwrapped = image {
            //print("Sending out accumulated image")
            print("Total segments: \(totalSegmentCount)")
            imageObservable.notify(imageUnwrapped)
        }
    }

    /// The queue to accumulate on.
    private let accumulatorQueue: OperationQueue
}

private func calculateBrightness(segmentCount: Int, exposure: CGFloat)  -> CGFloat {
    return CGFloat(exp(1 + 10 * exposure)) / CGFloat(segmentCount)
}
