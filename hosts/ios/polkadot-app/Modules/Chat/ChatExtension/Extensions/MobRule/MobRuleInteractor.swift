import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import Operation_iOS
import AsyncExtensions
import Individuality
import KeyDerivation
import ChainRegistry

protocol MobRuleInteracting: AnyObject {
    func setup() async
    func submitVote(
        for caseIndex: MobRulePallet.CaseIndex,
        with opinion: MobRulePallet.Judgement
    ) async throws
    func setCurrentCaseExpanded(isExpanded: Bool) async
    func markSensitiveAllow(for caseIndex: MobRulePallet.CaseIndex) async

    func observeWidgetState() -> AnyAsyncSequence<MobRuleWidgetState?>
    func observeSuccessfulVote() -> AnyAsyncSequence<MobRuleVote>
}

struct MobRuleWidgetState {
    let casesInfo: MobRuleCasesInfo
    let maxClaimableVotes: ClaimableVotesLimit
    let votedOnce: Bool
    let vottableCasesCount: Int
    let inProgressVote: MobRuleVote?
    let vottableCaseIndex: MobRulePallet.CaseIndex?
    let vottableCase: MobRulePallet.OpenCase?
    let vottableTattooFamilyId: ProofOfInkPallet.FamilyId?
    let vottableCaseIsExpanded: Bool
    let sensitiveContentAllowed: Bool
    let isSuspended: Bool

    var vottableCaseContext: MobRuleVottableCaseContext? {
        guard let caseIndex = vottableCaseIndex,
              let openCase = vottableCase else { return nil }
        return MobRuleVottableCaseContext(
            caseIndex: caseIndex,
            openCase: openCase,
            familyId: vottableTattooFamilyId,
            inProgressVote: inProgressVote,
            isExpanded: vottableCaseIsExpanded,
            sensitiveAllowed: sensitiveContentAllowed
        )
    }
}

enum MobRuleInteractorError: Error {
    case missingVottableCase
}

private actor MobRuleInteractorState {
    var casesInfo: MobRuleCasesInfo?
    var designFamilies: ProofOfInkPallet.DesignFamiliesResult?
    var maxClaimableVotes: ClaimableVotesLimit?
    var inProgressVote: MobRuleVote?
    var localVotedIndices = Set<MobRulePallet.CaseIndex>()
    var caseDescriptionExpanded: Bool = false
    var allowedSensitiveCases = Set<MobRulePallet.CaseIndex>()
    var isSuspended: Bool = false

    func updateCasesInfo(_ value: MobRuleCasesInfo) {
        casesInfo = value
    }

    func updateDesignFamilies(_ value: ProofOfInkPallet.DesignFamiliesResult) {
        designFamilies = value
    }

    func updateMaxClaimableVotes(_ value: ClaimableVotesLimit) {
        maxClaimableVotes = value
    }

    func updateInProgressVote(_ value: MobRuleVote?) {
        inProgressVote = value
    }

    func addLocalVotedIndex(_ value: MobRulePallet.CaseIndex) {
        localVotedIndices.insert(value)
    }

    func updateCaseDescriptionExpanded(_ value: Bool) {
        caseDescriptionExpanded = value
    }

    func addAllowedSensitiveCase(_ value: MobRulePallet.CaseIndex) {
        allowedSensitiveCases.insert(value)
    }

    func updateIsSuspended(_ value: Bool) {
        isSuspended = value
    }
}

final class MobRuleInteractor: RuntimeConstantFetching {
    private let chain: ChainModel
    private let caseCleanService: CleanCaseServicing
    private let connection: JSONRPCEngine
    private let runtimeProvider: RuntimeProviderProtocol
    private let proofOfInkFactory: ProofOfInkOperationFactoryProtocol
    private let mobRuleCasesFactory: MobRuleCasesOperationFactoryProtocol
    private let voteService: MobRuleVoteServicing
    private let scoreInfoSyncService: ScoreInfoSyncServicing
    private let logger: LoggerProtocol
    private let selectedWallet: WalletManaging
    private var caseCountSyncService: CaseCountSyncService?
    private var userVotesClaimService: UserVotesClaimsServicing?

