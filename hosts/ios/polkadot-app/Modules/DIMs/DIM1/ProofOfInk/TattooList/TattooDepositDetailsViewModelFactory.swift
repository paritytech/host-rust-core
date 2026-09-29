import Foundation
import UIKit
import SubstrateSdk
import PolkadotUI

struct TattooConfirmDepositViewModel {
    let amount: String
    let isLoading: Bool
    let action: () -> Void
}

protocol TattooDepositDetailsViewModelMaking {
    func makeApplyWithDeposit(
        deposit: Balance,
        action: @escaping () -> Void
    ) -> TattooConfirmDepositViewModel

    func makeInsufficientDeposit(
        remaining: Balance,
        inProgress: Bool,
        action: @escaping () -> Void
    ) -> TattooDepositDetailsViewController.ViewModel
}

final class TattooDepositDetailsViewModelFactory: TattooDepositDetailsViewModelMaking {
    private let balanceViewModelFactory: PrimitiveBalanceViewModelFactoryProtocol
    private let confirmDepositViewModelFactory: ConfirmDepositViewModelMaking?

    init(
        balanceViewModelFactory: PrimitiveBalanceViewModelFactoryProtocol,
        confirmDepositViewModelFactory: ConfirmDepositViewModelMaking?
    ) {
        self.balanceViewModelFactory = balanceViewModelFactory
        self.confirmDepositViewModelFactory = confirmDepositViewModelFactory
    }

    func makeApplyWithDeposit(
        deposit: Balance,
        action: @escaping () -> Void
    ) -> TattooConfirmDepositViewModel {
        let depositString = confirmDepositViewModelFactory?.formatAmount(deposit) ??
            balanceViewModelFactory.amountFromValue(deposit, roundingMode: .up).value(for: .current)

        return TattooConfirmDepositViewModel(
            amount: depositString,
            isLoading: false,
            action: action
        )
    }

    func makeInsufficientDeposit(
        remaining: Balance,
        inProgress: Bool,
        action: @escaping () -> Void
    ) -> TattooDepositDetailsViewController.ViewModel {
        let remainingString = balanceViewModelFactory
            .amountFromValue(remaining, roundingMode: .up)
            .value(for: .current)

        return TattooDepositDetailsViewController.ViewModel(
            requiredAmount: remainingString,
            inProgress: inProgress,
            actionHandler: action
        )
    }
}
