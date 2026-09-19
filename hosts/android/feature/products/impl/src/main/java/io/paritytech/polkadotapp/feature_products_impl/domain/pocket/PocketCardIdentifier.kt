package io.paritytech.polkadotapp.feature_products_impl.domain.pocket

import io.paritytech.polkadotapp.feature_products_api.domain.pocket.PocketCardId
import java.text.Normalizer

/**
 * The core screens a card id with its chat identifier rules before any Pocket call; applying the same
 * rules at manifest load makes a bad id fail there instead of at the first wire call.
 */
object PocketCardIdentifier {
    private const val MAX_BYTES = 256

    /** Throws [IllegalArgumentException] on a rejected id, for use inside a `runCatching` parser. */
    fun screen(raw: String): PocketCardId {
        val normalized = Normalizer.normalize(raw.trim(), Normalizer.Form.NFC)
        require(normalized.isNotEmpty()) { "card id must not be empty" }
        require(normalized.toByteArray().size <= MAX_BYTES) { "card id longer than $MAX_BYTES bytes" }
        require(normalized.codePoints().noneMatch(::isUnsafe)) { "card id carries an unsafe character" }
        return PocketCardId(normalized)
    }

    private fun isUnsafe(codePoint: Int): Boolean =
        Character.getType(codePoint) == Character.CONTROL.toInt() ||
            isNonAsciiSpace(codePoint) ||
            codePoint in INVISIBLE_JOINERS ||
            codePoint in VARIATION_SELECTORS ||
            codePoint in BIDI_OVERRIDES ||
            codePoint in BIDI_ISOLATES ||
            codePoint in EMOJI_TAGS ||
            codePoint in OTHER_INVISIBLES

    private fun isNonAsciiSpace(codePoint: Int): Boolean =
        codePoint != ' '.code && (Character.isSpaceChar(codePoint) || Character.isWhitespace(codePoint))

    private val INVISIBLE_JOINERS = 0x2060..0x2064
    private val VARIATION_SELECTORS = 0xFE00..0xFE0F
    private val BIDI_OVERRIDES = 0x202A..0x202E
    private val BIDI_ISOLATES = 0x2066..0x2069
    private val EMOJI_TAGS = 0xE0000..0xE007F
    private val OTHER_INVISIBLES = setOf(0x00AD, 0x200B, 0x200C, 0x200D, 0x061C, 0x2028, 0x2029, 0xFEFF)
}
