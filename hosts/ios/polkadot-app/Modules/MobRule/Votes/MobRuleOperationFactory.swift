import Foundation
import SubstrateSdk
import Operation_iOS
import SubstrateStateCall
import Individuality
import ChainRegistry

protocol MobRuleOperationFactoryProtocol {
    func votedOnWrapper(
        voter: PeoplePallet.Alias,
        doneOnly: Bool,
        connection: ChainConnection,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[MobRulePallet.CaseIndex]>
}

final class MobRuleOperationFactory {
    let stateCallFactory: StateCallRequestFactoryProtocol

    init(
        stateCallFactory: StateCallRequestFactoryProtocol = StateCallRequestFactory()
    ) {
        self.stateCallFactory = stateCallFactory
    }
}

extension MobRuleOperationFactory: MobRuleOperationFactoryProtocol {
    func votedOnWrapper(
        voter: PeoplePallet.Alias,
        doneOnly: Bool,
        connection: ChainConnection,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[MobRulePallet.CaseIndex]> {
        let coderFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<[MobRulePallet.CaseIndex]> = stateCallFactory
            .createWrapper(
                for: MobRulePallet.RuntimeApiCall.votedOn.methodName,
                paramsClosure: { encoder, _ in
                    try encoder.appendBytes(json: .stringValue(voter.toHexString()))
                    try encoder.appendBool(json: .boolValue(doneOnly))
                },
                codingFactoryClosure: { try coderFactoryOperation.extractNoCancellableResultData() },
                connection: connection,
                resultDecoder: StateCallResultFromScaleTypeDecoder<[MobRulePallet.CaseIndex]>(),
                at: nil
            )

        fetchWrapper.addDependency(operations: [coderFactoryOperation])

        let mappingOperation = ClosureOperation<[MobRulePallet.CaseIndex]> {
            try fetchWrapper.targetOperation.extractNoCancellableResultData()
        }

        mappingOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper
            .insertingHead(operations: [coderFactoryOperation])
            .insertingTail(operation: mappingOperation)
    }
}

extension MobRulePallet {
    static let runtimeAPIPrefix = "MobRuleApi_"

    enum RuntimeApiCall: String {
        case votedOn = "voted_on"

        var methodName: String {
            runtimeAPIPrefix + rawValue
        }
    }
}
