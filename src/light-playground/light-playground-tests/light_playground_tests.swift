import XCTest

class light_playground_tests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    // MARK: Variables used in benchmarks
    let benchmarkLayout = SimulationLayout(
        exposure: 0.55,
        lights: [Light(
            pos: CGPoint(x: 100, y: 100),
            color: LightColor(r: 255, g: 255, b: 255))],
        walls: [],
        circleShapes: [])

    let benchmarkSegmentCount = 20_000

    let benchmarkSize = CGSize(width: 1080, height: 1920)

    let benchmarkContext = CPULightSimulatorContext()

    // MARK: Benchmarks

    func testBenchmarkTraceAndDraw() {
        let rootGrid = LightGrid(context: benchmarkContext, generateImage: true, size: benchmarkSize)

        self.measure {
            let tracer = Tracer.makeTracer(
                context: self.benchmarkContext,
                rootGrid: rootGrid,
                layout: self.benchmarkLayout,
                simulationSize: self.benchmarkSize,
                segmentsToTrace: self.benchmarkSegmentCount,
                interactiveTrace: false)

            tracer.start()
            tracer.waitUntilFinished()
        }
    }

    func testBenchmarkTrace() {
        self.measure {
            _ = Tracer.trace(
                layout: self.benchmarkLayout,
                simulationSize: self.benchmarkSize,
                maxSegments: self.benchmarkSegmentCount)
        }
    }

    func testBenchmarkDraw() {
        let grid = LightGrid(context: benchmarkContext, generateImage: true, size: benchmarkSize)

        /// The scene is traced outside of measure, to create a representative trace.
        let segmentArray = Tracer.trace(
            layout: self.benchmarkLayout,
            simulationSize: self.benchmarkSize,
            maxSegments: self.benchmarkSegmentCount)

        self.measure {
            grid.drawSegments(layout: self.benchmarkLayout, segments: segmentArray, lowQuality: false)
        }
    }
}