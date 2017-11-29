import UIKit

/// Maintains all the logic around onboarding (including tracking if it has already been shown).
class OnboardingViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    public static func presentIfNeverCompleted(storyboard: UIStoryboard, parentController: UIViewController) {
        if !UserDefaults.standard.bool(forKey: kOnboardingKeyName) {
            parentController.present(OnboardingViewController.new(storyboard: storyboard), animated: false, completion: nil)
        }
    }

    public static func new(storyboard: UIStoryboard) -> OnboardingViewController {
        let viewController = storyboard.instantiateViewController(
            withIdentifier: "OnboardingScreen") as! OnboardingViewController

        viewController.modalPresentationStyle = .fullScreen
        viewController.modalTransitionStyle = .crossDissolve

        return viewController
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        self.view.backgroundColor = .black

        guard let storyboard = self.storyboard else { preconditionFailure() }

        screens.append(contentsOf: [
            SingleOnboardingPageViewController.new(
                storyboard: storyboard,
                text: "Welcome to light playground!",
                imageName: "onboarding_1"),
            SingleOnboardingPageViewController.new(
                storyboard: storyboard,
                text: "Select the light tool and tap on space to add a light",
                imageName: "onboarding_2"),
            SingleOnboardingPageViewController.new(
                storyboard: storyboard,
                text: "After adding a light, select the wall tool to draw walls",
                imageName: "onboarding_3"),
            SingleOnboardingPageViewController.new(
                storyboard: storyboard,
                text: "Circle and triangle tools can also be used to distort light",
                imageName: "onboarding_4"),
            SingleOnboardingPageViewController.new(
                storyboard: storyboard,
                text: "Colors can be configured using the options button",
                imageName: "onboarding_5"),
            SingleOnboardingPageViewController.new(
                storyboard: storyboard,
                text: "Your image can be shared at any time using the share button",
                imageName: "onboarding_6"),
            SingleOnboardingPageViewController.new(
                storyboard: storyboard,
                text: "Swipe to start!",
                imageName: nil),



            finalPlaceholderController
        ])

        self.dataSource = self
        self.delegate = self
        self.setViewControllers([screens[0]], direction: .forward, animated: true, completion: nil)
    }

    // MARK:UIPageViewControllerDataSource

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let currentIndex = screens.index(of: viewController) else { return nil }
        let newIndex = currentIndex - 1
        if newIndex >= 0 {
            return screens[newIndex]
        }
        return nil
    }
    
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let currentIndex = screens.index(of: viewController) else { return nil }
        let newIndex = currentIndex + 1
        if newIndex < screens.count {
            return screens[newIndex]
        }
        return nil
    }

    func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return screens.count
    }

    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        guard let currentViewController = pageViewController.viewControllers?.first else { return 0 }
        guard let index = screens.index(of: currentViewController) else { return 0 }
        return index
    }

    // MARK: UIPageViewControllerDelegate

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        if pendingViewControllers.contains(finalPlaceholderController) {
            // Record that the onboarding has been completed.
            UserDefaults.standard.set(true, forKey: OnboardingViewController.kOnboardingKeyName)
            // We hit the final view controller, dismiss so the user can use the app.
            dismiss(animated: true, completion: nil)
        }
    }

    // MARK: Private

    var screens = [UIViewController]()
    var finalPlaceholderController: UIViewController = UIViewController()

    // Shouldn't change unless we want to bug existing users again.
    private static let kOnboardingKeyName = "HasCompletedOnboardingV1"
}
