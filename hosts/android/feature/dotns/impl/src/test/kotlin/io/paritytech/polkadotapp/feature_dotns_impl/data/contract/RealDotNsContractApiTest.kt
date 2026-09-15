@file:OptIn(ExperimentalStdlibApi::class)

package io.paritytech.polkadotapp.feature_dotns_impl.data.contract

import io.novasama.substrate_sdk_android.extensions.fromHex
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_dotns_impl.data.config.DotNsConfigProvider
import io.paritytech.polkadotapp.feature_revive_api.ReviveContractApi
import io.paritytech.polkadotapp.test_shared.any
import io.paritytech.polkadotapp.test_shared.eq
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.web3j.abi.FunctionEncoder
import org.web3j.abi.TypeReference
import org.web3j.abi.datatypes.Address
import org.web3j.abi.datatypes.DynamicBytes
import org.web3j.abi.datatypes.Function
import org.web3j.abi.datatypes.Type

class RealDotNsContractApiTest {
    private val reviveContractApi: ReviveContractApi = mock()
    private val chainRegistry: ChainRegistry = mock()
    private val configProvider: DotNsConfigProvider = mock()

    private val contractApi = RealDotNsContractApi(reviveContractApi, chainRegistry, configProvider)

    @Test
    fun `serves the content hash the name's own resolver carries`() = runBlocking<Unit> {
        stubConfig()
        stubRegistryResolver(NAME_RESOLVER)
        stubContentHash(NAME_RESOLVER, CONTENT_HASH)

        assertArrayEquals(CONTENT_HASH, contractApi.resolveContentHash(NAME).getOrThrow())
        verify(reviveContractApi, never()).callReadOnly(eq(CHAIN_ID), eq(FIXED_RESOLVER), any())
    }

    @Test
    fun `falls back to the fixed resolver when the name's own resolver has no content hash`() = runBlocking<Unit> {
        stubConfig()
        stubRegistryResolver(NAME_RESOLVER)
        stubEmptyOutput(NAME_RESOLVER)
        stubContentHash(FIXED_RESOLVER, CONTENT_HASH)

        assertArrayEquals(CONTENT_HASH, contractApi.resolveContentHash(NAME).getOrThrow())
    }

    @Test
    fun `reads the fixed resolver directly when the name has no registry entry`() = runBlocking<Unit> {
        stubConfig()
        stubRegistryResolver(null)
        stubContentHash(FIXED_RESOLVER, CONTENT_HASH)

        assertArrayEquals(CONTENT_HASH, contractApi.resolveContentHash(NAME).getOrThrow())
    }

    @Test
    fun `reports no content when neither resolver carries a content hash`() = runBlocking<Unit> {
        stubConfig()
        stubRegistryResolver(NAME_RESOLVER)
        stubEmptyOutput(NAME_RESOLVER)
        stubEmptyOutput(FIXED_RESOLVER)

        assertNull(contractApi.resolveContentHash(NAME).getOrThrow())
    }

    private fun stubConfig() = runBlocking {
        whenever(chainRegistry.knownChains).thenReturn(
            KnownChains(people = "", assetHub = CHAIN_ID, bulletIn = "", hydration = null)
        )
        whenever(configProvider.getDotNsConfig()).thenReturn(
            Result.success(DotNsConfig(resolverContractAddress = FIXED_RESOLVER, registryContractAddress = REGISTRY))
        )
    }

    private fun stubRegistryResolver(resolver: AccountId?) = runBlocking {
        val address = resolver?.value ?: ByteArray(20)
        val output = abiEncodeReturnValues(
            listOf(Address("0x" + address.toHexString())),
            listOf(object : TypeReference<Address>() {})
        )
        whenever(reviveContractApi.callReadOnly(eq(CHAIN_ID), eq(REGISTRY), any()))
            .thenReturn(Result.success(output.toDataByteArray()))
    }

    private fun stubContentHash(resolver: AccountId, contentHash: ByteArray) = runBlocking {
        val output = abiEncodeReturnValues(
            listOf(DynamicBytes(EIP_1577_IPFS_PREFIX + contentHash)),
            listOf(object : TypeReference<DynamicBytes>() {})
        )
        whenever(reviveContractApi.callReadOnly(eq(CHAIN_ID), eq(resolver), any()))
            .thenReturn(Result.success(output.toDataByteArray()))
    }

    // A resolver that does not implement the call reverts, which surfaces as an empty output.
    private fun stubEmptyOutput(resolver: AccountId) = runBlocking {
        whenever(reviveContractApi.callReadOnly(eq(CHAIN_ID), eq(resolver), any()))
            .thenReturn(Result.success(DataByteArray.empty()))
    }

    @Suppress("UNCHECKED_CAST")
    private fun abiEncodeReturnValues(values: List<Type<*>>, typeRefs: List<TypeReference<out Type<*>>>): ByteArray {
        val function = Function("_", values, typeRefs as List<TypeReference<Type<*>>>)
        val encoded = FunctionEncoder.encode(function).fromHex()
        return encoded.copyOfRange(4, encoded.size)
    }

    private companion object {
        const val CHAIN_ID = "asset-hub-chain-id"
        const val NAME = "getcash.paseo"
        val EIP_1577_IPFS_PREFIX = byteArrayOf(0xe3.toByte(), 0x01)
        val CONTENT_HASH = "01701220".fromHex() + ByteArray(32) { 3 }
        val FIXED_RESOLVER: AccountId = ByteArray(20) { 5 }.toDataByteArray()
        val REGISTRY: AccountId = ByteArray(20) { 6 }.toDataByteArray()
        val NAME_RESOLVER: AccountId = ByteArray(20) { 7 }.toDataByteArray()
    }
}
