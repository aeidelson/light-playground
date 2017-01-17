import Foundation
import CoreGraphics

protocol Accumulator {
    init(simulationSize: CGSize, tracers: [Tracer])

    // Clear the accumulator state. Called when the simulation layout changes.
    func reset()

    var imageObservable: Observable<CGImage> { get }
}

class CPUAccumulator: Accumulator {
    required init(simulationSize: CGSize, tracers: [Tracer]) {
        grid = LightGrid(size: simulationSize)

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
        grid.reset()
    }

    var imageObservable = Observable<CGImage>()

    // MARK: Private

    private let grid: LightGrid
    private var totalSegmentCount: Int = 0

    /// Will be called on background queue.
    private func handleNewSegments(_ segments: [LightSegment]) {
        print("Got new segments")

        totalSegmentCount += segments.count

        var image: CGImage?

        print ("Drawing some segments")

        grid.drawSegments(segments: segments)
        let exposure = CGFloat(0.5) // TODO: Move to constant

        print ("Rendering image")
        image = grid.renderImage(brightness: calculateBrightness(segmentCount: totalSegmentCount, exposure: exposure))

        if let imageUnwrapped = image {
            print("Sending out accumulated image")
            imageObservable.notify(imageUnwrapped)
        }
    }

    /// The queue to accumulate on.
    private let accumulatorQueue = DispatchQueue(label: "accumulator_queue")
}

private func calculateBrightness(segmentCount: Int, exposure: CGFloat)  -> CGFloat {
    return CGFloat(exp(1 + 10 * exposure)) / CGFloat(segmentCount)
}
