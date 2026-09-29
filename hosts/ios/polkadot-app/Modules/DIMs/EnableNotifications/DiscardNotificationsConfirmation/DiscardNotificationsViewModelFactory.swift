import Foundation

protocol DiscardNotificationsViewModelMaking {
    func viewModel() -> DiscardNotificationsViewLayout.ViewModel
}

struct DiscardNotificationsViewModelFactory: DiscardNotificationsViewModelMaking {
    private let variant: EnableNotificationsVariant

    init(variant: EnableNotificationsVariant) {
        self.variant = variant
    }

    func viewModel() -> DiscardNotificationsViewLayout.ViewModel {
        let title =
            switch variant {
            case .tattooUploading:
                String(localized: .Notification.discardNotificationsTitle)
            case .game:
                String(localized: .Notification.discardNotificationsGameTitle)
            }

        return .init(
            title: title,
            enableButtonTitle: String(localized: .Notification.enableNotificationEnableButton),
            discardButtonTitle: String(localized: .Notification.enableNotificationIgnoreButton)
        )
    }
}
