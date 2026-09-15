import Foundation
import PolkadotUI
import SubstrateSdk

final class TopUpMismatchPresenter {
    weak var view: TopUpMismatchViewProtocol?
    let wireframe: TopUpMismatchWireframeProtocol

    private let context: TopUpRequestContext
    private let claimedAmount: Balance
    private let requestedAmount: Balance
    private let viewModelFactory: TopUpRequestViewModelMaking

    init(
        wireframe: TopUpMismatchWireframeProtocol,
        context: TopUpRequestContext,
        claimedAmount: Balance,
        requestedAmount: Balance,
        viewModelFactory: TopUpRequestViewModelMaking
    ) {
        self.wireframe = wireframe
        self.context = context
        self.claimedAmount = claimedAmount
        self.requestedAmount = requestedAmount
        self.viewModelFactory = viewModelFactory
    }
}

extension TopUpMismatchPresenter: TopUpMismatchPresenterProtocol {
    func setup() {
        let viewModel = TopUpMismatchViewModel(
            title: viewModelFactory.amountMismatchTitle(productId: context.productId),
            claimedAmount: viewModelFactory.formatAmountValue(claimedAmount),
            originalAmount: viewModelFactory.formatAmountValue(requestedAmount),
            tokenSymbol: viewModelFactory.tokenSymbol(),
            subtitle: viewModelFactory.amountMismatchWarning(),
            closeButtonTitle: String(localized: .Common.close)
        )
        viewModel.onCloseTapped = { [weak self] in
            self?.didTapClose()
        }
        view?.didReceive(viewModel: viewModel)
    }

    func didTapClose() {
        wireframe.dismiss(view: view)
        context.deliverFailed(PaymentTopUpError.partialPayment(amount: claimedAmount))
    }
}
