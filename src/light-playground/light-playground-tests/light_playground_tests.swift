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

    func testBenchmarkTrace() {
        let segments = 20_000

        let context = CPULightSimulatorContext()
        let size = CGSize(width: 1080, height: 1920)
        let rootGrid = LightGrid(context: context, generateImage: true, size: size)

        let layout = SimulationLayout(
            exposure: 0.55,
            lights: [Light(
                pos: CGPoint(x: 100, y: 100),
                color: LightColor(r: 255, g: 255, b: 255))],
            walls: [],
            circleShapes: [])

        self.measure {
            let tracer = Tracer.makeTracer(
                context: context,
                rootGrid: rootGrid,
                layout: layout,
                simulationSize: size,
                segmentsToTrace: segments,
                interactiveTrace: false)

            tracer.start()
            tracer.waitUntilFinished()
        }
    }

    func testBenchmarkDraw() {
        let segments = 10_000

        let context = CPULightSimulatorContext()
        let size = CGSize(width: 1080, height: 1920)
        let grid = LightGrid(context: context, generateImage: true, size: size)

        let layout = SimulationLayout(
            exposure: 0.55,
            lights: [],
            walls: [],
            circleShapes: [])


        var segmentArray: [LightSegment] = []
        for _ in 0...segments {
            let p0 = CGPoint(
                x: CGFloat(arc4random_uniform(UInt32(size.width)-1)),
                y: CGFloat(arc4random_uniform(UInt32(size.height)-1)))
            let p1 = CGPoint(
                x: CGFloat(arc4random_uniform(UInt32(size.width)-1)),
                y: CGFloat(arc4random_uniform(UInt32(size.height)-1)))
            segmentArray.append(LightSegment(
                p0: p0,
                p1: p1,
                color: LightColor(r: 255, g: 255, b: 255)))
        }

        self.measure {
            grid.drawSegments(layout: layout, segments: segmentArray, lowQuality: false)
        }
    }
}