    private let widgetStateSubject = AsyncCurrentValueSubject<MobRuleWidgetState?>(nil)
    private let successfulVoteSubject = AsyncPassthroughSubject<MobRuleVote>()

    private let state = MobRuleInteractorState()

    init(
        chain: ChainModel,
        caseCleanService: CleanCaseServicing,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol,
        voteService: MobRuleVoteServicing,
        scoreInfoSyncService: ScoreInfoSyncServicing,
        selectedWallet: WalletManaging = WalletManagerRepository.shared.mobRuleAlias(),
        mobRuleCasesFactory: MobRuleCasesOperationFactoryProtocol = MobRuleCasesOperationFactory(),
        proofOfInkFactory: ProofOfInkOperationFactoryProtocol = ProofOfInkOperationFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chain = chain
        self.selectedWallet = selectedWallet
        self.caseCleanService = caseCleanService
        self.connection = connection
        self.runtimeProvider = runtimeProvider
        self.mobRuleCasesFactory = mobRuleCasesFactory
        self.proofOfInkFactory = proofOfInkFactory
        self.voteService = voteService
        self.scoreInfoSyncService = scoreInfoSyncService
        self.logger = logger
    }
}

extension MobRuleInteractor: MobRuleInteracting {
    func setup() async {
        subscribeToCaseCount()
        provideDesignFamilies()
        fetchMaxClaimableVotes()
        subscribeToScoreInfo()
    }

    func submitVote(
        for caseIndex: MobRulePallet.CaseIndex,
        with opinion: MobRulePallet.Judgement
    ) async throws {
        Task {
            guard let openCase = await state.casesInfo?.openCases[caseIndex] else {
                logger.error("Missing vottable case")
                throw MobRuleInteractorError.missingVottableCase
            }

            let tattooFamilyId = await makeTattooFamilyId(
                designFamilies: state.designFamilies,
                openCase: openCase
            )

            let vote = MobRuleVote(
                caseIndex: caseIndex,
                openCase: openCase,
                opinion: opinion,
                tattooFamilyId: tattooFamilyId
            )

            logger.debug("Vote submitting will start with \(vote)")

            await state.updateInProgressVote(vote)
            await sendWidgetState()

            do {
                try await voteService.vote(with: vote)
                logger.debug("Vote submitted")
                await state.updateInProgressVote(nil)
                await state.addLocalVotedIndex(vote.caseIndex)
                await state.updateCaseDescriptionExpanded(false)
                await sendWidgetState()
                successfulVoteSubject.send(vote)
            } catch {
                logger.error("Vote submitting failed: \(error.localizedDescription)")
                await state.updateInProgressVote(nil)
                await sendWidgetState()
            }
        }
    }

    func setCurrentCaseExpanded(isExpanded: Bool) async {
        await state.updateCaseDescriptionExpanded(isExpanded)
        await sendWidgetState()
    }

    func markSensitiveAllow(for caseIndex: MobRulePallet.CaseIndex) async {
        await state.addAllowedSensitiveCase(caseIndex)
        await sendWidgetState()
    }

    func observeWidgetState() -> AnyAsyncSequence<MobRuleWidgetState?> {
        widgetStateSubject.eraseToAnyAsyncSequence()
    }

    func observeSuccessfulVote() -> AnyAsyncSequence<MobRuleVote> {
        successfulVoteSubject.eraseToAnyAsyncSequence()
    }
}

extension MobRuleInteractor: CaseCountSyncObserver {
    func caseCountDidUpdate(with _: MobRulePallet.CaseIndex) {
        providedFilteredCasesForUser()
        provideDesignFamilies()
    }

    func caseCountSubscriptionFailed(with error: Error) {
        logger.error("Case count subscription failed: \(error.localizedDescription)")
    }
}

private extension MobRuleInteractor {
    func subscribeToCaseCount() {
        caseCountSyncService = .init(
            connection: connection,
            runtimeService: runtimeProvider,
            observers: [self],
            workQueue: .global()
        )

        caseCountSyncService?.setup()
    }

