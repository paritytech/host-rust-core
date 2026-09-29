import UIKit
import UIKit_iOS
import FoundationExt

final class DiscardDIMViewController: UIViewController, ViewHolder {
    typealias RootViewType = DiscardDIMViewLayout

    let presenter: DiscardDIMPresenterProtocol

    init(presenter: DiscardDIMPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = DiscardDIMViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupActions()
        presenter.setup()
    }
}

private extension DiscardDIMViewController {
    func setupActions() {
        rootView.cancelButton.addTarget(
            self,
            action: #selector(actionCancel),
            for: .touchUpInside
        )

        rootView.mainButton.addTarget(
            self,
            action: #selector(actionDiscard),
            for: .touchUpInside
        )
    }

    @objc
    func actionCancel() {
        presenter.cancel()
    }

    @objc
    func actionDiscard() {
        presenter.discardReservation()
    }
}

extension DiscardDIMViewController: DiscardDIMViewProtocol {
    func didReceive(viewModel: DiscardDIMViewModel) {
        rootView.bind(viewModel: viewModel)
    }

    func didReceive(activity active: Bool) {
        rootView.showActivity(active: active)
    }
}

extension DiscardDIMViewController: ModalSheetPresenterDelegate {
    func presenterShouldHide(_: any ModalPresenterProtocol) -> Bool {
        !rootView.activityInProgress
    }

    func presenterCanDrag(_: ModalPresenterProtocol) -> Bool {
        !rootView.activityInProgress
    }
}
