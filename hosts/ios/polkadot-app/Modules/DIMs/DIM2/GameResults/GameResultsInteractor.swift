import Foundation
import SubstrateSdk
import Operation_iOS
import OperationExt
import Individuality
import CommonService

@MainActor
final class GameResultsInteractor {
    weak var presenter: GameResultsInteractorOutputProtocol?

    private let dependencies: GameResultsDependencies
    private let usernameValidator: FullUsernameAvailabilityValidating
    private let logger: LoggerProtocol

    private let attestationTotal = 10
    private let passThreshold = 6

    private var context: ReportSuccessContext?
    private var lastInput: GameResultsInput?
    private var pushedHashes = Set<Data>()
    private var didAttend = false
    private var didCompletePack = false
    private var task: Task<Void, Never>?
    private var personObserverToken: NSObject?

    init(
        dependencies: GameResultsDependencies,
        usernameValidator: FullUsernameAvailabilityValidating = FullUsernameAvailabilityValidator(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.dependencies = dependencies
        self.usernameValidator = usernameValidator
        self.logger = logger
    }

    deinit {
        task?.cancel()
        if let token = personObserverToken {
            dependencies.personDataStore.remove(observer: token)
        }
        dependencies.nftsSubscriptionService.cancel()
    }
}

extension GameResultsInteractor: GameResultsInteractorInputProtocol {
    func start(context: ReportSuccessContext) {
        guard self.context == nil else {
            logger.debug("[GameDebug] interactor.start ignored — already started")
            return
        }
        self.context = context
        logger
            .debug(
                "[GameDebug] interactor.start gameIndex=\(context.gameIndex) " +
                    "player=\(context.player.rawTypeValue) " +
                    "blockHash=\(context.reportBlockHash?.toHex(includePrefix: true) ?? "nil") " +
                    "wasPerson=\(context.wasPersonBeforeReport) " +
                    "snapshot.maxGroupSize=\(context.gameSnapshot.maxGroupSize) " +
                    "snapshot.playerCount=\(context.gameSnapshot.playerCount) " +
                    "claimBeneficiary=\(context.claimBeneficiary.toHex(includePrefix: true).prefix(12))… " +
                    "claimUsesScoreAlias=\(context.claimUsesScoreAlias)"
            )
        task?.cancel()
        task = Task { [weak self] in
            await self?.run(context: context)
        }
    }

    func stop() {
        logger.debug("[GameDebug] interactor.stop — cancelling task + removing person observer")
        task?.cancel()
        task = nil
        if let token = personObserverToken {
            dependencies.personDataStore.remove(observer: token)
            personObserverToken = nil
        }
        dependencies.nftsSubscriptionService.cancel()
    }

    func resolveUsernameAvailability(
        name: String
    ) async -> GameResultsInput.UsernameClaim.Availability {
        do {
            let result = try await usernameValidator.checkAvailability(for: Username(value: name))
            let availability: GameResultsInput.UsernameClaim.Availability =
                switch result {
                case .free,
                     .reservedByUs,
                     .reclaimExpiredReservation:
                    .available
                case .notAvailable:
                    .taken
                }
            logger.debug("[GameDebug] username '\(name)' raw=\(result) mapped=\(availability)")
            return availability
        } catch {
            logger.error("[GameDebug] username '\(name)' check FAILED: \(error)")
            return .unknown
        }
    }

