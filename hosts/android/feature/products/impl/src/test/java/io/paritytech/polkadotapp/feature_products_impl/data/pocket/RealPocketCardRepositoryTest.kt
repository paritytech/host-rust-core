package io.paritytech.polkadotapp.feature_products_impl.data.pocket

import io.paritytech.polkadotapp.database.dao.PocketCardDao
import io.paritytech.polkadotapp.database.model.PocketCardFaceLocal
import io.paritytech.polkadotapp.database.model.PocketCardLocal
import io.paritytech.polkadotapp.feature_products_api.domain.pocket.PocketCard
import io.paritytech.polkadotapp.feature_products_api.model.JsWidget
import io.paritytech.polkadotapp.feature_products_impl.domain.pocket.CachedPocketCard
import io.paritytech.polkadotapp.feature_products_impl.domain.pocket.addedCard
import io.paritytech.polkadotapp.feature_products_impl.domain.pocket.cardKey
import io.paritytech.polkadotapp.feature_products_impl.domain.pocket.gameProduct
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// A face the app once wrote and can no longer read: the shape a renamed node or a dropped variant
// leaves behind in a database that outlives the format.
private const val UNREADABLE_FACE = """{"type":"hologram"}"""

class RealPocketCardRepositoryTest {
    private class FakePocketCardDao : PocketCardDao {
        val rows = MutableStateFlow<List<PocketCardLocal>>(emptyList())
        val faces = mutableMapOf<Pair<String, String>, String>()

        override fun observeAll(): Flow<List<PocketCardLocal>> = rows

        override suspend fun insert(card: PocketCardLocal) {
            rows.value = rows.value.filterNot { it.productId == card.productId && it.cardId == card.cardId } + card
        }

        override suspend fun delete(productId: String, cardId: String): Int {
            val before = rows.value.size
            rows.value = rows.value.filterNot { it.productId == productId && it.cardId == cardId }
            return before - rows.value.size
        }

        override suspend fun getFace(productId: String, cardId: String): String? = faces[productId to cardId]

        override suspend fun insertFace(face: PocketCardFaceLocal) {
            faces[face.productId to face.cardId] = face.faceJson
        }

        override suspend fun deleteFace(productId: String, cardId: String) {
            faces -= productId to cardId
        }
    }

    private val dao = FakePocketCardDao()
    private val repository = RealPocketCardRepository(dao)

    private fun key(cardId: String) = cardKey(gameProduct, cardId)

    private fun card(cardId: String, face: JsWidget): CachedPocketCard = addedCard(gameProduct, cardId).copy(face = face)

    // The collection feeds the home tab, the core's card list and the deeplink handler, none of which
    // catch. A face written by an older vocabulary must cost the card its picture, not its place.
    @Test
    fun `a card whose stored face no longer decodes keeps its place and answers no face`() = runTest {
        repository.insert(card("stamps", JsWidget.Text(text = "Stamps")))
        dao.faces["game.dot" to "stamps"] = UNREADABLE_FACE

        assertEquals(listOf(key("stamps")), repository.observeCards().first().map { it.key })
        assertNull(repository.face(key("stamps")))
    }

    @Test
    fun `an added card round-trips through the face it was approved with`() = runTest {
        repository.insert(card("loyalty", JsWidget.Text(text = "Loyalty")))

        assertEquals("loyalty", repository.observeCards().first().single().title)
        assertEquals(JsWidget.Text(text = "Loyalty"), repository.face(key("loyalty")))
    }

    // A face is kept for host-placed cards too, which have no card row of their own. Writing one must
    // not put a card in the collection that nobody added.
    @Test
    fun `keeping a face adds no card to the collection`() = runTest {
        repository.saveFace(key("humanity"), JsWidget.Text(text = "Humanity"))

        assertEquals(emptyList<PocketCard>(), repository.observeCards().first())
        assertEquals(JsWidget.Text(text = "Humanity"), repository.face(key("humanity")))
    }

    @Test
    fun `removing a card takes its face with it`() = runTest {
        repository.insert(card("loyalty", JsWidget.Text(text = "Loyalty")))

        assertEquals(true, repository.delete(key("loyalty")))

        assertEquals(emptyList<PocketCard>(), repository.observeCards().first())
        assertNull(repository.face(key("loyalty")))
    }
}
