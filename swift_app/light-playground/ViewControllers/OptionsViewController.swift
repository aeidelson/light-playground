import UIKit

class OptionsViewController: UITableViewController, UIPopoverPresentationControllerDelegate {

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        fatalError("Has not been implemented")
    }

    override init(style: UITableViewStyle) {
        fatalError("Has not been implemented")
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        self.modalPresentationStyle = .popover
        self.popoverPresentationController?.delegate = self
    }

    // MARK: UIViewController

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        loadDefaults()
    }

    // MARK: UIPopoverPresentationControllerDelegate

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }

    func popoverPresentationControllerShouldDismissPopover(
        _ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        self.dismiss(animated: false)
        return true
    }

    // MARK: Internal

    func setInitialValues(
        exposure: CGFloat,
        lightColor: LightColor,
        absorption: FractionalLightColor,
        diffusion: CGFloat
    ) {
        exposureSlider.setValue(Float(exposure), animated: false)

        lightRedSlider.setValue(Float(lightColor.r), animated: false)
        lightGreenSlider.setValue(Float(lightColor.g), animated: false)
        lightBlueSlider.setValue(Float(lightColor.b), animated: false)

        // Surface color is the inverse of the absorption.
        surfaceRedSlider.setValue(1.0 - Float(absorption.r), animated: false)
        surfaceGreenSlider.setValue(1.0 - Float(absorption.g), animated: false)
        surfaceBlueSlider.setValue(1.0 - Float(absorption.b), animated: false)

        diffusionSlider.setValue(Float(diffusion), animated: false)
    }

    /// Called on viewWillAppear so setInitialValues can be called.
    var loadDefaults: () -> Void = {}

    var onExposureChange: (CGFloat) -> Void = { _ in }
    var onLightColorChange: (LightColor) -> Void = { _ in }
    var onAbsorptionChange: (FractionalLightColor) -> Void = { _ in }
    var onDiffusionChange: (CGFloat) -> Void = { _ in }

    // MARK: Interface builder outlets

    @IBOutlet weak var exposureSlider: UISlider!
    @IBOutlet weak var lightRedSlider: UISlider!
    @IBOutlet weak var lightGreenSlider: UISlider!
    @IBOutlet weak var lightBlueSlider: UISlider!
    @IBOutlet weak var diffusionSlider: UISlider!
    @IBOutlet weak var surfaceRedSlider: UISlider!
    @IBOutlet weak var surfaceGreenSlider: UISlider!
    @IBOutlet weak var surfaceBlueSlider: UISlider!

    @IBAction func exposureChanged(_ sender: Any) {
        onExposureChange(CGFloat(exposureSlider.value))
    }

    @IBAction func redLightColorChanged(_ sender: Any) {
        lightColorChanged()
    }

    @IBAction func greenLightColorChanged(_ sender: Any) {
        lightColorChanged()
    }

    @IBAction func blueLightColorChanged(_ sender: Any) {
        lightColorChanged()
    }

    @IBAction func diffusionChanged(_ sender: Any) {
        onDiffusionChange(CGFloat(diffusionSlider.value))
    }

    @IBAction func redPassChanged(_ sender: Any) {
        passChanged()
    }

    @IBAction func greenPassChanged(_ sender: Any) {
        passChanged()
    }

    @IBAction func bluePassChanged(_ sender: Any) {
        passChanged()
    }

    @IBAction func onShowTutorial(_ sender: Any) {
        guard let storyboard = self.storyboard else { preconditionFailure() }
        present(OnboardingViewController.new(storyboard: storyboard), animated: false, completion: nil)
    }

    // MARK: Private

    // A helper to combine the color sliders before calling `onLightColorChange`
    private func lightColorChanged() {
        // The values of the sliders should be constrained at the xib-level to 0-255.
        onLightColorChange(LightColor(
            r: UInt8(lightRedSlider.value),
            g: UInt8(lightGreenSlider.value),
            b: UInt8(lightBlueSlider.value)))
    }

    private func passChanged() {
        // `Pass` is just the inverse/friendly version of absorption.
        onAbsorptionChange(FractionalLightColor(
            r: 1.0 - CGFloat(surfaceRedSlider.value),
            g: 1.0 - CGFloat(surfaceGreenSlider.value),
            b: 1.0 - CGFloat(surfaceBlueSlider.value)))
    }
}
