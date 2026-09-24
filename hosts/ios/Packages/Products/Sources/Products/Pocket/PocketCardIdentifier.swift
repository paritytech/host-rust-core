import Foundation

/// The label a product declares for one of its cards, unique within that product.
public struct PocketCardId: Hashable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

public enum PocketCardIdentifierError: Error, CustomStringConvertible {
    case empty
    case tooLong(bytes: Int)
    case unsafeCharacter(UnicodeScalar)

    public var description: String {
        switch self {
        case .empty:
            "card id must not be empty"
        case let .tooLong(bytes):
            "card id or title is \(bytes) bytes, longer than it may be"
        case let .unsafeCharacter(scalar):
            "card id carries an unsafe character U+\(String(scalar.value, radix: 16, uppercase: true))"
        }
    }
}

/// Screens a card id with the rules the core applies before any Pocket call, so
/// a bad id fails where it is declared rather than at the first wire call.
///
/// The character rules exist so two distinct ids cannot render identically: the
/// user approves a card from a dialog showing its title, and a product must not
/// be able to pass one off as another's.
public enum PocketCardIdentifier {
    public static let maxBytes = 256

    /// A title is shorter than an id because it is drawn: one long enough to
    /// push the product's name out of the approval dialog defeats the dialog.
    public static let maxTitleBytes = 96

    public static func screen(_ raw: String) throws -> PocketCardId {
        try PocketCardId(value: screened(raw, maxBytes: maxBytes))
    }

    /// The same rules for the name the card is drawn under. The dialog that
    /// grants a card its place names it by this text, so a title able to hide
    /// characters passes a card off exactly as an id able to would.
    public static func screenTitle(_ raw: String) throws -> String {
        try screened(raw, maxBytes: maxTitleBytes)
    }

    private static func screened(_ raw: String, maxBytes: Int) throws -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping

        guard !normalized.isEmpty else { throw PocketCardIdentifierError.empty }

        let bytes = normalized.utf8.count
        guard bytes <= maxBytes else { throw PocketCardIdentifierError.tooLong(bytes: bytes) }

        if let unsafe = normalized.unicodeScalars.first(where: isUnsafe) {
            throw PocketCardIdentifierError.unsafeCharacter(unsafe)
        }

        return normalized
    }

    /// An ordinary ASCII space hides nothing, so it is the one space that stays.
    private static func isUnsafe(_ scalar: UnicodeScalar) -> Bool {
        if scalar == " " { return false }

        return scalar.properties.generalCategory == .control
            || scalar.properties.isWhitespace
            || invisibles.contains(scalar.value)
            || invisibleRanges.contains { $0.contains(scalar.value) }
    }

    private static let invisibles: Set<UInt32> = [
        0x00AD, // soft hyphen
        0x061C, // arabic letter mark
        0x200B, // zero width space
        0x200C, // zero width non-joiner
        0x200D, // zero width joiner
        0x2028, // line separator
        0x2029, // paragraph separator
        0xFEFF // zero width no-break space
    ]

    private static let invisibleRanges: [ClosedRange<UInt32>] = [
        0x2060 ... 0x2064, // invisible joiners
        0x202A ... 0x202E, // bidi overrides
        0x2066 ... 0x2069, // bidi isolates
        0xFE00 ... 0xFE0F, // variation selectors
        0xE0000 ... 0xE007F // emoji tags
    ]
}
