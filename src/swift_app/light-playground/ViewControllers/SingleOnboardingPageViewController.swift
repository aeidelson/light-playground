import UIKit

class SingleOnboardingPageViewController: UIViewController {

    public static func new(storyboard: UIStoryboard, text: String, imageName: String?) -> SingleOnboardingPageViewController {
        let viewController = storyboard.instantiateViewController(
            withIdentifier: "SingleOnboardingPageScreen") as! SingleOnboardingPageViewController

        viewController.interimText = text
        viewController.interimImageName = imageName
        return viewController
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        if let interimText = interimText {
            text.text = interimText
        }
        if let interimImageName = interimImageName {
            image.image = UIImage(named: interimImageName)
        }
    }

    // MARK: Outlets

    @IBOutlet weak var text: UITextView!
    @IBOutlet weak var image: UIImageView!

    // MARK: Fileprivate

    // These are used between the time the view controller is created and the time it is inflated.
    // TODO(aeidelson): Is there a better way to do this?
    fileprivate var interimText: String?
    fileprivate var interimImageName: String?

}
