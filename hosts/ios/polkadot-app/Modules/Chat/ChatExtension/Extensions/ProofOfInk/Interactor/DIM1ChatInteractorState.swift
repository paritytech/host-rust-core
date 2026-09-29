import Foundation
import AsyncExtensions
import SubstrateSdk
import CommonService
import Individuality

actor DIM1ChatInteractorState {
    typealias TattooFamilyProvider = (ProofOfInkPallet.FamilyIndex) async throws -> ProofOfInkPallet.FamilyId?

    // MARK: - External Data State

    private(set) var remoteState: DetermineStateSyncState?
    private(set) var personState: DetermineStatePersonData?
    private(set) var evidenceLocalState: EvidenceSubmission.LocalState?
    private(set) var evidenceSession: EvidenceSubmission.Session?
    private(set) var evidenceRecordingState: ProvideEvidenceState?
    private(set) var gameInfo: GameInfo?
    private(set) var offboardInProgress: Bool = false

    // MARK: - Deduplication State

    private var lastEmittedPersonId: PeoplePallet.PersonalId?
    private var lastEmittedFullUsername: Username?
    private var lastEmittedTattooComittedSince: BlockNumber?
    private var lastEmittedPhotoProvidedSince: BlockNumber?
    private var lastEmittedVideoProvidedSince: BlockNumber?

    // MARK: - Evidence State

    private var evidenceUploadingService: DIM1EvidenceSubmissionFacadeProtocol?
    private var evidenceFileTrackingTask: Task<Void, Never>?

    // MARK: - Callbacks

    private var onWidgetUpdate: ((DIM1WidgetState?) -> Void)?
    private var onMessageEvent: ((DIM1MessageEvent) -> Void)?
    private var evidenceUploadingServiceProvider: (() -> DIM1EvidenceSubmissionFacadeProtocol)?
    private var evidenceFileTrackingTaskProvider: ((ProofOfInkPallet.Candidate.Selected) -> Task<Void, Never>)?
    private var tattooFamilyProvider: TattooFamilyProvider?

    private let evidenceModelFactory: ProofOfInkChatEvidenceModelFactoryProtocol
    private let logger: LoggerProtocol

    // MARK: - Init

    init(
        evidenceModelFactory: ProofOfInkChatEvidenceModelFactoryProtocol,
        logger: LoggerProtocol
    ) {
        self.evidenceModelFactory = evidenceModelFactory
        self.logger = logger
    }

    // MARK: - Callback Setters

    func setOnWidgetUpdate(_ callback: ((DIM1WidgetState?) -> Void)?) {
        onWidgetUpdate = callback
    }

    func setOnMessageEvent(_ callback: ((DIM1MessageEvent) -> Void)?) {
        onMessageEvent = callback
    }

    func setEvidenceUploadingServiceProvider(_ callback: @escaping () -> DIM1EvidenceSubmissionFacadeProtocol) {
        evidenceUploadingServiceProvider = callback
    }

    func setEvidenceFileTrackingTaskProvider(_ callback: @escaping (ProofOfInkPallet.Candidate.Selected) -> Task<
        Void,
        Never
    >) {
        evidenceFileTrackingTaskProvider = callback
    }

    func setTattooFamilyProvider(_ callback: @escaping TattooFamilyProvider) {
        tattooFamilyProvider = callback
    }

    // MARK: - State Updates

    func updateRemoteState(_ newRemoteState: DetermineStateSyncState?) async {
        remoteState = newRemoteState

        updateEvidenceProgress()
        await updatePersonhoodProgress()
    }

    func updatePersonState(_ newPersonState: DetermineStatePersonData?) async {
        personState = newPersonState

        updateEvidenceProgress()
        await updatePersonhoodProgress()
    }

    func updateEvidenceLocalState(_ newEvidenceLocalState: EvidenceSubmission.LocalState?) async {
        evidenceLocalState = newEvidenceLocalState

        updateEvidenceProgress()
        await updatePersonhoodProgress()
    }

    func updateEvidenceSession(_ newEvidenceSession: EvidenceSubmission.Session?) {
        evidenceSession = newEvidenceSession

        updateEvidenceProgress()
    }

    func updateEvidenceRecordingState(_ recordingState: ProvideEvidenceState) async {
        evidenceRecordingState = recordingState

        guard let candidate = remoteState?.candidate else {
            return
        }

        await updateCandidateState(candidate: candidate)
    }

    func updateGameInfo(_ gameInfo: GameInfo?) async {
        self.gameInfo = gameInfo
        await updatePersonhoodProgress()
    }

    func retryUpload() async {
        await updatePersonhoodProgress()
        evidenceUploadingService?.retry()
    }

    func updateOffboard(inProgress: Bool) async {
        offboardInProgress = inProgress
        await updatePersonhoodProgress()
    }
}

