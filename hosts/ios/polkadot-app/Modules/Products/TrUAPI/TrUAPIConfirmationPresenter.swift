import Foundation
import Products
import TrUAPIHost

protocol TrUAPIConfirmationPresenting: Sendable {
    /// Present a confirmation for the core-reviewed action; returns user's
    /// decision. The requesting product identity is sourced from the review
    /// itself, so the presenter is product-agnostic and shared across the host
    /// and per-execution bridges.
    func confirm(review: UserConfirmationReview, from requesterName: String) async -> Bool
}

/// Routes core-reviewed actions to the native confirmation surfaces exposed
/// through `ProductRoutersFacadeProtocol`, keyed off the typed
/// `UserConfirmationReview` so the full payload reaches each prompt.
/// Cancellation-aware: the rust core dropping its future (e.g. the product
/// closed mid-prompt) resolves false immediately; an already presented prompt
/// stays up and its late decision is discarded.
final class TrUAPIConfirmationPresenter: TrUAPIConfirmationPresenting, @unchecked Sendable {
    private let routerFacade: ProductRoutersFacadeProtocol
    private let promptMapper: TrUAPIReviewPromptMapping
    private let logger: LoggerProtocol

    init(
        routerFacade: ProductRoutersFacadeProtocol,
        promptMapper: TrUAPIReviewPromptMapping = TrUAPIReviewPromptMapper(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.routerFacade = routerFacade
        self.promptMapper = promptMapper
        self.logger = logger
    }

    func confirm(review: UserConfirmationReview, from requesterName: String) async -> Bool {
        do {
            return try await dispatch(review: review, from: requesterName)
        } catch {
            logger.error("Failed to map confirmation review: \(error)")
            return false
        }
    }
}

private extension TrUAPIConfirmationPresenter {
    func dispatch(review: UserConfirmationReview, from requesterName: String) async throws -> Bool {
        switch review {
        case .signPayload,
             .signRaw,
             .createTransaction:
            try await confirmSigning(for: review, from: requesterName)
        case let .statementStoreProductSign(statementReview):
            await confirmStatementSign(
                promptMapper.makeStatementSignRequest(from: statementReview)
            )
        case let .identityDisclosure(identityReview):
            await confirmPermission(
                promptMapper.makePermissionRequest(from: identityReview)
            )
        case let .preimageSubmit(preimageReview):
            await confirmPermission(
                promptMapper.makePermissionRequest(from: preimageReview)
            )
        case let .accountAccess(accessReview):
            await confirmPermission(
                promptMapper.makePermissionRequest(from: accessReview)
            )
        case let .productSubtree(subtreeReview):
            await confirmPermission(
                promptMapper.makePermissionRequest(from: subtreeReview)
            )
        case let .accountAlias(aliasReview):
            await confirmPermission(
                promptMapper.makePermissionRequest(from: aliasReview)
            )
        case let .createProof(proofReview):
            try await confirmCreateProof(
                promptMapper.makeCreateProofRequest(from: proofReview)
            )
        case let .resourceAllocation(allocationReview):
            try await confirmAllowance(
                promptMapper.makeAllowanceRequest(from: allocationReview)
            )
        case let .signVrf(vrfReview):
            try await confirmSignVrf(
                promptMapper.makeSignVrfRequest(from: vrfReview)
            )
        }
    }

    /// Wraps the signing review as a confirm input and presents the sheet. The
    /// sheet renders the review directly (no wallet lookup); the rust core signs
    /// after approval.
    func confirmSigning(for review: UserConfirmationReview, from requesterName: String) async throws -> Bool {
        guard let input = ProductsSignConfirmInput(review: review) else {
            throw TrUAPIReviewMappingError.notASigningReview
        }

        return await presentSigning(input: input, requester: requesterName)
    }

