import Foundation
import AsyncExtensions
import Individuality

enum DIM1WidgetState: Equatable {
    /// SwitchToCurrentDim (DIM1) / Terminate other one (DIM2)
    ///
    /// `possible` Defines possibility to offboard DIM2 in current state
    case switchToCurrentDim(possible: Bool, inProgress: Bool)
    case applyForTattoo
    case provideVideoEvidence(
        design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    )
    case providePhotoEvidence(
        design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    )
    case evidenceProvided
    case evidenceApproved
    case fullUsernameRegistration(People.RegisteredData)
    case usernameClaimed
}

enum DIM1MessageEvent {
    case tattooCommitted(
        selectedCandidate: ProofOfInkPallet.Candidate.Selected,
        familyId: ProofOfInkPallet.FamilyId
    )
    case videoRecordConfirmed(
        selectedCandidate: ProofOfInkPallet.Candidate.Selected
    )
    case photoConfirmed(
        selectedCandidate: ProofOfInkPallet.Candidate.Selected
    )
    case evidenceStateUpdate(
        selectedCandidate: ProofOfInkPallet.Candidate.Selected,
        model: ProofOfInkChatEvidenceModel
    )
    case evidenceApproved
    case personhoodRegistered(personalId: PeoplePallet.PersonalId)
    case fullUsernameClaimed(content: FullUsernameClaimedMessageDecoder.Content)
}

protocol DIM1ChatInteracting: AnyObject {
    func setup() async

    func observeWidgetState() -> AnyAsyncSequence<DIM1WidgetState?>

    func observeMessageEvents() -> AnyAsyncSequence<DIM1MessageEvent>

    func retryEvidenceUpload() async

    func switchToCurrentDim() async throws
}