    func submitClaim() {
        guard let context else {
            logger.warning("[GameDebug] submitClaim ignored — no context")
            return
        }
        // swiftlint:disable closure_parameter_position
        Task { [
            logger,
            claimService = dependencies.claimService,
            store = dependencies.airdropRegistrationStore,
            context
        ] in
            // Prefer the method persisted at registration; fall back to the report context only when
            // no record exists (e.g. registered before this was introduced).
            let registration = try? await store.record(forGameIndex: context.gameIndex)
            let beneficiary = registration?.beneficiary ?? context.claimBeneficiary
            let usesScoreAlias = registration?.usesScoreAlias ?? context.claimUsesScoreAlias
            let gameIndex = context.gameIndex

            logger.debug(
                "[GameDebug] submitClaim START gameIndex=\(gameIndex) " +
                    "beneficiary=\(beneficiary.toHex(includePrefix: true).prefix(12))… " +
                    "usesScoreAlias=\(usesScoreAlias) restoredFromRegistration=\(registration != nil)"
            )

            let wrapper = claimService.submitClaim(
                gameIndex: gameIndex,
                beneficiary: beneficiary,
                usesScoreAlias: usesScoreAlias
            )
            do {
                let result = try await wrapper.asyncExecute()
                switch result.status {
                case let .success(extrinsic):
                    logger.debug(
                        "[GameDebug] submitClaim SUCCESS gameIndex=\(gameIndex) hash=\(extrinsic.extrinsicHash)"
                    )
                case let .failure(failed):
                    logger.error(
                        "[GameDebug] submitClaim DISPATCH FAILED gameIndex=\(gameIndex) error=\(failed.error)"
                    )
                }
            } catch {
                logger.error("[GameDebug] submitClaim FAILED gameIndex=\(gameIndex) error=\(error)")
            }
        }
        // swiftlint:enable closure_parameter_position
    }
}

private extension GameResultsInteractor {
    func run(context: ReportSuccessContext) async {
        logger.debug("[GameDebug] pipeline.run START — kicking off parallel roster + prize fetch")

        async let candidatesAsync = fetchCandidates(context: context)
        async let prizeAsync = fetchPrize(context: context)
        async let attendedAsync = fetchAttended(context: context)
        let candidates = await candidatesAsync
        let prize = await prizeAsync
        didAttend = await attendedAsync

        let initialMinted = await fetchInitialMinted(context: context, candidates: candidates)

        logger
            .debug(
                "[GameDebug] pipeline.run roster+prize ready " +
                    "candidates=\(candidates.hashes.count) " +
                    "expectedPeerRounds=\(candidates.expectedPeerRounds) " +
                    "prize.present=\(prize != nil) " +
                    "prize.won=\(prize?.won.description ?? "nil")"
            )

        logger
            .debug(
                "[GameDebug] subscribing to NFT mints with \(candidates.hashes.count) candidate hashes"
            )
        let mintStream = dependencies.nftsSubscriptionService.observeMints(
            player: context.player,
            candidates: candidates.hashes
        )

        let initialState = dependencies.personDataStore.currentState
        let initialRegistered = initialState?.makeRegisteredData()
        logger
            .debug(
                "[GameDebug] initial personDataStore snapshot " +
                    "isRegistered=\(initialRegistered != nil) " +
                    "hasReachedPersonhood=\(initialState?.hasReachedPersonhood ?? false) " +
                    "hasFullUsername=\(initialRegistered?.fullUsername != nil) " +
                    "liteUsername=\(initialRegistered?.liteUsername.value ?? "nil")"
            )
        let initial = makeInput(
            context: context,
            candidates: candidates,
            prize: prize,
            matchedHashes: initialMinted,
            personData: initialState
        )
        logger
            .debug(
                "[GameDebug] initial input built " +
                    "score=\(String(describing: initial.attestations.score))/\(initial.attestations.total) " +
                    "passed=\(String(describing: initial.attestations.passed)) " +
                    "matchedHashes=\(initial.attestationHashes.count) " +
                    "member.justBecameMember=\(initial.member.justBecameMember) " +
                    "member.displayName=\(initial.member.displayName ?? "nil") " +
                    "prizeDraw.present=\(initial.prizeDraw != nil) " +
                    "usernameClaim.eligible=\(initial.usernameClaim.eligible) " +
                    "usernameClaim.suggested=\(initial.usernameClaim.suggestedUsername ?? "nil")"
            )
        logger.debug("[GameDebug] → deliver(initial) baseline + outcome")
        deliver(initial)

        subscribeToPersonStore(context: context, candidates: candidates, prize: prize)

        for hash in initialMinted {
            await handleMint(hash)
        }
        await completePackOnPass(context: context, candidates: candidates, prize: prize)

        logger.debug("[GameDebug] starting mint stream consumer loop")
        do {
            for try await hash in mintStream {
                guard !Task.isCancelled else {
                    logger.debug("[GameDebug] mint loop break — task cancelled")
                    break
                }
                await handleMint(hash)
                await refreshAttendanceIfNeeded(context: context, candidates: candidates, prize: prize)
                await completePackOnPass(context: context, candidates: candidates, prize: prize)
            }
        } catch {
            logger.error("[GameDebug] mint stream error: \(error)")
        }
        logger.debug("[GameDebug] mint stream ended totalPushed=\(pushedHashes.count)")
    }

