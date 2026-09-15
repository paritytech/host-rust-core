import Foundation
import SubstrateSdk
import CommonService
import SubstrateStorageSubscription
import Individuality
import ChainRegistry

protocol PendingInvitationObserving: BaseObservableStateStore<Bool>, ApplicationServiceProtocol {}

final class PendingInvitationObserver: BaseObservableStateStore<Bool> {
    let chainId: ChainModel.Id
    let chainRegistry: ChainRegistryProtocol

    let operationQueue: OperationQueue
    let workingQueue: DispatchQueue

    let ticketPublicKey: String
    let issuer: AccountAddress

    let storagePath: StorageCodingPath

    private var subscription: CallbackBatchStorageSubscription<PendingInvitationTracking.InvitationChange>?

    init(
        type: Invitation.InvitationType,
        ticketPublicKey: String,
        issuer: AccountAddress,
        chainId: ChainModel.Id,
        chainRegistry: ChainRegistryProtocol,
        operationQueue: OperationQueue,
        logger: Logger
    ) {
        switch type {
        case .game:
            storagePath = GamePallet.pendingInvites
        case .tattoo:
            storagePath = ProofOfInkPallet.pendingInvites
        }
        self.ticketPublicKey = ticketPublicKey
        self.issuer = issuer
        self.chainId = chainId
        self.chainRegistry = chainRegistry
        self.operationQueue = operationQueue
        workingQueue = DispatchQueue(label: "PendingInvitationObserver.workingQueue")

        super.init(logger: logger)
    }
}

extension PendingInvitationObserver: PendingInvitationObserving {
    func setup() {
        workingQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard subscription == nil else {
                return
            }

            subscribeToPendingInvites()
        }
    }

    func throttle() {
        workingQueue.async { [weak self] in
            guard let self else {
                return
            }

            subscription?.unsubscribe()
            subscription = nil
        }
    }
}

extension PendingInvitationObserver {
    func subscribeToPendingInvites() {
        do {
            let ticketId = try Data(hexString: ticketPublicKey)
            let issuerId = try issuer.toAccountId()
            let connection = try chainRegistry.getConnectionOrError(for: chainId)
            let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chainId)

            subscription = CallbackBatchStorageSubscription(
                requests: [
                    createPendingInvitesSubscriptionRequest(ticket: ticketId, issuer: issuerId)
                ],
                connection: connection,
                runtimeService: runtimeProvider,
                repository: nil,
                operationQueue: operationQueue,
                callbackQueue: workingQueue
            ) { [weak self] result in
                self?.mutex.lock()

                defer {
                    self?.mutex.unlock()
                }

                switch result {
                case let .success(changes):
                    self?.logger.debug("Pending invites updated: \(changes)")
                    self?.stateObservable.state = .init(changes.inviteIssued)
                case let .failure(error):
                    self?.logger.error("Unexpected points subscription error: \(error)")
                }
            }

            subscription?.subscribe()
        } catch {
            logger.error("Error while subscribing to pending invites: \(error)")
        }
    }

    private func createPendingInvitesSubscriptionRequest(
        ticket: AccountId,
        issuer: AccountId
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: DoubleMapSubscriptionRequest(
                storagePath: storagePath,
                localKey: "",
                keyParamClosure: {
                    (
                        BytesCodable(wrappedValue: issuer),
                        BytesCodable(wrappedValue: ticket)
                    )
                }
            ),
            mappingKey: nil
        )
    }
}
