@testable import polkadot_app
import Foundation
import Testing

struct DeepLinkParsingTests {
    @Test("Parses deeplink for chat with players")
    func parseDeeplinkForChatWithPlayers() {
        let date = Date()
        let url = AppConfig.DeepLink.players(game: 0, gameDate: date)

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        #expect(components?.count == 2)
        #expect(components?[0].name == "id")
        #expect(components?[0].value == "0")
        #expect(components?[1].name == "date")
        #expect(components?[1].value == date.ISO8601Format())
    }

    @Test("Parses deeplink to open chat with preexistence check")
    func parseChatDeeplinkNoForce() {
        performChatDeeplinkTest(
            chatId: Chat.Id.chatExtension(DIM2ChatExtension.identifier),
            force: false
        )
    }

    @Test("Parses deeplink to open chat without preexistence check")
    func parseChatDeeplinkWithForce() {
        performChatDeeplinkTest(
            chatId: Chat.Id.chatExtension(DIM1ChatExtension.identifier),
            force: true
        )
    }

    private func performChatDeeplinkTest(chatId: Chat.Id, force: Bool) {
        let url = AppConfig.DeepLink.chat(chatId, force: force)

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        #expect(components?.count == 2)
        #expect(components?[0].name == "id")
        #expect(components?[0].value == chatId.rawRepresentation)
        #expect(components?[1].name == "force")
        #expect(components?[1].value.flatMap(Bool.init) == force)
    }
}
