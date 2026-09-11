import Foundation
import SubstrateSdk
@preconcurrency import SubstrateStateCall
import Operation_iOS
import BigInt

enum ReviveContractError: Error {
    case runtimeApiNotFound
    case callFailed(JSON)
}

struct ReviveContractResult: Decodable {
    let result: Substrate.Result<ReviveExecResult, JSON>
}

struct ReviveExecResult: Decodable {
    let data: BytesCodable
}

final class ReviveContractCaller {
    private let stateCallFactory: StateCallRequestFactoryProtocol

    init(stateCallFactory: StateCallRequestFactoryProtocol = StateCallRequestFactory()) {
        self.stateCallFactory = stateCallFactory
    }

    // 184467440737090 — max weight dimension (matches the runtime's saturating max used for read calls).
    private static let maxWeight: BigUInt = 184_467_440_737_090
}

extension ReviveContractCaller: ReviveContractCalling {
    func callReadOnly(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        caller: AccountId,
        contract: Data,
        input: Data
    ) async throws -> Data {
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        guard
            let runtimeApi = codingFactory.metadata.getRuntimeApiMethod(
                for: "ReviveApi",
                methodName: "call"
            ) else {
            throw ReviveContractError.runtimeApiNotFound
        }

        let arguments = CallArguments(caller: caller, contract: contract, input: input)

        let outcome: ReviveContractResult = try await stateCallFactory.createWrapper(
            for: runtimeApi.callName,
            paramsClosure: { encoder, context in
                try Self.encodeCallParams(
                    encoder: encoder,
                    context: context,
                    runtimeApi: runtimeApi,
                    arguments: arguments
                )
            },
            codingFactoryClosure: { codingFactory },
            connection: connection,
            queryType: runtimeApi.method.output.asTypeId()
        )
        .asyncExecute()

        return try outcome
            .result
            .ensureOkOrError { ReviveContractError.callFailed($0) }
            .data
            .wrappedValue
    }

    // Manually SCALE-encode the ReviveApi_call parameters (in order):
    // origin: AccountId32, dest: H160, value: u128, gas_limit: Weight,
    // storage_deposit_limit: u128, input_data: Vec<u8>.
    private struct CallArguments {
        let caller: AccountId
        let contract: Data
        let input: Data
    }

    private static func encodeCallParams(
        encoder: DynamicScaleEncoding,
        context: RuntimeJsonContext,
        runtimeApi: RuntimeApiQueryResult,
        arguments: CallArguments
    ) throws {
        let rawContext = context.toRawContext()
        let inputs = runtimeApi.method.inputs

        try encoder.append(
            BytesCodable(wrappedValue: arguments.caller),
            ofType: inputs[0].paramType.asTypeId(),
            with: rawContext
        )
        try encoder.append(
            BytesCodable(wrappedValue: arguments.contract),
            ofType: inputs[1].paramType.asTypeId(),
            with: rawContext
        )
        try encoder.append(
            StringCodable(wrappedValue: BigUInt.zero),
            ofType: inputs[2].paramType.asTypeId(),
            with: rawContext
        )

        let weight = Substrate.WeightV2(refTime: maxWeight, proofSize: maxWeight)
        try encoder.append(weight, ofType: inputs[3].paramType.asTypeId(), with: rawContext)

        try encoder.append(
            StringCodable(wrappedValue: maxWeight),
            ofType: inputs[4].paramType.asTypeId(),
            with: rawContext
        )
        try encoder.append(
            BytesCodable(wrappedValue: arguments.input),
            ofType: inputs[5].paramType.asTypeId(),
            with: rawContext
        )
    }
}
