import UIKit
import SubstrateSdk
import Individuality
import Operation_iOS
import ChainRegistry

final class TattooFamilyDetailsInteractor {
    weak var presenter: TattooFamilyDetailsInteractorOutputProtocol?

    let connection: JSONRPCEngine
    let runtimeProvider: RuntimeProviderProtocol
    let families: [ProofOfInk.Collection]
    let proofOfInkFactory: ProofOfInkOperationFactoryProtocol
    let operationQueue: OperationQueue
    let jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol

    let reservedCancellable = CancellableCallStore()

    init(
        families: [ProofOfInk.Collection],
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol,
        proofOfInkFactory: ProofOfInkOperationFactoryProtocol,
        jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol,
        operationQueue: OperationQueue
    ) {
        self.families = families
        self.connection = connection
        self.runtimeProvider = runtimeProvider
        self.proofOfInkFactory = proofOfInkFactory
        self.jsonLocalSubscriptionFactory = jsonLocalSubscriptionFactory
        self.operationQueue = operationQueue
    }

    deinit {
        reservedCancellable.cancel()
    }

    private func provideReservedDesigns() {
        reservedCancellable.cancel()

        let wrapper = proofOfInkFactory.fetchReservedDesignes(
            for: connection,
            runtimeProvider: runtimeProvider
        )

        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: reservedCancellable,
            runningCallbackIn: .main
        ) { [weak self] result in
            guard let self else {
                return
            }
            MainActor.assumeIsolated {
                switch result {
                case let .success(reservedItems):
                    let items = self.familyIndices.reduce(into: ProofOfInkPallet.ReservedDesignsResult()) {
                        $0[$1] = reservedItems[$1]
                    }
                    self.presenter?.didReceiveReservedDesigns(items)
                case let .failure(error):
                    self.presenter?.didReceiveError(.reservedFailed(error))
                }
            }
        }
    }

    private var familyIds: [ProofOfInkPallet.FamilyId] {
        families.map(\.family.id)
    }

    private var familyIndices: [ProofOfInkPallet.FamilyIndex] {
        families.map(\.familyIndex)
    }
}

extension TattooFamilyDetailsInteractor: TattooFamilyDetailsInteractorInputProtocol {
    func setup() {
        provideReservedDesigns()
    }

    func retryReserved() {
        if !reservedCancellable.hasCall {
            provideReservedDesigns()
        }
    }
}
