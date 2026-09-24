import Foundation
import Testing
@testable import polkadot_app

/// Classification goes through the core's own `parse_navigate`, so every host
/// reads a Pocket link the same way rather than parsing the string itself.
struct PocketDeeplinkParserTests {
    let parser = PocketDeeplinkParser()

    @Test
    func readsAnAddLink() throws {
        let link = try #require(parser.parse("polkadot://game.dot/-/pocket/add?card=loyalty"))

        #expect(link.productHost == "game.dot")
        #expect(link.action == .add)
        #expect(link.cardId == "loyalty")
    }

    @Test
    func readsAnOpenLink() throws {
        let link = try #require(parser.parse("polkadot://game.dot/-/pocket/open?card=loyalty"))

        #expect(link.action == .open)
    }

    /// The reserved `-` segment belongs to the host. An ordinary product path is
    /// not a Pocket link and must fall through to the App.
    @Test
    func doesNotClaimAnOrdinaryProductLink() {
        #expect(parser.parse("polkadot://game.dot/some/page") == nil)
    }

    @Test
    func doesNotClaimAnUnrelatedUrl() {
        #expect(parser.parse("https://example.com/-/pocket/add?card=loyalty") == nil)
    }
}