    func handleMint(_ hash: Data) async {
        guard pushedHashes.insert(hash).inserted else {
            logger.debug("[GameDebug] mint duplicate skip hash=\(hash.toHex().prefix(12))…")
            return
        }
        logger
            .debug(
                "[GameDebug] mint matched #\(pushedHashes.count) hash=\(hash.toHex()) " +
                    "→ presenter.didReceiveAttestation"
            )
        presenter?.didReceiveAttestation(hash: hash)
    }

    func refreshAttendanceIfNeeded(
        context: ReportSuccessContext,
        candidates: GameAttestationCandidates,
        prize: AirdropPrizeReport?
    ) async {
        guard !didAttend else { return }
        let attended = await fetchAttended(context: context)
        guard attended else { return }
        didAttend = true
        logger.debug("[GameDebug] attendance confirmed on-chain mid-stream")
        let updated = makeInput(
            context: context,
            candidates: candidates,
            prize: prize,
            matchedHashes: Array(pushedHashes),
            personData: dependencies.personDataStore.currentState
        )
        deliver(updated)
    }

    func completePackOnPass(
        context: ReportSuccessContext,
        candidates: GameAttestationCandidates,
        prize: AirdropPrizeReport?
    ) async {
        guard !didCompletePack else { return }
        guard pushedHashes.count >= passThreshold else { return }
        didCompletePack = true
        logger
            .debug(
                "[GameDebug] pass reached (\(pushedHashes.count) >= \(passThreshold)) — completing pack from nftCandidates"
            )

        do {
            let pending = try await dependencies.nftsSubscriptionService.fetchPendingHashes(player: context.player)
            for hash in pending {
                guard pushedHashes.count < attestationTotal else { break }
                await handleMint(hash) // dedupes against already-confirmed/pushed hashes
            }
        } catch {
            logger
                .error(
                    "[GameDebug] completePackOnPass: pending fetch failed: \(error) — relying on the mint stream for the tail"
                )
        }
        logger.debug("[GameDebug] pack completed on pass → \(pushedHashes.count)/\(attestationTotal)")

        let updated = makeInput(
            context: context,
            candidates: candidates,
            prize: prize,
            matchedHashes: Array(pushedHashes),
            personData: dependencies.personDataStore.currentState
        )
        deliver(updated)
    }

    func subscribeToPersonStore(
        context: ReportSuccessContext,
        candidates: GameAttestationCandidates,
        prize: AirdropPrizeReport?
    ) {
        let token = NSObject()
        personObserverToken = token
        logger.debug("[GameDebug] subscribing to personDataStore observer")
        dependencies.personDataStore.add(
            observer: token,
            sendStateOnSubscription: false,
            queue: .main
        ) { [weak self, logger] _, newState in
            logger
                .debug(
                    "[GameDebug] personDataStore CHANGE " +
                        "hasReachedPersonhood=\(newState?.hasReachedPersonhood ?? false) " +
                        "isRegistered=\(newState?.makeRegisteredData() != nil) " +
                        "hasFullUsername=\(newState?.makeRegisteredData()?.fullUsername != nil)"
                )
            guard let self else { return }
            Task { @MainActor in
                self.handlePersonState(
                    newState,
                    context: context,
                    candidates: candidates,
                    prize: prize
                )
            }
        }
    }

