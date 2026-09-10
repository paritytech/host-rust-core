import UIKit
import FoundationExt

final class RootInitViewController: UIViewController, ViewHolder {
    typealias RootViewType = RootInitViewLayout

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = RootInitViewLayout()
    }
}

extension RootInitViewController: RootViewProtocol {
    func didReceive(viewModel: RootInitViewLayout.ViewModel) {
        rootView.bind(viewModel: viewModel)
    }
}
