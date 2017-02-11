//
//  OptionsViewController.swift
//  light-playground
//
//  Created by Aaron Eidelson on 2/3/17.
//  Copyright © 2017 Aaron Eidelson. All rights reserved.
//

import Foundation
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

        redAbsorptionSlider.setValue(Float(absorption.r), animated: false)
        greenAbsorptionSlider.setValue(Float(absorption.g), animated: false)
        blueAbsorptionSlider.setValue(Float(absorption.b), animated: false)

        diffusionSlider.setValue(Float(diffusion), animated: false)
    }

    /// Called on viewWillAppear so setInitialValues can be called.
    var loadDefaults: () -> Void = {}

    var onExposureChange: (CGFloat) -> Void = { _ in }
    var onLightColorChange: (LightColor) -> Void = { _ in }
    var onAbsorptionChange: (FractionalLightColor) -> Void = { _ in }
    var onDiffusionChange: (CGFloat) -> Void = { _ in }
    var onSaveButtonHit: () -> Void = {}

    // MARK: Interface builder outlets

    @IBOutlet weak var exposureSlider: UISlider!
    @IBOutlet weak var lightRedSlider: UISlider!
    @IBOutlet weak var lightGreenSlider: UISlider!
    @IBOutlet weak var lightBlueSlider: UISlider!
    @IBOutlet weak var diffusionSlider: UISlider!
    @IBOutlet weak var redAbsorptionSlider: UISlider!
    @IBOutlet weak var greenAbsorptionSlider: UISlider!
    @IBOutlet weak var blueAbsorptionSlider: UISlider!

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

    @IBAction func redAbsorptionChanged(_ sender: Any) {
        absorptionChanged()
    }

    @IBAction func greenAbsorptionChanged(_ sender: Any) {
        absorptionChanged()
    }

    @IBAction func blueAbsorptionChanged(_ sender: Any) {
        absorptionChanged()
    }

    @IBAction func saveButtonHit(_ sender: Any) {
        dismiss(animated: false)
        onSaveButtonHit()
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

    private func absorptionChanged() {
        onAbsorptionChange(FractionalLightColor(
            r: CGFloat(redAbsorptionSlider.value),
            g: CGFloat(greenAbsorptionSlider.value),
            b: CGFloat(blueAbsorptionSlider.value)))
    }
}