    func handlePersonState(
        _ state: DetermineStatePersonData?,
        context: ReportSuccessContext,
        candidates: GameAttestationCandidates,
        prize: AirdropPrizeReport?
    ) {
        guard let lastInput else {
            logger.debug("[GameDebug] handlePersonState skipped — no lastInput yet")
            return
        }
        let registered = state?.makeRegisteredData()
        let hasReachedPersonhood = state?.hasReachedPersonhood ?? false
        let member = makeMember(
            context: context,
            registered: registered,
            hasReachedPersonhood: hasReachedPersonhood
        )
        let usernameClaim = makeUsernameClaim(registered: registered)
        guard member != lastInput.member || usernameClaim != lastInput.usernameClaim else {
            logger
                .debug(
                    "[GameDebug] handlePersonState — no diff vs lastInput, skip re-push"
                )
            return
        }
        logger
            .debug(
                "[GameDebug] person state changed — diff detected\n" +
                    "  member.justBecameMember: \(lastInput.member.justBecameMember) → " +
                    "\(member.justBecameMember)\n" +
                    "  member.displayName: \(lastInput.member.displayName ?? "nil") → " +
                    "\(member.displayName ?? "nil")\n" +
                    "  usernameClaim.eligible: \(lastInput.usernameClaim.eligible) → " +
                    "\(usernameClaim.eligible)\n" +
                    "  usernameClaim.suggested: \(lastInput.usernameClaim.suggestedUsername ?? "nil") → " +
                    "\(usernameClaim.suggestedUsername ?? "nil")"
            )
        let updated = makeInput(
            context: context,
            candidates: candidates,
            prize: prize,
            matchedHashes: Array(pushedHashes),
            personData: state
        )
        logger.debug("[GameDebug] → deliver(updated) baseline + outcome (person state changed)")
        deliver(updated)
    }
}

private extension GameResultsInteractor {
    func fetchCandidates(context: ReportSuccessContext) async -> GameAttestationCandidates {
        do {
            return try await dependencies.groupRosterService.fetchAttestationCandidates(
                gameIndex: context.gameIndex,
                attestee: context.player,
                maxGroupSize: context.gameSnapshot.maxGroupSize,
                playerCount: context.gameSnapshot.playerCount,
                blockHash: context.reportBlockHash
            )
        } catch {
            logger.error("[GameDebug] roster fetch FAILED: \(error)")
            return GameAttestationCandidates(hashes: [], expectedPeerRounds: 0)
        }
    }

    func fetchPrize(context: ReportSuccessContext) async -> AirdropPrizeReport? {
        do {
            return try await dependencies.prizeService.fetchReport(
                gameIndex: context.gameIndex,
                player: context.player,
                blockHash: context.reportBlockHash
            )
        } catch {
            logger.error("[GameDebug] airdrop read FAILED: \(error)")
            return nil
        }
    }

    func fetchAttended(context: ReportSuccessContext) async -> Bool {
        do {
            return try await dependencies.nftsSubscriptionService.fetchDidAttend(
                player: context.player,
                gameIndex: context.gameIndex
            )
        } catch {
            logger.error("[GameDebug] attendance read FAILED: \(error)")
            return false
        }
    }

    func fetchInitialMinted(
        context: ReportSuccessContext,
        candidates: GameAttestationCandidates
    ) async -> [Data] {
        guard !candidates.hashes.isEmpty else { return [] }
        do {
            let minted = try await dependencies.nftsSubscriptionService.fetchMintedHashes(
                player: context.player,
                candidates: candidates.hashes
            )
            logger.debug(
                "[GameDebug] pre-fetch minted=\(minted.count)/\(candidates.hashes.count) " +
                    "→ silhouette count"
            )
            return minted
        } catch {
            logger.error("[GameDebug] pre-fetch minted FAILED: \(error)")
            return []
        }
    }
}

private extension GameResultsInteractor {
    func deliver(_ full: GameResultsInput) {
        lastInput = full
        presenter?.didReceiveResults(baselineInput(from: full))

        let outcome = makeOutcome(from: full)
        guard outcome.passed else {
            logger.debug(
                "[GameDebug] outcome withheld — not (yet) passed (< \(passThreshold)); no setGameOutcome sent"
            )
            return
        }
        logger.debug("[GameDebug] → didReceiveOutcome passed=true")
        presenter?.didReceiveOutcome(outcome)
    }

    func baselineInput(from full: GameResultsInput) -> GameResultsInput {
        GameResultsInput(
            attestations: GameResultsInput.Attestations(
                score: nil,
                total: full.attestations.total,
                passed: nil
            ),
            member: full.member,
            prizeDraw: full.prizeDraw,
            usernameClaim: full.usernameClaim,
            onPrizeClaim: full.onPrizeClaim,
            attestationHashes: full.attestationHashes
        )
    }

