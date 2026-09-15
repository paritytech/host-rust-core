import Foundation
import ExtrinsicService
import SubstrateSdk
import KeyDerivation
@testable import Coinage

/// An origin factory that hands back ``StubExtrinsicOrigin`` for every request. Pass `errorToThrow` to
/// make the unload-token path fail.
final class StubOriginFactory: OriginCreating {
    let errorToThrow: Error?

    init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    func createAsCoinOrigin(for _: WalletManaging) throws -> ExtrinsicOriginDefining {
        StubExtrinsicOrigin()
    }

    func createInfallibleUnpaidSignedOrigin(for _: WalletManaging) throws -> ExtrinsicOriginDefining {
        StubExtrinsicOrigin()
    }

    func createAsUnloadTokenOrigins(
        voucherGroups: [[Voucher]],
        currentDate _: Date,
        blockHash _: BlockHashData?
    ) async throws -> [ExtrinsicOriginDefining] {
        if let errorToThrow { throw errorToThrow }
        return voucherGroups.map { _ in StubExtrinsicOrigin() }
    }
}
