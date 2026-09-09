import UIKit

protocol RootInitViewModelMaking {
    func makeInitial() -> RootInitViewLayout.ViewModel
    func makeWaitingForNetwork() -> RootInitViewLayout.ViewModel
}

final class RootInitViewModelFactory: RootInitViewModelMaking {
    func makeInitial() -> RootInitViewLayout.ViewModel {
        RootInitViewLayout.ViewModel(
            logo: .polkadotLogoLoading.withRenderingMode(.alwaysTemplate),
            issue: nil
        )
    }

    func makeWaitingForNetwork() -> RootInitViewLayout.ViewModel {
        RootInitViewLayout.ViewModel(
            logo: .polkadotLogoLoading.withRenderingMode(.alwaysTemplate),
            issue: RootInitViewLayout.ViewModel.Issue(
                title: String(localized: .rootInitWaitingTitle),
                subtitle: String(localized: .rootInitWaitingSubtitle)
            )
        )
    }
}
