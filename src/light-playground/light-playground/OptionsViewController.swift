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

    // MARK: Internal

    func setInitialValues(
        exposure: CGFloat,
        lightColor: LightColor,
        wallReflectivity: CGFloat
    ) {
        exposureSlider.setValue(Float(exposure), animated: false)

        lightRedSlider.setValue(Float(lightColor.r), animated: false)
        lightGreenSlider.setValue(Float(lightColor.g), animated: false)
        lightBlueSlider.setValue(Float(lightColor.b), animated: false)

        wallReflectivitySlider.setValue(Float(wallReflectivity), animated: false)
    }

    /// Called on viewWillAppear so setInitialValues can be called.
    var loadDefaults: () -> Void = {}

    var onExposureChange: (CGFloat) -> Void = { _ in }
    var onLightColorChange: (LightColor) -> Void = { _ in }
    var onWallReflectivityChange: (CGFloat) -> Void = { _ in }

    // MARK: Interface builder outlets

    @IBOutlet weak var exposureSlider: UISlider!
    @IBOutlet weak var lightRedSlider: UISlider!
    @IBOutlet weak var lightGreenSlider: UISlider!
    @IBOutlet weak var lightBlueSlider: UISlider!
    @IBOutlet weak var wallReflectivitySlider: UISlider!

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

    @IBAction func wallReflectivityChanged(_ sender: Any) {
        onWallReflectivityChange(CGFloat(wallReflectivitySlider.value))
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
}
