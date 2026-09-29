import SubstrateSdk

public extension GamePallet {
    struct PhaseDurationValues: Decodable, Equatable {
        @StringCodable public var registration: UInt32
        @StringCodable public var shuffle: UInt32
        @StringCodable public var postShuffleMargin: UInt32
        @StringCodable public var reporting: UInt32
        @StringCodable public var playerProcess: UInt32
    }
}
