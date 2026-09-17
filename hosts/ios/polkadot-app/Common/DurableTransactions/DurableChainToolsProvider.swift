import ChainRegistry
import DurableTransactions
import ExtrinsicService
import ExtrinsicServiceExt
import Foundation
import os
import SubstrateSdk

/// The app's chain-bound extrinsic tools for the durability engine, resolved per chain from the chain
/// registry and built once each.
final class DurableChainToolsProvider: DurableChainToolsProviding, @unchecked Sendable {
    struct Tools {
        let operationFactory: any ExtrinsicOperationFactoryProtocol
        let submitter: any ExtrinsicSubmitting
    }

    private let chainRegistry: ChainRegistryProtocol
    private let extrinsicFacade: ExtrinsicSubmissionMonitorFacade
    private let tools = OSAllocatedUnfairLock<[ChainId: Tools]>(initialState: [:])

    init(chainRegistry: ChainRegistryProtocol, extrinsicFacade: ExtrinsicSubmissionMonitorFacade) {
        self.chainRegistry = chainRegistry
        self.extrinsicFacade = extrinsicFacade
    }

    func extrinsicOperationFactory(for chainId: ChainId) throws -> any ExtrinsicOperationFactoryProtocol {
        try tools(for: chainId).operationFactory
    }

    func extrinsicSubmitter(for chainId: ChainId) throws -> any ExtrinsicSubmitting {
        try tools(for: chainId).submitter
    }
}

private extension DurableChainToolsProvider {
    func tools(for chainId: ChainId) throws -> Tools {
        if let cached = tools.withLock({ $0[chainId] }) {
            return cached
        }

        guard let chain = chainRegistry.getChain(for: chainId) else {
            throw DurableTxError.chainViewUnavailable
        }

        // Durability must observe the finalized outcome, not just inclusion, so the watch follows each
        // extrinsic until its block is finalized.
        let built = try Tools(
            operationFactory: extrinsicFacade.createOperationFactory(chain: chain),
            submitter: extrinsicFacade.makeForkProtectedSubmitter(chain: chain, trackingTill: .finalized)
        )

        return tools.withLock { current in
            if let existing = current[chainId] { return existing }
            current[chainId] = built
            return built
        }
    }
}
