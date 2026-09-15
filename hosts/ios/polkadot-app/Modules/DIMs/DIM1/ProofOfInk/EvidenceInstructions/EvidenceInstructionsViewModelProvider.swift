import Foundation
import PolkadotUI
import SwiftUI

protocol EvidenceInstructionsViewModelProviderProtocol {
    func createViewModel() -> InstructionSheetViewModel
}

final class EvidenceInstructionsViewModelProvider: EvidenceInstructionsViewModelProviderProtocol {
    let mode: EvidenceInstructionsMode

    init(mode: EvidenceInstructionsMode) {
        self.mode = mode
    }

    func createViewModel() -> InstructionSheetViewModel {
        switch mode {
        case .photo:
            createPhotoViewModel()
        case .video:
            createVideoViewModel()
        }
    }
}

private extension EvidenceInstructionsViewModelProvider {
    func createPhotoViewModel() -> InstructionSheetViewModel {
        let items = [
            InstructionItem(
                title: String(localized: .Tattoo.instructionSheetPhotoStep1Title),
                detail: String(localized: .Tattoo.instructionSheetPhotoStep1Description)
            ),
            InstructionItem(
                title: String(localized: .Tattoo.instructionSheetPhotoStep2Title),
                detail: String(localized: .Tattoo.instructionSheetPhotoStep2Description)
            ),
            InstructionItem(
                title: String(localized: .Tattoo.instructionSheetPhotoStep3Title),
                detail: String(localized: .Tattoo.instructionSheetPhotoStep3Description)
            )
        ]
        return InstructionSheetViewModel(
            title: String(localized: .Tattoo.instructionSheetPhotoTitle),
            items: items,
            glyphImage: Image(.evidenceInfoPhoto),
            primaryButtonTitle: String(localized: .Tattoo.instructionPhotoPrimaryButton)
        )
    }

    func createVideoViewModel() -> InstructionSheetViewModel {
        let items = [
            InstructionItem(
                title: String(localized: .Tattoo.instructionSheetVideoStep1Title),
                detail: String(localized: .Tattoo.instructionSheetVideoStep1Description)
            ),
            InstructionItem(
                title: String(localized: .Tattoo.instructionSheetVideoStep2Title),
                detail: String(localized: .Tattoo.instructionSheetVideoStep2Description)
            ),
            InstructionItem(
                title: String(localized: .Tattoo.instructionSheetVideoStep3Title),
                detail: String(localized: .Tattoo.instructionSheetVideoStep3Description)
            ),
            InstructionItem(
                title: String(localized: .Tattoo.instructionSheetVideoStep4Title),
                detail: String(localized: .Tattoo.instructionSheetVideoStep4Description)
            ),
            InstructionItem(
                title: String(localized: .Tattoo.instructionSheetVideoStep5Title),
                detail: String(localized: .Tattoo.instructionSheetVideoStep5Description)
            ),
            InstructionItem(
                title: String(localized: .Tattoo.instructionSheetVideoStep6Title),
                detail: String(localized: .Tattoo.instructionSheetVideoStep6Description)
            )
        ]
        return InstructionSheetViewModel(
            title: String(localized: .Tattoo.instructionSheetVideoTitle),
            items: items,
            glyphImage: Image(.evidenceInfoVideo),
            primaryButtonTitle: String(localized: .Tattoo.instructionVideoPrimaryButton)
        )
    }
}
