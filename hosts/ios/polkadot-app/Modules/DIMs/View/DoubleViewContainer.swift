import UIKit
import UIKit_iOS

final class DoubleViewContainer<F: UIView, S: UIView>: UIView {
    enum ShowResult {
        case notChanged
        case switchedToFirst
        case switchedToSecond
    }

    var firstView: F? {
        subviews.first as? F
    }

    var secondView: S? {
        subviews.first as? S
    }

    @discardableResult
    func showFirstView(setupViewClosure: ((F) -> Void)?) -> ShowResult {
        showView(
            of: F.self,
            setupViewClosure: setupViewClosure,
        )
    }

    @discardableResult
    func showSecondView(setupViewClosure: ((S) -> Void)?) -> ShowResult {
        showView(
            of: S.self,
            setupViewClosure: setupViewClosure,
        )
    }
}

private extension DoubleViewContainer {
    func showView<View: UIView>(
        of type: View.Type,
        setupViewClosure: ((View) -> Void)?
    ) -> ShowResult {
        if let addedView = subviews.first as? View {
            setupViewClosure?(addedView)
            return .notChanged
        }

        let animated = !subviews.isEmpty
        let result: ShowResult = type == F.self
            ? .switchedToFirst
            : .switchedToSecond

        func addView() {
            subviews.first?.removeFromSuperview()
            let newView = View()
            addSubview(newView)
            newView.snp.makeConstraints { $0.edges.equalToSuperview() }
            setupViewClosure?(newView)
        }

        if animated {
            UIView.transition(
                with: self,
                duration: 0.3,
                options: result == .switchedToSecond
                    ? .transitionFlipFromRight
                    : .transitionFlipFromLeft
            ) {
                addView()
            }
        } else {
            addView()
        }

        return result
    }
}
