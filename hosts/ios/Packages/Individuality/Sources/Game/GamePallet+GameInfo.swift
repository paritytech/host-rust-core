import SubstrateSdk

public extension GamePallet {
    struct GameInfo: Decodable, Equatable {
        public let state: GameState
        @StringCodable public var index: GameIndex
        @StringCodable public var registrationEnds: UInt32
        @StringCodable public var gameDate: UInt32
        @StringCodable public var reportEnds: UInt32
        @StringCodable public var maxGroupSize: UInt32
        @StringCodable public var rounds: UInt8
        @OptionStringCodable public var personhoodScoreOverride: UInt32?
        @OptionStringCodable public var airdropsScheduled: UInt8?
    }
}
