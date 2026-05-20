import UIKit

/// Re-enables the edge-swipe-to-pop gesture when SwiftUI hides the
/// system back button via `.navigationBarBackButtonHidden(true)`.
///
/// UIKit ties `interactivePopGestureRecognizer` to the back button's
/// presence by default — hiding the button disables the gesture.
/// We hide the button to render our own three-line sidebar glyph,
/// but losing the swipe makes the navigation feel non-native.
///
/// Setting the gesture's delegate to the nav controller itself and
/// allowing the gesture whenever there's a previous view in the
/// stack restores the standard iOS pop interaction across every
/// pushed screen in the app.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
