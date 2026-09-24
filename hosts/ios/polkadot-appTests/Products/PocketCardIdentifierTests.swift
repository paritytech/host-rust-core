import Foundation
import Products
import Testing
@testable import polkadot_app

/// The core screens a card id with its chat identifier rules before any Pocket
/// call. Applying the same rules at manifest load makes a bad id fail there
/// instead of at the first wire call.
struct PocketCardIdentifierTests {
    @Test
    func acceptsAPlainIdentifier() throws {
        #expect(try PocketCardIdentifier.screen("loyalty").value == "loyalty")
    }

    @Test
    func trimsSurroundingWhitespace() throws {
        #expect(try PocketCardIdentifier.screen("  loyalty \n").value == "loyalty")
    }

    /// Composed and decomposed spellings of the same text must not become two
    /// distinct cards.
    @Test
    func normalizesToComposedForm() throws {
        let decomposed = "cafe\u{0301}"
        let composed = "café"

        #expect(try PocketCardIdentifier.screen(decomposed).value == composed)
    }

    @Test
    func refusesAnEmptyIdentifier() {
        #expect(throws: (any Error).self) { try PocketCardIdentifier.screen("") }
        #expect(throws: (any Error).self) { try PocketCardIdentifier.screen("   ") }
    }

    /// The bound is on bytes once normalized, not characters, and is the same
    /// 256 the core applies.
    @Test
    func refusesAnIdentifierLongerThanTheByteBound() {
        #expect(throws: Never.self) { try PocketCardIdentifier.screen(String(repeating: "a", count: 256)) }
        #expect(throws: (any Error).self) { try PocketCardIdentifier.screen(String(repeating: "a", count: 257)) }
        // Four bytes each, so 64 is the limit and 65 is over it.
        #expect(throws: (any Error).self) { try PocketCardIdentifier.screen(String(repeating: "😀", count: 65)) }
    }

    /// Characters that let two distinct ids render identically are refused, so
    /// a card cannot impersonate another product's.
    @Test
    func refusesCharactersThatHideADifference() {
        let confusables = [
            "loy\u{200B}alty", // zero-width space
            "loy\u{200D}alty", // zero-width joiner
            "loy\u{00AD}alty", // soft hyphen
            "loy\u{FEFF}alty", // byte order mark
            "loy\u{202E}alty", // right-to-left override
            "loy\u{2066}alty", // left-to-right isolate
            "loy\u{FE0F}alty", // variation selector
            "loy\u{2060}alty", // word joiner
            "loy\u{00A0}alty", // non-breaking space
            "loy\u{0001}alty" // control character
        ]

        for confusable in confusables {
            #expect(throws: (any Error).self, "expected \(confusable.debugDescription) to be refused") {
                try PocketCardIdentifier.screen(confusable)
            }
        }
    }

    /// An ordinary ASCII space inside an id is not a confusable, so it stays.
    @Test
    func keepsAnOrdinaryInteriorSpace() throws {
        #expect(try PocketCardIdentifier.screen("loyalty card").value == "loyalty card")
    }
}
