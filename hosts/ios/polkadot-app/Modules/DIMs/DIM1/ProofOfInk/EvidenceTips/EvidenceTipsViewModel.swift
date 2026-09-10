import UIKit

struct EvidenceTipsViewModel: Equatable {
    struct Step: Equatable {
        let step: String
        let title: String
        let description: String
    }

    let icon: UIImage
    let title: String
    let steps: [Step]
}

extension EvidenceTipsViewModel {
    static let photoTips: EvidenceTipsViewModel = .init(
        icon: .photoInstructions,
        title: String(localized: .Tattoo.tipsPhotoTitle),
        steps: [
            .init(
                step: String(localized: .Tattoo.tipsEvidenceStep1),
                title: String(localized: .Tattoo.tipsPhotoStep1Title),
                description: String(localized: .Tattoo.tipsPhotoStep1Description)
            ),
            .init(
                step: String(localized: .Tattoo.tipsEvidenceStep2),
                title: String(localized: .Tattoo.tipsPhotoStep2Title),
                description: String(localized: .Tattoo.tipsPhotoStep2Description)
            )
        ]
    )

    static let videoTips: EvidenceTipsViewModel = .init(
        icon: .videoProvided,
        title: String(localized: .Tattoo.tipsVideoTitle),
        steps: [
            .init(
                step: String(localized: .Tattoo.tipsEvidenceStep1),
                title: String(localized: .Tattoo.tipsVideoStep1Title),
                description: String(localized: .Tattoo.tipsVideoStep1Description)
            ),
            .init(
                step: String(localized: .Tattoo.tipsEvidenceStep2),
                title: String(localized: .Tattoo.tipsVideoStep2Title),
                description: String(localized: .Tattoo.tipsVideoStep2Description)
            ),
            .init(
                step: String(localized: .Tattoo.tipsEvidenceStep3),
                title: String(localized: .Tattoo.tipsVideoStep3Title),
                description: String(localized: .Tattoo.tipsVideoStep3Description)
            ),
            .init(
                step: String(localized: .Tattoo.tipsEvidenceStep4),
                title: String(localized: .Tattoo.tipsVideoStep4Title),
                description: String(localized: .Tattoo.tipsVideoStep4Description)
            )
        ]
    )
}
