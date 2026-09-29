import UIKit
import PolkadotUI

protocol EnableNotificationViewModelMaking {
    func viewModel(isDenied: Bool) -> EnableNotificationsViewLayout.ViewModel
}

final class EnableNotificationViewModelFactory: EnableNotificationViewModelMaking {
    private let variant: EnableNotificationsVariant

    init(variant: EnableNotificationsVariant) {
        self.variant = variant
    }

    func viewModel(isDenied: Bool) -> EnableNotificationsViewLayout.ViewModel {
        switch variant {
        case .tattooUploading:
            tattooUploadingViewModel(isDenied: isDenied)
        case .game:
            gameViewModel(isDenied: isDenied)
        }
    }
}

private extension EnableNotificationViewModelFactory {
    func tattooUploadingViewModel(isDenied: Bool) -> EnableNotificationsViewLayout.ViewModel {
        .init(
            reasons: [
                .init(
                    image: .evidenceUploading,
                    details: String(localized: .Notification.enableNotificationReasonEvidenceUploaded)
                ),
                .init(
                    image: .evidenceInReview,
                    details: String(localized: .Notification.enableNotificationReasonEvidenceAccepted)
                ),
                .init(
                    image: .evidenceBadgeIcon,
                    details: String(localized: .Notification.enableNotificationReasonEvidenceIssued)
                )
            ],
            additionalInfo: nil,
            enableTitle: isDenied
                ? String(localized: .Common.openSettings)
                : String(localized: .Notification.enableNotificationEnableButton)
        )
    }

    func gameViewModel(isDenied: Bool) -> EnableNotificationsViewLayout.ViewModel {
        .init(
            reasons: [
                .init(
                    image: .upcomingGameReason,
                    details: String(localized: .Notification.enableNotificationReasonGameUpcoming)
                ),
                .init(
                    image: .completedGameReason,
                    details: String(localized: .Notification.enableNotificationReasonGameCompleted)
                ),
                .init(
                    image: .rewardGameReason,
                    details: String(localized: .Notification.enableNotificationReasonGameRewardUpdates)
                )
            ],
            additionalInfo: gameAdditionalInfo(isDenied: isDenied),
            enableTitle: isDenied
                ? String(localized: .Common.openSettings)
                : String(localized: .Notification.enableNotificationEnableButton)
        )
    }

    func gameAdditionalInfo(isDenied: Bool) -> EnableNotificationsViewLayout.ViewModel.AdditionalInfoModel? {
        let string: String
        let highlightedString: String
        if isDenied {
            string = String(localized: .Notification.enableNotificationDeniedGameAdditionalInfo)
            highlightedString = String(localized: .Notification.enableNotificationDeniedGameAdditionalInfoHighlighted)
        } else {
            string = String(localized: .Notification.enableNotificationGameAdditionalInfo)
            highlightedString = String(localized: .Notification.enableNotificationGameAdditionalInfoHighlighted)
        }
        let range = (string as NSString).range(of: highlightedString)
        let attributedString = NSMutableAttributedString(
            string: string,
            attributes: [.foregroundColor: UIColor.white69]
        )
        attributedString.addAttributes(
            [.foregroundColor: UIColor.white100],
            range: range
        )

        return .init(
            info: attributedString,
            icon: .evidenceUploadingKeepOpened.tinted(with: UIColor.white48)!
        )
    }
}
