import UIKit
import Foundation_iOS
import FoundationExt

final class TattooConfirmViewController: UIViewController, ViewHolder {
    typealias RootViewType = TattooConfirmViewLayout

    let presenter: TattooConfirmPresenterProtocol

    init(presenter: TattooConfirmPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = TattooConfirmViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupLocalization()
        setupHandlers()
    }

    private func setupHandlers() {
        rootView.cancelButton.addTarget(
            self,
            action: #selector(actionCancel),
            for: .touchUpInside
        )

        rootView.confirmButton.addTarget(
            self,
            action: #selector(actionConfirm),
            for: .touchUpInside
        )
    }

    private func setupLocalization() {
        rootView.titleLabel.text = String(localized: .Tattoo.confirmTitle)
        rootView.subtitleLabel.text = String(localized: .Tattoo.confirmSubtitle)
        rootView.cancelButton.imageWithTitleView?.title = String(localized: .Common.cancel)
        rootView.confirmButton.imageWithTitleView?.title = String(localized: .Common.confirm)
    }

    @objc func actionCancel() {
        presenter.cancel()
    }

    @objc func actionConfirm() {
        presenter.confirm()
    }
}

extension TattooConfirmViewController: TattooConfirmViewProtocol {}

extension TattooConfirmViewController: Localizable {
    func applyLocalization() {
        if isViewLoaded {
            setupLocalization()
        }
    }
}
