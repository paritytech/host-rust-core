import UIKit
import SwiftUI

final class BalanceInfoViewController: UIHostingController<BalanceInfoView> {
    let presenter: BalanceInfoPresenterProtocol

    init(presenter: BalanceInfoPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: BalanceInfoView())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHandlers()
        presenter.setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func setupHandlers() {
        rootView.onAvailableNowInfo = { [unowned presenter] in
            presenter.onAvailableNowInfo()
        }
        rootView.onAvailableSoonInfo = { [unowned presenter] in
            presenter.onAvailableSoonInfo()
        }
    }
}

extension BalanceInfoViewController: BalanceInfoViewProtocol {
    func didReceive(model: BalanceInfoModel) {
        rootView.model = model
    }
}