    func presentSigning(input: ProductsSignConfirmInput, requester: ProductId) async -> Bool {
        await awaitDecision { [routerFacade] in
            await withCheckedContinuation { continuation in
                let context = ProductsSignConfirmContext(
                    requester: PolkadotSigningRequester(name: requester, iconUrl: nil),
                    input: input
                )
                context.setContinuation(continuation)
                routerFacade.productsRouter.showSignConfirmation(with: context)
            }
        }
    }

    func confirmStatementSign(_ request: StatementSignConfirmationRequest) async -> Bool {
        await awaitDecision { [routerFacade] in
            let decision: StatementSignDecision = await withCheckedContinuation { continuation in
                let context = StatementSignConfirmationContext(request: request)
                context.setContinuation(continuation)
                routerFacade.productsRouter.showStatementSignPrompt(context: context)
            }
            return decision == .approved
        }
    }

    func confirmPermission(_ request: TrUAPIPermissionRequest) async -> Bool {
        await awaitDecision { [routerFacade] in
            let decision: PermissionDecision = await withCheckedContinuation { continuation in
                let context = ProductPermissionContext(
                    productId: request.productId,
                    permissions: request.permissions
                )
                context.setContinuation(continuation)
                routerFacade.productsRouter.showPrompt(context: context)
            }

            switch decision {
            case .allowAlways,
                 .allowOnce:
                return true
            case .deny:
                return false
            }
        }
    }

    func confirmCreateProof(_ request: CreateProofConfirmationRequest) async -> Bool {
        await awaitDecision { [routerFacade] in
            let decision: CreateProofDecision = await withCheckedContinuation { continuation in
                let context = CreateProofConfirmationContext(request: request)
                context.setContinuation(continuation)
                routerFacade.productsRouter.showCreateProofPrompt(context: context)
            }
            return decision == .approved
        }
    }

    func confirmAllowance(_ request: TrUAPIAllowanceRequest) async -> Bool {
        await awaitDecision { [routerFacade] in
            let decision: AllowancePromptDecision = await withCheckedContinuation { continuation in
                let context = AllowancePromptContext(
                    productId: request.productId,
                    resources: request.resources
                )
                context.setContinuation(continuation)
                routerFacade.productsRouter.showAllowancePrompt(context: context)
            }
            return decision == .approved
        }
    }

    func confirmSignVrf(_ request: SignVrfConfirmationRequest) async -> Bool {
        await awaitDecision { [routerFacade] in
            let decision: SignVrfDecision = await withCheckedContinuation { continuation in
                let context = SignVrfConfirmationContext(request: request)
                context.setContinuation(continuation)
                routerFacade.productsRouter.showSignVrfPrompt(context: context)
            }
            return decision == .approved
        }
    }

    /// Bridges a prompt decision to the rust-core future, resolving exactly
    /// once. Rust-side cancellation resolves false without waiting for the
    /// prompt; a decision arriving afterwards is discarded.
    func awaitDecision(present: @escaping @MainActor () async -> Bool) async -> Bool {
        let pending = PendingDecision()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    guard pending.begin(continuation) else {
                        return
                    }
                    let verdict = await present()
                    pending.finish(verdict)
                }
            }
        } onCancel: {
            Task { @MainActor in pending.finish(false) }
        }
    }
}

/// Resume-once state for one confirmation. All mutable state is
/// MainActor-confined; a cancellation racing ahead of `begin` resolves the
/// incoming continuation with false instead of leaking it.
@MainActor
private final class PendingDecision {
    private var isFinished = false
    private var continuation: CheckedContinuation<Bool, Never>?

    nonisolated init() {}

    /// Returns false when the confirmation already finished (e.g. cancelled
    /// before the prompt task ran); the continuation is resolved either way.
    func begin(_ continuation: CheckedContinuation<Bool, Never>) -> Bool {
        guard !isFinished else {
            continuation.resume(returning: false)
            return false
        }
        self.continuation = continuation
        return true
    }

    func finish(_ verdict: Bool) {
        guard !isFinished else {
            return
        }
        isFinished = true
        continuation?.resume(returning: verdict)
        continuation = nil
    }
}
