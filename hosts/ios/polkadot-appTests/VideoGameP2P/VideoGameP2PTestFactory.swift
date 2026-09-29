@testable import polkadot_app
import Foundation
import Individuality
import MessageExchangeKit
import SubstrateSdk

enum VideoGameP2PTestFactory {
    static let gameIndex: GamePallet.GameIndex = 7

    static func makePeer() -> MessageExchange.Peer {
        MessageExchange.Peer(
            accountId: Data(repeating: 1, count: 32),
            publicKey: Data(repeating: 2, count: 33),
            pin: nil,
            devices: []
        )
    }

    static func makeSession(
        peer: MessageExchange.Peer = makePeer(),
        exchangeService: MockVideoGameMessageExchangeService = MockVideoGameMessageExchangeService()
    ) -> VideoGameSignalingSession {
        VideoGameSignalingSession(
            gameIndex: gameIndex,
            peerAccountId: peer.accountId,
            exchangeService: AnyMessageExchangeService(exchangeService),
            peer: peer,
            peerLogger: Logger.shared
        )
    }
}
