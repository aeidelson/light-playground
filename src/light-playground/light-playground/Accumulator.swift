import Foundation
import CoreGraphics

protocol Accumulator {
    // Clear the accumulator state. Called when the simulation layout changes.
    func reset()

    var imageObservable: Observable<CGImage> { get }
}

class CPUAccumulator: Accumulator {
    required init(accumulatorQueue: OperationQueue, simulationSize: CGSize, tracers: [Tracer]) {
        self.accumulatorQueue = accumulatorQueue
        self.grid = LightGrid(size: simulationSize)

        for tracer in tracers {
            // TODO: Unsubscribe using the returned token, on deinit.
            _ = tracer.incrementalSegmentsObservable.subscribe(
                onQueue: accumulatorQueue
            ) { [weak self] segments in
                guard let strongSelf = self else { return }

                strongSelf.handleNewSegments(segments)
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

    private let grid: LightGrid
    private var totalSegmentCount: Int = 0

    /// Will be called on background queue.
    private func handleNewSegments(_ segments: [LightSegment]) {
        //print("Got new segments")

        totalSegmentCount += segments.count

        var image: CGImage?

        //print ("Drawing some segments")

        grid.drawSegments(segments: segments)
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
