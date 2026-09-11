package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.Junctions
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.MultiLocation.Interior
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.MultiLocation.Junction
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.RelativeMultiLocation
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertNull
import org.junit.Test
import java.math.BigInteger

class AirdropPrizeAssetIdTest {
    @Test
    fun `extracts the GeneralIndex of an Asset Hub asset`() {
        val location = RelativeMultiLocation(
            parents = 0,
            interior = Junctions(
                Junction.PalletInstance(BigInteger.valueOf(50)),
                Junction.GeneralIndex(BigInteger.valueOf(1337)),
            )
        )

        assertEquals(BigInteger.valueOf(1337), location.firstGeneralIndex())
    }

    @Test
    fun `returns null when the Location carries no GeneralIndex`() {
        val location = RelativeMultiLocation(
            parents = 1,
            interior = Junctions(Junction.PalletInstance(BigInteger.valueOf(50))),
        )

        assertNull(location.firstGeneralIndex())
    }

    @Test
    fun `returns null for a bare Here interior`() {
        val location = RelativeMultiLocation(parents = 1, interior = Interior.Here)

        assertNull(location.firstGeneralIndex())
    }
}
