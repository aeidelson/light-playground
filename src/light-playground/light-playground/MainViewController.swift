import UIKit

class MainViewController: UIViewController, CALayerDelegate, UIPopoverPresentationControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.isHidden = true

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
    @IBOutlet weak var optionsButton: UIBarButtonItem!

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
                radius: 50,
                shapeAttributes: ShapeAttributes(
                    absorption: wallAbsorption,
                    diffusion: wallDiffusion,
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
                    absorption: wallAbsorption,
                    diffusion: wallDiffusion))

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
                    absorption: wallAbsorption,
                    diffusion: wallDiffusion)))

            // The interactive wall when building the wall is no longer relevant
            interactiveWall = nil

            resetSimulator()
        default:
            break
        }
    }

    @IBAction func clearButtonHit(_ sender: Any) {
        self.circleShapes = []
        self.walls = []
        self.lights = []
        self.interactiveWall = nil
        resetSimulator()
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
                wallAbsorption: strongSelf.wallAbsorption,
                wallDiffusion: strongSelf.wallDiffusion)
        }

        optionsViewController.onExposureChange = { [weak self] newExposure in
            self?.exposure = newExposure
            self?.resetSimulator()
        }

        optionsViewController.onLightColorChange = { [weak self] newLightColor in
            self?.lightColor = newLightColor
        }

        optionsViewController.onWallAbsorptionChange = { [weak self] newWallAbsorption in
            self?.wallAbsorption = newWallAbsorption
        }


        optionsViewController.onWallDiffusionChange = { [weak self] newWallDiffusion in
            self?.wallDiffusion = newWallDiffusion
        }

        optionsViewController.onSaveButtonHit = { [weak self] in
            self?.saveImage()
        }

        optionsViewController.modalPresentationStyle = .popover
        optionsViewController.popoverPresentationController?.barButtonItem = optionsButton
        present(optionsViewController, animated: false, completion: nil)
    }

    /// Used to track where the start of a wall was.
    /// HACK: This should probably be encoded in the interaction enum eventually?
    var wallStartLocation: CGPoint?

    private enum InteractionMode {
        case light
        case wall
        case circle
    }

    private var currentInteractionMode: InteractionMode {
        switch interactionModeControl.selectedSegmentIndex {
        case 0:
            return .light
        case 1:
            return .wall
        case 2:
            return .circle
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
            exposure: exposure,
            lights: finalLights,
            walls: finalWalls,
            circleShapes: circleShapes)

        simulator?.restartSimulation(
            layout: layout,
            isInteractive: isInteractive)
    }

    private func saveImage() {
        guard let cgImage = latestImage else { return }
        let image = UIImage(cgImage: cgImage)
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    /// Options (with defaults) that are configurable in the OptionsController.
    private var exposure: CGFloat = 0.60
    private var lightColor = LightColor(r: 255, g: 255, b: 255)
    private var wallAbsorption: CGFloat = 0.25
    private var wallDiffusion: CGFloat = 0.1

    // State of the simulation
    private var lights = [Light]()
    private var walls = [Wall]()
    private var circleShapes = [CircleShape]()
    private var interactiveWall: Wall?
    private var simulator: LightSimulator?
}