private extension DIM1ChatInteractorState {
    func updatePersonhoodProgress() async {
        guard let remoteState, let personState else {
            onWidgetUpdate?(nil)
            return
        }

        if let registeredData = personState.makeRegisteredData() {
            guard case .proofOfInk = registeredData.source else {
                onWidgetUpdate?(nil)
                return
            }

            emitPersonhoodRegisteredIfNeeded(registeredData: registeredData)
            emitFullUsernameClaimedIfNeeded(registeredData: registeredData)

            if registeredData.fullUsername != nil {
                onWidgetUpdate?(.usernameClaimed)
            } else {
                onWidgetUpdate?(.fullUsernameRegistration(registeredData))
            }

            return
        }

        // Check if person is proof of ink one but not completed onboarding yet
        if remoteState.proofOfInkPerson != nil, remoteState.memberRingPosition?.isSuspended != true {
            onWidgetUpdate?(.evidenceApproved)
            return
        }

        if let candidate = remoteState.candidate {
            await updateCandidateState(candidate: candidate)
        } else {
            stopEvidenceUploadingService()
            let dim2State = resolveDIM2State()
            switch dim2State {
            case .notRegistered:
                onWidgetUpdate?(.applyForTattoo)
            case let .registered(offboardAvailable):
                onWidgetUpdate?(.switchToCurrentDim(possible: offboardAvailable, inProgress: offboardInProgress))
            }
        }
    }

    func updateEvidenceProgress() {
        guard
            let remoteState,
            let candidate = remoteState.candidate,
            case let .selected(selectedState) = candidate
        else {
            return
        }

        guard evidenceLocalState != nil || selectedState.judging != nil else {
            return
        }

        let input = ProofOfInkChatEvidenceModelFactoryInput(
            remoteState: remoteState,
            evidenceSession: evidenceLocalState != nil ? evidenceSession : nil
        )

        guard let model = evidenceModelFactory.makeViewModel(input: input) else {
            logger.error("Model creation failed")
            return
        }

        onMessageEvent?(.evidenceStateUpdate(
            selectedCandidate: selectedState,
            model: model
        ))
    }
}

// MARK: - Candidate State Resolution

private extension DIM1ChatInteractorState {
    func updateCandidateState(candidate: ProofOfInkPallet.Candidate) async {
        switch candidate {
        case .applied:
            stopEvidenceUploadingService()
            onWidgetUpdate?(.applyForTattoo)

        case let .selected(selectedState):
            await updateCandidateSelectedState(selectedState, evidenceLocalState: evidenceLocalState)

        case .proven:
            stopEvidenceUploadingService()

            onMessageEvent?(.evidenceApproved)
            onWidgetUpdate?(.evidenceApproved)
        }
    }

    func updateCandidateSelectedState(
        _ onChainState: ProofOfInkPallet.Candidate.Selected,
        evidenceLocalState: EvidenceSubmission.LocalState?
    ) async {
        do {
            guard let familyId = try await tattooFamilyProvider?(onChainState.design.familyIndex) else {
                logger.error("Tattoo not found for index: \(onChainState.design.familyIndex)")
                return
            }

            emitTattooCommitedIfNeeded(for: onChainState, familyId: familyId)

            guard evidenceLocalState == nil, onChainState.judging == nil else {
                startEvidenceUploadingServiceIfNeeded()
                emitPhotoProvidedIfNeeded(for: onChainState)
                onWidgetUpdate?(.evidenceProvided)
                return
            }

            stopEvidenceUploadingService()

            switch evidenceRecordingState {
            case .none,
                 .noEvidence,
                 .existingVideo:
                if evidenceFileTrackingTask == nil {
                    evidenceFileTrackingTask = evidenceFileTrackingTaskProvider?(onChainState)
                }

                onWidgetUpdate?(
                    .provideVideoEvidence(
                        design: onChainState.design,
                        familyId: familyId,
                        evidenceId: String(onChainState.since)
                    )
                )
            case .confirmedVideo:
                evidenceFileTrackingTask?.cancel()
                evidenceFileTrackingTask = nil

                emitVideoProvidedIfNeeded(for: onChainState)

                onWidgetUpdate?(
                    .providePhotoEvidence(
                        design: onChainState.design,
                        familyId: familyId,
                        evidenceId: String(onChainState.since)
                    )
                )
            }
        } catch {
            logger.error("Tattoo family fetch failed: \(error)")
        }
    }
}

