import UIKit

class MainViewController: UIViewController, CALayerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup the draw layer
        drawLayer.delegate = self
        drawLayer.isOpaque = true

        // It seems this needs to come from the screen since it isn't necessarily inherited from view correctly:
        //   http://stackoverflow.com/questions/9479001/uiviews-contentscalefactor-depends-on-implementing-drawrect
        drawLayer.contentsScale = UIScreen.main.scale
        interactionView.layer.insertSublayer(drawLayer, at: 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews();
        drawLayer.frame = interactionView.bounds

        // The simulator relies on the layout bounds, so it only makes sense to start the simulator
        // after it has been laid out.
        simulator = CPULightSimulator(simulationSize: CGSize(
            width: drawLayer.frame.size.width * drawLayer.contentsScale,
            height: drawLayer.frame.size.height * drawLayer.contentsScale
        ))

        // TODO: Unsubscribe from the simulator.
        simulator?.snapshotHandler = { snapshot in
            DispatchQueue.main.async {[weak self] in
                self?.latestImage = snapshot.image
                self?.drawLayer.display()
            }
        }

        resetSimulator()
     }

    // MARK: CALayerDelegate

    func display(_ layer: CALayer) {
        drawLayer.contents = latestImage
    }

    // MARK: Private
    private let drawLayer = CALayer()
    private var latestImage: CGImage?

    // MARK: Handle user interaction

    @IBOutlet weak var interactionView: UIView!
    @IBOutlet weak var interactionModeControl: UISegmentedControl!

    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) {
        if case .light = currentInteractionMode {
            let lightLogation = sender.location(in: interactionView)
            lights.append(Light(
                pos: CGPoint(
                    x: lightLogation.x * drawLayer.contentsScale,
                    y: lightLogation.y * drawLayer.contentsScale)))
            resetSimulator()
        }
    }

    @IBAction func panGesture(_ sender: UIPanGestureRecognizer) {
        switch (currentInteractionMode, sender.state) {
        case (.wall, .began):
            wallStartLocation = sender.location(in: interactionView)
        case (.wall, .changed):
            guard let start = wallStartLocation else { break }
            let end = sender.location(in: interactionView)

            interactiveWall = Wall(
                pos1: CGPoint(
                    x: start.x * drawLayer.contentsScale,
                    y: start.y * drawLayer.contentsScale),
                pos2: CGPoint(
                    x: end.x * drawLayer.contentsScale,
                    y: end.y * drawLayer.contentsScale))

            resetSimulator()

        case (.wall, .ended):
            guard let start = wallStartLocation else { break }
            let end = sender.location(in: interactionView)

            walls.append(Wall(
                pos1: CGPoint(
                    x: start.x * drawLayer.contentsScale,
                    y: start.y * drawLayer.contentsScale),
                pos2: CGPoint(
                    x: end.x * drawLayer.contentsScale,
                    y: end.y * drawLayer.contentsScale)))

            // The interactive wall when building the wall is no longer relevant
            interactiveWall = nil

            resetSimulator()
        default:
            break
        }
    }

    /// Used to track where the start of a wall was.
    /// HACK: This should probably be encoded in the interaction enum eventually?
    var wallStartLocation: CGPoint?

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
        let finalLights = lights
        var finalWalls = walls
        var isInteractive = false

        if let strongInteractiveWall = interactiveWall {
            finalWalls = finalWalls + [strongInteractiveWall]
            isInteractive = true
        }

        let layout = SimulationLayout(
            lights: finalLights,
            walls: finalWalls)

        simulator?.restartSimulation(
            layout: layout,
            isInteractive: isInteractive)

    }

    private var lights = [Light]()
    private var walls = [Wall]()
    private var interactiveWall: Wall?
    private var simulator: LightSimulator?
}