    func makeOutcome(from full: GameResultsInput) -> GameOutcome {
        GameOutcome(
            passed: full.attestations.passed ?? false,
            justBecameMember: full.member.justBecameMember,
            prizeDraw: full.prizeDraw,
            usernameClaim: full.usernameClaim
        )
    }

    func makeInput(
        context: ReportSuccessContext,
        candidates: GameAttestationCandidates,
        prize: AirdropPrizeReport?,
        matchedHashes: [Data],
        personData: DetermineStatePersonData?
    ) -> GameResultsInput {
        let collectiblesEarned = min(matchedHashes.count, attestationTotal)
        let passed = collectiblesEarned >= passThreshold
        let matchedHexes = matchedHashes.prefix(attestationTotal).map { $0.toHex() }

        let registered = personData?.makeRegisteredData()
        let hasReachedPersonhood = personData?.hasReachedPersonhood ?? false

        logger
            .debug(
                "[GameDebug] attestations: score=\(collectiblesEarned) " +
                    "minted=\(matchedHashes.count) passed=\(passed) (real>=\(passThreshold)) " +
                    "didAttend=\(didAttend) hasReachedPersonhood=\(hasReachedPersonhood) " +
                    "expectedPeerRounds=\(candidates.expectedPeerRounds)"
            )

        let attestations = GameResultsInputBuilder.AttestationsData(
            score: collectiblesEarned,
            total: attestationTotal,
            passed: passed,
            hashes: matchedHexes
        )

        let eligiblePrize = (didAttend && hasReachedPersonhood) ? prize : nil

        logger
            .debug(
                "[GameDebug] prize gate: didAttend=\(didAttend) hasReachedPersonhood=\(hasReachedPersonhood) " +
                    "prize.present=\(prize != nil) prize.won=\(prize?.won.description ?? "nil") " +
                    "→ eligiblePrize=\(eligiblePrize != nil) (prize decoupled from NFT pass)"
            )

        let member = makeMember(
            context: context,
            registered: registered,
            hasReachedPersonhood: hasReachedPersonhood
        )
        let usernameClaim = makeUsernameClaim(registered: registered)

        return GameResultsInputBuilder.build(
            attestations: attestations,
            member: member,
            prize: eligiblePrize,
            usernameClaim: usernameClaim,
            onPrizeClaim: { [weak self] in
                self?.submitClaim()
            }
        )
    }

    func makeMember(
        context: ReportSuccessContext,
        registered: People.RegisteredData?,
        hasReachedPersonhood: Bool
    ) -> GameResultsInput.MemberState {
        let justBecameMember = !context.wasPersonBeforeReport && hasReachedPersonhood

        logger
            .debug(
                "[GameDebug] member gate: wasPersonBeforeReport=\(context.wasPersonBeforeReport) " +
                    "hasReachedPersonhood=\(hasReachedPersonhood) → justBecameMember=\(justBecameMember)"
            )

        let displayName = registered?.fullUsername?.value
            ?? dependencies.usernameStorage.username?.value

        return GameResultsInput.MemberState(
            justBecameMember: justBecameMember,
            displayName: displayName,
            memberSince: nil
        )
    }

    func makeUsernameClaim(
        registered: People.RegisteredData?
    ) -> GameResultsInput.UsernameClaim {
        guard let registered else {
            return GameResultsInput.UsernameClaim(
                eligible: false,
                suggestedUsername: nil,
                previousUsername: nil,
                availability: nil,
                alternatives: nil
            )
        }
        if registered.fullUsername != nil {
            return GameResultsInput.UsernameClaim(
                eligible: false,
                suggestedUsername: nil,
                previousUsername: registered.fullUsername?.value,
                availability: nil,
                alternatives: nil
            )
        }
        let base = registered.liteUsername.partialUsername
        guard !base.isEmpty else {
            return GameResultsInput.UsernameClaim(
                eligible: false,
                suggestedUsername: nil,
                previousUsername: registered.liteUsername.value,
                availability: nil,
                alternatives: nil
            )
        }
        return GameResultsInput.UsernameClaim(
            eligible: true,
            suggestedUsername: base,
            previousUsername: registered.liteUsername.value,
            availability: nil,
            alternatives: nil
        )
    }
}
