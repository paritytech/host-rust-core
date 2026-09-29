package io.paritytech.polkadotapp.feature_products_impl.domain.pocket

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PocketCardIdentifierTest {
    private fun rejects(raw: String) {
        assertThrows("expected '$raw' to be rejected", IllegalArgumentException::class.java) {
            PocketCardIdentifier.screen(raw)
        }
    }

    @Test
    fun `trims and NFC-normalizes like the core, so both sides key the same card`() {
        // "e" + combining acute composes to the single code point the core stores.
        assertEquals("caf\u00e9", PocketCardIdentifier.screen("  cafe\u0301 ").value)
        assertEquals("loyalty card", PocketCardIdentifier.screen("loyalty card").value)
    }

    @Test
    fun `rejects what the core rejects before the first wire call`() {
        rejects("")
        rejects("   ")
        rejects("a".repeat(257))
        rejects("loy\u200Dalty") // zero-width joiner lets two ids render alike
        rejects("loy\u00ADalty") // soft hyphen
        rejects("loy\uFE0Falty") // variation selector
        rejects("loy\u00A0alty") // non-ASCII space
        rejects("loy\talty") // control character
        rejects("loy\u202Ealty") // bidi override
        rejects("loy\u200Balty") // zero-width space
    }

    @Test
    fun `byte budget applies after normalization, which can expand the input`() {
        // 128 two-byte characters fit; 129 do not.
        PocketCardIdentifier.screen("\u00e9".repeat(128))
        rejects("\u00e9".repeat(129))
    }
}
