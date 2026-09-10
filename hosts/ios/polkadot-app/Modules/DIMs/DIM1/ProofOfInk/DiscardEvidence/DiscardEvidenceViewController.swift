import UIKit
import FoundationExt

final class DiscardEvidenceViewController: UIViewController, ViewHolder {
    typealias RootViewType = DiscardEvidenceViewLayout

    let presenter: DiscardEvidencePresenterProtocol

    init(presenter: DiscardEvidencePresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = DiscardEvidenceViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupActions()
        presenter.setup()
    }
}

private extension DiscardEvidenceViewController {
    func setupActions() {
        rootView.cancelButton.addTarget(
            self,
            action: #selector(didTapCancel),
            for: .touchUpInside
        )

        rootView.mainButton.addTarget(
            self,
            action: #selector(didTapDiscard),
            for: .touchUpInside
        )
    }

    @objc
    func didTapCancel() {
        presenter.cancel()
    }

    @objc
    func didTapDiscard() {
        presenter.discard()
    }
}

extension DiscardEvidenceViewController: DiscardEvidenceViewProtocol {
    func didReceive(viewModel: DiscardEvidenceViewModel) {
        rootView.bind(viewModel: viewModel)
    }
}