// MARK: - Deduplication

private extension DIM1ChatInteractorState {
    func emitPersonhoodRegisteredIfNeeded(registeredData: People.RegisteredData) {
        guard case .proofOfInk = registeredData.source else {
            return
        }

        let personalId = registeredData.personId

        guard lastEmittedPersonId != personalId else {
            return
        }

        lastEmittedPersonId = personalId
        onMessageEvent?(.personhoodRegistered(personalId: personalId))
    }

    func emitFullUsernameClaimedIfNeeded(registeredData: People.RegisteredData) {
        guard case .proofOfInk = registeredData.source else {
            return
        }

        guard let fullUsername = registeredData.fullUsername else {
            return
        }

        guard lastEmittedFullUsername != fullUsername else {
            return
        }

        lastEmittedFullUsername = fullUsername

        let content = FullUsernameClaimedMessageDecoder.Content(
            liteUsername: registeredData.liteUsername,
            fullUsername: fullUsername
        )

        onMessageEvent?(.fullUsernameClaimed(content: content))
    }

    func emitTattooCommitedIfNeeded(
        for selectedCandidate: ProofOfInkPallet.Candidate.Selected,
        familyId: ProofOfInkPallet.FamilyId
    ) {
        guard selectedCandidate.since != lastEmittedTattooComittedSince else {
            return
        }

        lastEmittedTattooComittedSince = selectedCandidate.since

        onMessageEvent?(
            .tattooCommitted(
                selectedCandidate: selectedCandidate,
                familyId: familyId
            )
        )
    }

    func emitPhotoProvidedIfNeeded(for selectedCandidate: ProofOfInkPallet.Candidate.Selected) {
        guard selectedCandidate.since != lastEmittedPhotoProvidedSince else {
            return
        }

        lastEmittedPhotoProvidedSince = selectedCandidate.since

        onMessageEvent?(.photoConfirmed(selectedCandidate: selectedCandidate))
    }

    func emitVideoProvidedIfNeeded(for selectedCandidate: ProofOfInkPallet.Candidate.Selected) {
        guard selectedCandidate.since != lastEmittedVideoProvidedSince else {
            return
        }

        lastEmittedVideoProvidedSince = selectedCandidate.since

        onMessageEvent?(.videoRecordConfirmed(selectedCandidate: selectedCandidate))
    }
}

// MARK: - Evidence Service Control

private extension DIM1ChatInteractorState {
    func startEvidenceUploadingServiceIfNeeded() {
        guard evidenceUploadingService == nil else {
            return
        }

        logger.debug("Starting evidence submission service")

        evidenceUploadingService = evidenceUploadingServiceProvider?()
        evidenceUploadingService?.setup()
    }

    func stopEvidenceUploadingService() {
        guard evidenceUploadingService != nil else {
            return
        }

        logger.debug("Stoping evidence submission service")

        evidenceUploadingService?.throttle()
        evidenceUploadingService = nil
    }
}

// MARK: - DIM2 State Handling

private extension DIM1ChatInteractorState {
    enum DIM2StateResolution {
        case notRegistered
        case registered(offboardAvailable: Bool)
    }

    func resolveDIM2State() -> DIM2StateResolution {
        let exists = gameInfo?.isCrediblePlayer == true ||
            remoteState?.gameParticipant != nil

        guard exists else {
            return .notRegistered
        }

        let gameAllowsOffboard = gameInfo == nil ||
            gameInfo?.state == .registration

        let isRegistered = gameInfo?.isRegistered == true

        // We do not allow suspended users to offboard currently.
        // In the current impl on the pallet side it's not possible
        // to re-register an offboarded suspended user as person
        // with the same key using poi or game
        let isSuspended = remoteState?.gameParticipant?.recognition.isSuspended == true

        if gameAllowsOffboard, !isRegistered, !isSuspended {
            return .registered(offboardAvailable: true)
        } else {
            return .registered(offboardAvailable: false)
        }
    }
}
