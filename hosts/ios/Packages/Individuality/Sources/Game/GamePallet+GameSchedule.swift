import SubstrateSdk

public extension GamePallet {
    struct GameSchedule: Decodable, Equatable {
        @StringCodable public var gamePlayTime: UInt32
        @StringCodable public var rounds: UInt8
        @StringCodable public var maxGroupSize: UInt32
        @OptionStringCodable public var personhoodScoreOverride: UInt32?
    }
}
