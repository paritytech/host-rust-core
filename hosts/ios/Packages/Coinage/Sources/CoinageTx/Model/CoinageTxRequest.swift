import ExtrinsicService
import Foundation

/// One transaction to register and submit: what it consumes and mints, plus how to build and
/// sign its extrinsic. A batch of these registers atomically under one ``CoinageTxGroupId``.
public struct CoinageTxRequest {
    public let inputs: [CoinageTxInput]
    public let outputs: [OwnAsset]
    public let builder: ExtrinsicBuilderClosure
    public let origin: any ExtrinsicOriginDefining

    public init(
        inputs: [CoinageTxInput],
        outputs: [OwnAsset],
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) {
        self.inputs = inputs
        self.outputs = outputs
        self.builder = builder
        self.origin = origin
    }
}
