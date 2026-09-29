import Foundation
import PolkadotUI
import Individuality

protocol TattooCommitViewModelFactoryProtocol {
    func createListViewModel(
        from viewModel: TattooCommitModel,
        choice: ProofOfInk.Choice
    ) -> TattooCommitListViewModel
}

final class TattooCommitViewModelFactory {
    private let viewModelFactory: TattooImageViewModelFactoryProtocol

    init(
        viewModelFactory: TattooImageViewModelFactoryProtocol = TattooImageViewModelFactory()
    ) {
        self.viewModelFactory = viewModelFactory
    }
}

extension TattooCommitViewModelFactory: TattooCommitViewModelFactoryProtocol {
    func createListViewModel(
        from viewModel: TattooCommitModel,
        choice: ProofOfInk.Choice
    ) -> TattooCommitListViewModel {
        .init(
            tattooDescription: provideTattooDescription(name: viewModel.name, description: viewModel.description),
            tattooImage: viewModelFactory.createViewModelFromChoice(choice)
        )
    }
}

private extension TattooCommitViewModelFactory {
    func provideTattooDescription(name: String, description: String) -> TopBottomLabelView.ViewModel {
        .init(
            top: name,
            bottom: description
        )
    }
}
