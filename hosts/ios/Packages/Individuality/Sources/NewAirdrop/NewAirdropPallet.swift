import Foundation
import BigInt
import SubstrateSdk

public enum NewAirdropPallet {
    public static let name = "Airdrop"

    public typealias EventId = Data
    public typealias AssetId = UInt32
    public typealias AssetBalance = BigUInt
    public typealias Permill = UInt32
    public typealias Slot = Data

    static let airdropContextBase = Data("pop:polkadot.network/airdrop".utf8)

    // Event ID layout: 27-byte base + 1-byte airdrop index + 4-byte big-endian game index = 32 bytes total.
    public static func gameEventId(
        forGameIndex gameIndex: UInt32,
        airdropIndex: UInt8
    ) -> EventId {
        let base = Data("pop:game:airdrop:".utf8)
        let padding = Data(repeating: UInt8(ascii: " "), count: 27)
        var ctx = (base + padding).prefix(27)
        ctx.append(Data([airdropIndex]))
        ctx.append(Data(gameIndex.bigEndianBytes))
        return ctx.prefix(32)
    }

    public static func airdropContext(forGameIndex gameIndex: UInt32, airdropIndex: UInt8) throws -> Data {
        try (airdropContextBase + gameEventId(forGameIndex: gameIndex, airdropIndex: airdropIndex)).blake2b32()
    }
}
