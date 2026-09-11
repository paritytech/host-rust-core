import UIKit
import PolkadotUI
import SwiftUI

final class TattooListViewLayout: UIView {
    let collectionView: UICollectionView = {
        let layout = TattooCollectionViewLayout.createLayout()
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)

        return view
    }()

    private var depositViewController: TattooDepositDetailsViewController?
    private var confirmDepositViewController: UIHostingController<ConfirmDepositView>?

    private var depositView: UIView? {
        depositViewController?.view ?? confirmDepositViewController?.view
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupStyle()
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupStyle() {
        backgroundColor = .bgSurfaceMain

        collectionView.backgroundColor = .clear
    }

    private func setupLayout() {
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide.snp.top)
            make.bottom.leading.trailing.equalToSuperview()
        }
    }
}

extension TattooListViewLayout {
    enum DepositViewType {
        case details(TattooDepositDetailsViewController.ViewModel)
        case confirm(TattooConfirmDepositViewModel)
    }

    struct ViewModel {
        let depositViewType: DepositViewType?
    }

    func bind(viewModel: ViewModel) {
        if let depositViewType = viewModel.depositViewType {
            switch depositViewType {
            case let .details(depositViewModel):
                removeConfirmDepositViewIfNeeded()
                addDepositViewIfNeeded()
                updateDepositView(viewModel: depositViewModel)
            case let .confirm(confirmViewModel):
                removeDepositViewIfNeeded()
                addConfirmDepositViewIfNeeded()
                updateConfirmDepositView(viewModel: confirmViewModel)
            }
        } else {
            removeDepositViewIfNeeded()
            removeConfirmDepositViewIfNeeded()
        }
    }

    func bind(tattooApplyActivity active: Bool) {
        if let confirmDepositViewController {
            confirmDepositViewController.rootView.isLoading = active
        }
    }

    private func addDepositViewIfNeeded() {
        guard depositView == nil else { return }
        let viewC = TattooDepositDetailsViewController(requiredAmount: "asdas")

        addSubview(viewC.view)
        viewC.view.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(4)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-12)
        }
        depositViewController = viewC
    }

    private func updateDepositView(viewModel: TattooDepositDetailsViewController.ViewModel) {
        guard let depositView else {
            return assertionFailure()
        }
        if depositView.frame == .zero {
            depositView.superview?.layoutIfNeeded()
            depositView.layoutIfNeeded()
            depositView.alpha = 0
        }

        UIView.animate(withDuration: 0.3) {
            depositView.alpha = 1
            self.depositViewController?.bind(viewModel: viewModel)
            depositView.layoutIfNeeded()
        }
    }

    private func removeDepositViewIfNeeded() {
        guard let depositView = depositViewController?.view else { return }

        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
            depositView.alpha = 0
        } completion: { finished in
            guard finished else {
                return
            }
            depositView.removeFromSuperview()
            self.depositViewController = nil
        }
    }

    private func addConfirmDepositViewIfNeeded() {
        guard confirmDepositViewController == nil else { return }
        let viewController = UIHostingController(
            rootView: ConfirmDepositView(amount: "", isLoading: false, onConfirmTapped: {})
        )
        viewController.view.backgroundColor = .clear

        addSubview(viewController.view)
        viewController.view.snp.makeConstraints {
            $0.directionalEdges.equalToSuperview()
        }
        confirmDepositViewController = viewController
    }

    private func updateConfirmDepositView(viewModel: TattooConfirmDepositViewModel) {
        guard let confirmView = confirmDepositViewController?.view else {
            return assertionFailure()
        }
        if confirmView.frame == .zero {
            confirmView.superview?.layoutIfNeeded()
            confirmView.layoutIfNeeded()
            confirmView.alpha = 0
        }

        UIView.animate(withDuration: 0.3) { [self] in
            confirmView.alpha = 1
            confirmDepositViewController?.rootView.amount = viewModel.amount
            confirmDepositViewController?.rootView.isLoading = viewModel.isLoading
            confirmDepositViewController?.rootView.onConfirmTapped = viewModel.action
            confirmView.layoutIfNeeded()
        }
    }

    private func removeConfirmDepositViewIfNeeded() {
        guard let confirmView = confirmDepositViewController?.view else { return }

        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
            confirmView.alpha = 0
        } completion: { finished in
            guard finished else {
                return
            }
            confirmView.removeFromSuperview()
            self.confirmDepositViewController = nil
        }
    }
}
