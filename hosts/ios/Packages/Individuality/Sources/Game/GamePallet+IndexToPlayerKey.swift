import SubstrateSdk

public extension GamePallet {
    struct IndexToPlayerKey: Encodable, Equatable {
        public let roundIndex: RoundIndex
        public let playerIndex: PlayerIndex

        public init(roundIndex: RoundIndex, playerIndex: PlayerIndex) {
            self.roundIndex = roundIndex
            self.playerIndex = playerIndex
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(StringCodable(wrappedValue: roundIndex))
            try container.encode(StringCodable(wrappedValue: playerIndex))
        }
    }
}
