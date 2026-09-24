package io.paritytech.polkadotapp.chains.multiNetwork.chain.remote

import com.google.gson.Gson
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.remote.model.ChainRemote
import io.paritytech.polkadotapp.chains.util.Ids
import io.paritytech.polkadotapp.common.utils.fromJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

class RemoteConfigDefaultChainsTest {
    private val gson = Gson()

    @Test
    fun defaultChainsParseIntoChainRemote() {
        val chains = parseDefaultChains()

        assertFalse("chains_v2 default is empty", chains.isEmpty())
        chains.forEach { chain ->
            assertTrue("blank chainId in $chain", chain.chainId.isNotBlank())
            assertTrue("blank name for ${chain.chainId}", chain.name.isNotBlank())
            assertFalse("no nodes for ${chain.chainId}", chain.nodes.isEmpty())
            assertFalse("no assets for ${chain.chainId}", chain.assets.isEmpty())
        }
    }

    @Test
    fun defaultChainsCoverTheChainsTheTrUApiRuntimeNeeds() {
        val byId = parseDefaultChains().associateBy(ChainRemote::chainId)

        val required = listOf(
            Chain.Ids.PREVIEWNET_PEOPLE,
            Chain.Ids.PREVIEWNET_BULLET_IN,
            Chain.Ids.PREVIEWNET_ASSET_HUB,
        )

        required.forEach { chainId ->
            val chain = byId[chainId]
            assertNotNull("$chainId missing from the chains_v2 defaults", chain)

            val genesisHash = chain!!.genesisHash
            assertNotNull("$chainId has no genesisHash", genesisHash)
            assertEquals("$chainId genesisHash is not 32 unprefixed bytes", 64, genesisHash!!.length)
            assertTrue(
                "$chainId genesisHash is not lowercase hex: $genesisHash",
                genesisHash.all { it in '0'..'9' || it in 'a'..'f' },
            )
        }
    }

    private fun parseDefaultChains(): List<ChainRemote> {
        val raw = readDefault(CONFIG_CHAINS_KEY)
        return gson.fromJson<List<ChainRemote>>(raw)
    }

    private fun readDefault(key: String): String {
        val document = DocumentBuilderFactory.newInstance()
            .newDocumentBuilder()
            .parse(defaultsFile())

        val entries = document.getElementsByTagName("entry")
        for (index in 0 until entries.length) {
            val entry = entries.item(index) as Element
            val entryKey = entry.getElementsByTagName("key").item(0).textContent.trim()
            if (entryKey == key) {
                return entry.getElementsByTagName("value").item(0).textContent
            }
        }

        error("No `$key` entry in ${defaultsFile()}")
    }

    private fun defaultsFile(): File {
        var directory: File? = File(System.getProperty("user.dir").orEmpty()).absoluteFile
        while (directory != null) {
            val candidate = File(directory, DEFAULTS_PATH)
            if (candidate.isFile) return candidate
            directory = directory.parentFile
        }

        error("Cannot find $DEFAULTS_PATH above ${System.getProperty("user.dir")}")
    }

    private companion object {
        const val DEFAULTS_PATH =
            "tools/remoteconfig/impl/src/debug/res/xml/remote_config_defaults.xml"
    }
}
