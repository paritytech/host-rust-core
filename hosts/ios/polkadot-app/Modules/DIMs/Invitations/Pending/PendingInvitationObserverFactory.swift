import SubstrateSdk
import Foundation
import ChainRegistry

protocol PendingInvitationObserverMaking {
    func makeObserver(
        ticketPublicKey: String,
        issuer: AccountAddress,
        of type: Invitation.InvitationType
    ) -> PendingInvitationObserving
}

final class PendingInvitationObserverFactory {
    let chainId: ChainModel.Id
    let chainRegistry: ChainRegistryProtocol
    let operationQueue: OperationQueue
    let logger: Logger

    init(
        chainId: ChainModel.Id,
        chainRegistry: ChainRegistryProtocol,
        operationQueue: OperationQueue,
        logger: Logger
    ) {
        self.chainId = chainId
        self.chainRegistry = chainRegistry
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension PendingInvitationObserverFactory: PendingInvitationObserverMaking {
    func makeObserver(
        ticketPublicKey: String,
        issuer: AccountAddress,
        of type: Invitation.InvitationType
    ) -> any PendingInvitationObserving {
        PendingInvitationObserver(
            type: type,
            ticketPublicKey: ticketPublicKey,
            issuer: issuer,
            chainId: chainId,
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}
