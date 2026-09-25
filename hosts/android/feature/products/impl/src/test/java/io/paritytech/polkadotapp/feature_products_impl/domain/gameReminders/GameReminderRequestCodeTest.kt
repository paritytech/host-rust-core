package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class GameReminderRequestCodeTest {
    @Test
    fun `request code is stable per product and namespaced away from the raw product hash`() {
        assertEquals(gameReminderRequestCode("jollity.dot"), gameReminderRequestCode("jollity.dot"))
        assertEquals("game:jollity.dot".hashCode(), gameReminderRequestCode("jollity.dot"))
        assertNotEquals("jollity.dot".hashCode(), gameReminderRequestCode("jollity.dot"))
    }
}
