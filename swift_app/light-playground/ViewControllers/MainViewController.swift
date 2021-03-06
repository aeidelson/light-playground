import UIKit

class MainViewController: UIViewController, CALayerDelegate, UIPopoverPresentationControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup the draw layer
        drawLayer.delegate = self
        drawLayer.isOpaque = true

        // It seems this needs to come from the screen since it isn't necessarily inherited from view correctly:
        //   http://stackoverflow.com/questions/9479001/uiviews-contentscalefactor-depends-on-implementing-drawrect
        drawLayer.contentsScale = UIScreen.main.scale
        interactionView.layer.insertSublayer(drawLayer, at: 0)

        guard let storyboard = self.storyboard else { preconditionFailure() }
        OnboardingViewController.presentIfNeverCompleted(storyboard: storyboard, parentController: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews();

        // Only take action if the simulation dimensions have changed.
        if drawLayer.frame != interactionView.bounds {
            drawLayer.frame = interactionView.bounds

            // The simulator relies on the layout bounds, so it only makes sense to start the simulator
            // after it has been laid out.
            simulator = LightSimulator(
                simulationSize: CGSize(
                    width: drawLayer.frame.size.width * drawLayer.contentsScale,
                    height: drawLayer.frame.size.height * drawLayer.contentsScale),
                initialExposure: exposure)

            simulator?.snapshotHandler = { snapshot in
                DispatchQueue.main.async {[weak self] in
                    self?.latestSnapshot = snapshot
                    self?.drawLayer.display()

                    self?.updateUIState()
                }
            }

            resetSimulator()
        }
     }

    // MARK: CALayerDelegate

    func display(_ layer: CALayer) {
        drawLayer.contents = latestSnapshot?.image
    }

    // MARK: Private
    private let drawLayer = CALayer()
    private var latestSnapshot: SimulationSnapshot?

    // MARK: Handle user interaction

    @IBOutlet weak var interactionView: UIView!
    @IBOutlet weak var interactionModeControl: UISegmentedControl!
    @IBOutlet weak var optionsButton: UIBarButtonItem!
    @IBOutlet weak var statusBar: UILabel!
    @IBOutlet weak var clearButton: UIBarButtonItem!
    @IBOutlet weak var shareButton: UIBarButtonItem!

    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) {
        let tapLocationRaw = sender.location(in: interactionView)
        let tapLocation = CGPoint(
            x: tapLocationRaw.x * drawLayer.contentsScale,
            y: tapLocationRaw.y * drawLayer.contentsScale)
        switch currentInteractionMode {
        case .light:
            lights.append(Light(
                pos: tapLocation,
                color: lightColor))
            resetSimulator()
        case .circle:
            circleShapes.append(CircleShape(
                pos: tapLocation,
                radius: 300,
                shapeAttributes: ShapeAttributes(
                    absorption: absorption,
                    diffusion: diffusion,
                    indexOfRefraction: 1.5,
                    translucent: true)))
            resetSimulator()
        case .triangle:
            let d: CGFloat = 200.0
            let p1 = CGPoint(
                x: tapLocation.x,
                y: tapLocation.y - d)
            let p2 = CGPoint(
                x: tapLocation.x - d,
                y: tapLocation.y + d)
            let p3 = CGPoint(
                x: tapLocation.x + d,
                y: tapLocation.y + d)
            polygonShapes.append(PolygonShape(
                posList: [p1, p2, p3],
                shapeAttributes: ShapeAttributes(
                    absorption: absorption,
                    diffusion: diffusion,
                    indexOfRefraction: 1.5,
                    translucent: true)))

            resetSimulator()
        default:
            break
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
                    y: end.y * drawLayer.contentsScale),
                shapeAttributes: ShapeAttributes(
                    absorption: absorption,
                    diffusion: diffusion))

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
                    y: end.y * drawLayer.contentsScale),
                shapeAttributes: ShapeAttributes(
                    absorption: absorption,
                    diffusion: diffusion)))

            // The interactive wall when building the wall is no longer relevant
            interactiveWall = nil

            resetSimulator()
        default:
            break
        }
    }

    @IBAction func clearButtonHit(_ sender: Any) {
        let alert = UIAlertController(title: "Do you want to clear the scene? (can't be undone)", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive, handler: { _ in
            self.circleShapes = []
            self.polygonShapes = []
            self.walls = []
            self.lights = []
            self.interactiveWall = nil
            self.resetSimulator()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.popoverPresentationController?.barButtonItem = clearButton
        present(alert, animated: true, completion: nil)
    }

    @IBAction func optionsButtonHit(_ sender: Any) {
        guard let viewController =
            self.storyboard?.instantiateViewController(withIdentifier: "OptionsScreen") else { return }
        guard let optionsViewController = viewController as? OptionsViewController else { preconditionFailure() }

        optionsViewController.loadDefaults = { [weak self] in
            guard let strongSelf = self else { return }
            optionsViewController.setInitialValues(
                exposure: strongSelf.exposure,
                lightColor: strongSelf.lightColor,
                absorption: strongSelf.absorption,
                diffusion: strongSelf.diffusion)
        }

        optionsViewController.onExposureChange = { [weak self] newExposure in
            self?.exposure = newExposure
            self?.simulator?.exposure = newExposure
        }

        optionsViewController.onLightColorChange = { [weak self] newLightColor in
            self?.lightColor = newLightColor
        }

        optionsViewController.onAbsorptionChange = { [weak self] newAbsorption in
            self?.absorption = newAbsorption
        }

        optionsViewController.onDiffusionChange = { [weak self] newDiffusion in
            self?.diffusion = newDiffusion
        }

        optionsViewController.modalPresentationStyle = .popover
        optionsViewController.popoverPresentationController?.barButtonItem = optionsButton
        present(optionsViewController, animated: false, completion: nil)
    }

    @IBAction func shareButtonHit(_ sender: Any) {
        precondition(Thread.isMainThread)
        guard let cgImage = latestSnapshot?.image else { return }
        let image = UIImage(cgImage: cgImage)
        let activityViewController = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activityViewController.popoverPresentationController?.barButtonItem = shareButton
        present(activityViewController, animated: true, completion: nil)
    }

    /// Used to track where the start of a wall was.
    /// HACK: This should probably be encoded in the interaction enum eventually?
    var wallStartLocation: CGPoint?

    private enum InteractionMode {
        case light
        case wall
        case circle
        case triangle
    }

    private var currentInteractionMode: InteractionMode {
        switch interactionModeControl.selectedSegmentIndex {
        case 0:
            return .light
        case 1:
            return .wall
        case 2:
            return .circle
        case 3:
            return .triangle
        default:
            preconditionFailure()
        }
    }

    private func updateUIState() {
        precondition(Thread.isMainThread)

        // TODO: Add if using Metal vs CPU

        if self.lights.isEmpty {
            statusBar.text = "Tap anywhere to add a light"

            clearButton.isEnabled = false

            // If there aren't any lights, then the only item the user can add to the scene is a light.
            interactionModeControl.selectedSegmentIndex = 0
            interactionModeControl.setEnabled(true, forSegmentAt: 0)
            interactionModeControl.setEnabled(false, forSegmentAt: 1)
            interactionModeControl.setEnabled(false, forSegmentAt: 2)
            interactionModeControl.setEnabled(false, forSegmentAt: 3)
        } else {
            statusBar.text = "\(latestSnapshot?.totalLightSegmentsTraced ?? 0) light segments drawn"

            clearButton.isEnabled = true

            // Enable all segments, since there is at least one light.
            interactionModeControl.setEnabled(true, forSegmentAt: 0)
            interactionModeControl.setEnabled(true, forSegmentAt: 1)
            interactionModeControl.setEnabled(true, forSegmentAt: 2)
            interactionModeControl.setEnabled(true, forSegmentAt: 3)
        }
    }

    // MARK: Maintain simulation state

    /// Should be called any time the state of input to the simulator changes.
    private func resetSimulator() {
        layoutVersion += 1

        let finalLights = lights
        var finalWalls = walls
        var isInteractive = false

        if let strongInteractiveWall = interactiveWall {
            finalWalls = finalWalls + [strongInteractiveWall]
            isInteractive = true
        }

        let layout = SimulationLayout(
            version: layoutVersion,
            lights: finalLights,
            walls: finalWalls,
            circleShapes: circleShapes,
            polygonShapes: polygonShapes)

        simulator?.restartSimulation(
            layout: layout,
            isInteractive: isInteractive)
    }

    /// Options (with defaults) that are configurable in the OptionsController.
    private var exposure: CGFloat = 0.45
    private var lightColor = LightColor(r: 255, g: 255, b: 255)
    private var absorption: FractionalLightColor = FractionalLightColor.zero
    private var diffusion: CGFloat = 0

    // State of the simulation
    private var layoutVersion = UInt64(0)
    private var lights = [Light]()
    private var walls = [Wall]()
    private var circleShapes = [CircleShape]()
    private var polygonShapes = [PolygonShape]()
    private var interactiveWall: Wall?
    private var simulator: LightSimulator?
}