    func providedFilteredCasesForUser() {
        Task {
            guard let account = try? selectedWallet.fetchAccount(for: chain) else {
                return
            }

            let wrapper = mobRuleCasesFactory.fetchCasesInfo(
                for: connection,
                runtimeProvider: runtimeProvider,
                aliasAccountId: account.accountId
            )

            do {
                try await state.updateCasesInfo(wrapper.asyncExecute())
                await sendWidgetState()
            } catch {
                logger.error("Retrieve cases failed: \(error.localizedDescription)")
            }
        }
    }

    func provideDesignFamilies() {
        Task {
            let wrapper = proofOfInkFactory.fetchAllFamilies(
                for: connection,
                runtimeProvider: runtimeProvider
            )

            do {
                try await state.updateDesignFamilies(wrapper.asyncExecute())
                await sendWidgetState()
            } catch {
                logger.error("Design families failed: \(error.localizedDescription)")
            }
        }
    }

    func subscribeToScoreInfo() {
        Task { [scoreInfoSyncService, logger] in
            do {
                for try await scoreInfo in scoreInfoSyncService.observe() {
                    let isSuspended = scoreInfo?.isSuspended == true
                    await state.updateIsSuspended(isSuspended)
                    await sendWidgetState()
                }
            } catch {
                logger.error("Score info subscription failed: \(error)")
            }
        }
    }

    func fetchMaxClaimableVotes() {
        Task {
            do {
                let operation = PrimitiveConstantOperation<ClaimableVotesLimit>(
                    oneOfPaths: [MobRulePallet.maxVotesClaimable],
                    fallbackValue: nil
                )
                operation.codingFactory = try await runtimeProvider
                    .fetchCoderFactoryOperation()
                    .asyncExecute()

                try await state.updateMaxClaimableVotes(operation.asyncExecute())
                await sendWidgetState()
            } catch {
                logger.error("Max claimable votes failed: \(error.localizedDescription)")
            }
        }
    }

    func sendWidgetState() async {
        guard
            let casesInfo = await state.casesInfo,
            let designFamilies = await state.designFamilies,
            let maxClaimableVotes = await state.maxClaimableVotes
        else {
            widgetStateSubject.send(nil)
            return
        }

        let localVotedIndices = await state.localVotedIndices
        let inProgressVote = await state.inProgressVote
        let caseDescriptionExpanded = await state.caseDescriptionExpanded
        let allowedSensitiveCases = await state.allowedSensitiveCases

        let vottableCases = casesInfo.openCases
            .filter { key, _ in !casesInfo.userVotes.contains(key) && !localVotedIndices.contains(key) }
            .sorted { $0.key < $1.key }
        let vottableCaseIndex = vottableCases.first?.key
        let vottableCase = vottableCases.first?.value
        let vottableTattooFamilyId = makeTattooFamilyId(
            designFamilies: designFamilies,
            openCase: vottableCase
        )

        let sensitiveContentAllowed = vottableCaseIndex.map { allowedSensitiveCases.contains($0) } ?? false

        let votedOnce = !localVotedIndices.isEmpty || !casesInfo.userVotes.isEmpty
        let isSuspended = await state.isSuspended

        widgetStateSubject.send(.init(
            casesInfo: casesInfo,
            maxClaimableVotes: maxClaimableVotes,
            votedOnce: votedOnce,
            vottableCasesCount: vottableCases.count,
            inProgressVote: inProgressVote,
            vottableCaseIndex: vottableCaseIndex,
            vottableCase: vottableCase,
            vottableTattooFamilyId: vottableTattooFamilyId,
            vottableCaseIsExpanded: caseDescriptionExpanded,
            sensitiveContentAllowed: sensitiveContentAllowed,
            isSuspended: isSuspended
        ))
    }

    func makeTattooFamilyId(
        designFamilies: ProofOfInkPallet.DesignFamiliesResult?,
        openCase: MobRulePallet.OpenCase?
    ) -> ProofOfInkPallet.FamilyId? {
        guard
            let designFamilies,
            let openCase,
            case let .proofOfInk(value) = openCase.details.statement
        else {
            return nil
        }
        let key = ProofOfInkPallet.DesignFamiliesKey(index: value.design.familyIndex)
        return designFamilies[key]?.id
    }
}
