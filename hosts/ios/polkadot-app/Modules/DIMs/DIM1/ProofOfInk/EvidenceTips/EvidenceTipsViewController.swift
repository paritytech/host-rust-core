import UIKit
import FoundationExt

final class EvidenceTipsViewController: UIViewController, ViewHolder {
    typealias RootViewType = EvidenceTipsViewLayout

    let presenter: EvidenceTipsPresenterProtocol

    init(presenter: EvidenceTipsPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = EvidenceTipsViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        presenter.setup()
    }
}

extension EvidenceTipsViewController: EvidenceTipsViewProtocol {
    func didReceive(viewModel: EvidenceTipsViewModel) {
        rootView.bind(viewModel: viewModel)
    }
}
