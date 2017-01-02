import UIKit

class MainViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup the draw layer
        drawLayer.isOpaque = true
        // It seems this need to come from the screen since it isn't necessarily inherited from view correctly:
        //   http://stackoverflow.com/questions/9479001/uiviews-contentscalefactor-depends-on-implementing-drawrect
        drawLayer.contentsScale = UIScreen.main.scale
        interactionView.layer.insertSublayer(drawLayer, at: 0)

        // Set up the drawlayer render loop
        let displayLink = CADisplayLink(target: self, selector: #selector(updateDrawLayer))
        displayLink.add(to: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        displayLink.preferredFramesPerSecond = 60
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews();
        drawLayer.frame = interactionView.bounds

        // The simulator relies on the layout bounds, so it only makes sense to start the simulator
        // after it has been laid out.
        resetSimulator()

    }


    func updateDrawLayer() {
        let snapshot = simulator.latestSnapshot
        drawLayer.contents = snapshot.image
    }

    // MARK: Private
    private let drawLayer = CALayer()

    // MARK: Handle user interaction

    @IBOutlet weak var interactionView: UIView!
    @IBOutlet weak var interactionModeControl: UISegmentedControl!

    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) {
        if case .light = currentInteractionMode {
            lights.append(Light(pos: sender.location(in: interactionView)))
            resetSimulator()
            print("Add light!")
        }
    }

    @IBAction func panGesture(_ sender: UIPanGestureRecognizer) {
        if case .wall = currentInteractionMode, case .ended = sender.state {

            resetSimulator()
            print("Add wall!")
        }
    }

    private enum InteractionMode {
        case light
        case wall
    }

    private var currentInteractionMode: InteractionMode {
        switch interactionModeControl.selectedSegmentIndex {
        case 0:
            return .light
        case 1:
            return .wall
        default:
            preconditionFailure()
        }
    }

    // MARK: Maintain simulation state

    /// Should be called any time the state of input to the simulator changes.
    private func resetSimulator() {
        simulator.startWithLayout(layout: SimulationLayout(
            maxRayCount: 1000,
            pixelDimensions: (
                w: Int(drawLayer.frame.size.width * drawLayer.contentsScale),
                h: Int(drawLayer.frame.size.height * drawLayer.contentsScale)),
            lights: lights,
            walls: walls))
    }

    private var lights = [Light]()
    private var walls = [Wall]()
    private let simulator: LightSimulator = CPULightSimulator()
}

