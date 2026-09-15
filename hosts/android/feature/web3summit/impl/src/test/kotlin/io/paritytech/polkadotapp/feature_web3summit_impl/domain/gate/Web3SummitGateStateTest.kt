package io.paritytech.polkadotapp.feature_web3summit_impl.domain.gate

import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitGateMode
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitGateModeProvider
import io.paritytech.polkadotapp.feature_web3summit_impl.data.storage.PreferencesLightPersonhoodEstablishedStorage
import io.paritytech.polkadotapp.feature_web3summit_impl.data.storage.PreferencesWeb3SummitVerifiedStorage
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.Mockito

class Web3SummitGateStateTest {
    @Test
    fun `disabled mode always lands on Main`() {
        assertDecision(Web3SummitDestination.Main, mode = Web3SummitGateMode.VERIFICATION_DISABLED, verified = false, lightPersonhood = false)
        assertDecision(Web3SummitDestination.Main, mode = Web3SummitGateMode.VERIFICATION_DISABLED, verified = false, lightPersonhood = true)
        assertDecision(Web3SummitDestination.Main, mode = Web3SummitGateMode.VERIFICATION_DISABLED, verified = true, lightPersonhood = true)
    }

    @Test
    fun `ended mode always lands on Ended`() {
        assertDecision(Web3SummitDestination.Ended, mode = Web3SummitGateMode.W3S_ENDED, verified = false, lightPersonhood = false)
        assertDecision(Web3SummitDestination.Ended, mode = Web3SummitGateMode.W3S_ENDED, verified = true, lightPersonhood = true)
    }

    @Test
    fun `enabled, verified and when light personhood established routes to Main`() {
        assertDecision(Web3SummitDestination.Main, mode = Web3SummitGateMode.VERIFICATION_ENABLED_SKIPPABLE, verified = true, lightPersonhood = true)
    }

    @Test
    fun `enabled and not verified routes to Spa`() {
        assertDecision(Web3SummitDestination.Spa, mode = Web3SummitGateMode.VERIFICATION_ENABLED, verified = false, lightPersonhood = true)
        assertDecision(Web3SummitDestination.Spa, mode = Web3SummitGateMode.VERIFICATION_ENABLED_SKIPPABLE, verified = false, lightPersonhood = true)
    }

    @Test
    fun `enabled and when light personhood not established routes to Spa`() {
        assertDecision(Web3SummitDestination.Spa, mode = Web3SummitGateMode.VERIFICATION_ENABLED, verified = true, lightPersonhood = false)
        assertDecision(Web3SummitDestination.Spa, mode = Web3SummitGateMode.VERIFICATION_ENABLED_SKIPPABLE, verified = true, lightPersonhood = false)
    }

    private fun assertDecision(
        expected: Web3SummitDestination,
        mode: Web3SummitGateMode,
        verified: Boolean,
        lightPersonhood: Boolean,
    ) = runBlocking {
        val modeProvider = Mockito.mock(Web3SummitGateModeProvider::class.java)
        val verifiedStorage = Mockito.mock(PreferencesWeb3SummitVerifiedStorage::class.java)
        val lightPersonhoodStorage = Mockito.mock(PreferencesLightPersonhoodEstablishedStorage::class.java)
        whenever(modeProvider.current()).thenReturn(mode)
        whenever(verifiedStorage.isVerified()).thenReturn(verified)
        whenever(lightPersonhoodStorage.isEstablished()).thenReturn(lightPersonhood)

        val state = Web3SummitGateState(modeProvider, verifiedStorage, lightPersonhoodStorage)
        assertEquals(expected, state.decideDestination())
    }
}
