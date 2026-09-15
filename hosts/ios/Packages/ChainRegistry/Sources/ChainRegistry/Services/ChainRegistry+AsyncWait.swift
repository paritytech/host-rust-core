import Foundation
import Operation_iOS
import OperationExt

public extension ChainRegistryProtocol {
    func asyncChains(
        for chainIDs: Set<ChainModel.Id>,
        workQueue: DispatchQueue = .global()
    ) -> CompoundOperationWrapper<[ChainModel.Id: ChainModel]> {
        let subscriptionId = NSObject()

        let operation = AsyncClosureOperation<[ChainModel.Id: ChainModel]>(operationClosure: { [weak self] closure in
            self?.chainsSubscribe(
                subscriptionId,
                runningInQueue: workQueue
            ) { changes in
                guard !changes.isEmpty else {
                    return
                }

                self?.chainsUnsubscribe(subscriptionId)
                let allChains = changes.allChangedItems()

                let chainIDsWithChainModel = allChains.filter { chainIDs.contains($0.chainId) }
                    .reduce(into: [ChainModel.Id: ChainModel]()) {
                        $0[$1.chainId] = $1
                    }
                closure(.success(chainIDsWithChainModel))
            }
        }, cancelationClosure: { [weak self] in
            self?.chainsUnsubscribe(subscriptionId)
        })

        return CompoundOperationWrapper(targetOperation: operation)
    }

    func asyncWaitChainsSetup(for chainIds: Set<ChainModel.Id>) async {
        guard !chainIds.isEmpty else { return }

        let syncQueue = DispatchQueue(label: "io.chain.registry.wait.chain.setup")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let target = NSObject()
            var availableChains: [ChainModel.Id: ChainModel] = [:]
            var didResume = false

            chainsSubscribe(target, runningInQueue: syncQueue) { [weak self] changes in
                guard let self, !didResume else { return }

                for change in changes {
                    switch change {
                    case let .insert(chain),
                         let .update(chain):
                        availableChains[chain.chainId] = chain
                    case let .delete(chainId):
                        availableChains[chainId] = nil
                    }
                }

                let allChainsAvailable = chainIds.allSatisfy { availableChains[$0] != nil }

                if allChainsAvailable {
                    didResume = true
                    chainsUnsubscribe(target)
                    continuation.resume()
                }
            }
        }
    }
}
