package io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_dotns_gateway_api.data.repository.DotNsGatewayRepository
import io.paritytech.polkadotapp.feature_dotns_gateway_api.domain.model.DotNsBaseNameAvailability
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeUsernameAvailabilityState
import io.paritytech.polkadotapp.test_shared.any
import io.paritytech.polkadotapp.test_shared.eq
import io.paritytech.polkadotapp.test_shared.whenever
import junit.framework.TestCase.assertEquals
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.mockito.Mockito.mock

class RealCheckUsernameAvailabilityUseCaseTest {
    private val knownChains = KnownChains(people = "", assetHub = CHAIN_ID, bulletIn = "", hydration = null)
    private val chainRegistry: ChainRegistry = mock()
    private val accountRepository: AccountRepository = mock()
    private val dotNsGatewayRepository: DotNsGatewayRepository = mock()

    private val useCase = RealCheckUsernameAvailabilityUseCase(
        knownChains = knownChains,
        chainRegistry = chainRegistry,
        accountRepository = accountRepository,
        dotNsGatewayRepository = dotNsGatewayRepository
    )

    @Test
    fun `Free when dotNS reports the name available`() = runBlocking<Unit> {
        stubOurAccount()
        stubAvailability(DotNsBaseNameAvailability.Free)

        assertEquals(UpgradeUsernameAvailabilityState.Free, useCase(NAME).getOrThrow())
    }

    @Test
    fun `ReservedByUs when dotNS reports our live reservation`() = runBlocking<Unit> {
        stubOurAccount()
        stubAvailability(DotNsBaseNameAvailability.ReservedByUs)

        assertEquals(UpgradeUsernameAvailabilityState.ReservedByUs, useCase(NAME).getOrThrow())
    }

    @Test
    fun `NotAvailable when dotNS reports the name taken`() = runBlocking<Unit> {
        stubOurAccount()
        stubAvailability(DotNsBaseNameAvailability.TakenByOther)

        assertEquals(UpgradeUsernameAvailabilityState.NotAvailable, useCase(NAME).getOrThrow())
    }

    private fun stubAvailability(availability: DotNsBaseNameAvailability) = runBlocking {
        whenever(dotNsGatewayRepository.getBaseNameAvailability(eq(NAME), eq(OUR_ACCOUNT_ID)))
            .thenReturn(Result.success(availability))
    }

    private fun stubOurAccount() = runBlocking {
        val chain = mock<Chain>()
        whenever(chainRegistry.getChain(eq(CHAIN_ID))).thenReturn(chain)
        val account = mock<MetaAccount>().also { whenever(it.accountIdIn(any())).thenReturn(OUR_ACCOUNT_ID) }
        whenever(accountRepository.getWalletAccount()).thenReturn(account)
    }

    private companion object {
        const val CHAIN_ID = "asset-hub-chain-id"
        const val NAME = "byteboro"
        val OUR_ACCOUNT_ID: AccountId = ByteArray(32) { 1 }.toDataByteArray()
    }
}
