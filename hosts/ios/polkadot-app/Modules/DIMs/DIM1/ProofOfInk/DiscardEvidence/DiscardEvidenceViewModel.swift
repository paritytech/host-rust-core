import Foundation

struct DiscardEvidenceViewModel {
    let title: String
    let description: String
    let mainAction: String
    let cancelAction: String
}

extension DiscardEvidenceViewModel {
    static let discardPhotoEvidence = DiscardEvidenceViewModel(
        title: String(localized: .Tattoo.discardPhotoTitle),
        description: String(localized: .Tattoo.discardPhotoDescription),
        mainAction: String(localized: .Tattoo.discardPhotoActionDiscard),
        cancelAction: String(localized: .Tattoo.discardPhotoActionCancel)
    )

    static let discardVideoEvidence = DiscardEvidenceViewModel(
        title: String(localized: .Tattoo.discardVideoTitle),
        description: String(localized: .Tattoo.discardVideoDescription),
        mainAction: String(localized: .Tattoo.discardVideoActionDiscard),
        cancelAction: String(localized: .Tattoo.discardVideoActionCancel)
    )
}
