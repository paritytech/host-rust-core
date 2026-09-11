package io.paritytech.polkadotapp.feature_products_impl.domain.usecase

import com.google.gson.Gson
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsResolver
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsTld
import io.paritytech.polkadotapp.feature_products_api.domain.error.ProductResolutionError
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.data.manifest.ManifestParser
import io.paritytech.polkadotapp.feature_products_impl.data.repository.ProductRepository
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.times
import org.mockito.Mockito.verify

private const val CID = "QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco"

class RealResolveProductUseCaseTest {
    private val dotNsResolver: DotNsResolver = mock()
    private val productRepository: ProductRepository = mock()
    private val manifestParser = ManifestParser(Gson())

    private val base = "coinflip.dot"
    private val productId = ProductId.fromStoredValue(base)

    private fun useCase() = RealResolveProductUseCase(
        dotNsResolver,
        manifestParser,
        productRepository,
    )

    private fun appJson() = """{"${'$'}v":1,"kind":"app","appVersion":[1,0,0]}"""
    private fun widgetJson() = """{"${'$'}v":1,"kind":"widget","appVersion":[1,0,0],"dimensions":{"height":[1,2]}}"""
    private fun workerJson() =
        """{"${'$'}v":1,"kind":"worker","appVersion":[1,0,0],"entrypoint":"index.js","includes":{"chat":true,"pocket":false}}"""

    private fun rootJson() = """{"${'$'}v":1,"displayName":"Coinflip","description":"d","icon":{"cid":"$CID","format":"png"}}"""

    @Test
    fun `resolves manifest product with all executables`() = runBlocking {
        whenever(dotNsResolver.getMetadataEntry(base, "manifest")).thenReturn(Result.success(rootJson()))
        whenever(dotNsResolver.getMetadataEntry("app.$base", "executable")).thenReturn(Result.success(appJson()))
        whenever(dotNsResolver.getMetadataEntry("widget.$base", "executable")).thenReturn(Result.success(widgetJson()))
        whenever(dotNsResolver.getMetadataEntry("worker.$base", "executable")).thenReturn(Result.success(workerJson()))

        val resolved = useCase().resolve(productId).getOrThrow()

        assertEquals("Coinflip", resolved.product.name)
        assertEquals(CID, resolved.product.icon?.cid?.toString())
        assertEquals(base, resolved.product.id.value)
        assertTrue(resolved.executables.app != null)
        assertTrue(resolved.executables.widget != null)
        assertTrue(resolved.executables.worker != null)
    }

    @Test
    fun `legacy product synthesizes only app`() = runBlocking {
        // No manifest record → legacy product: an APP at the base name, and no worker.
        whenever(dotNsResolver.getMetadataEntry(base, "manifest")).thenReturn(Result.success(null))

        val resolved = useCase().resolve(productId).getOrThrow()

        assertEquals(base, resolved.product.name)
        assertEquals(base, resolved.executables.app?.host?.value)
        assertEquals(null, resolved.executables.widget)
        assertEquals(null, resolved.executables.worker)
    }

    @Test
    fun `surfaces failure when manifest read fails`() = runBlocking {
        whenever(dotNsResolver.getMetadataEntry(base, "manifest"))
            .thenReturn(Result.failure(RuntimeException("registry down")))

        val result = useCase().resolve(productId)

        assertEquals(ProductResolutionError.Unknown, result.exceptionOrNull())
    }

    @Test
    fun `a failed executable read is retryable, not a product without that surface`() = runBlocking {
        whenever(dotNsResolver.getMetadataEntry(base, "manifest")).thenReturn(Result.success(rootJson()))
        whenever(dotNsResolver.getMetadataEntry("app.$base", "executable"))
            .thenReturn(Result.failure(RuntimeException("rpc down")))
        whenever(dotNsResolver.getMetadataEntry("widget.$base", "executable")).thenReturn(Result.success(null))
        whenever(dotNsResolver.getMetadataEntry("worker.$base", "executable")).thenReturn(Result.success(null))

        // Otherwise the miss would cache as "this product has no app" until the process restarts.
        assertTrue(useCase().resolve(productId).isFailure)
    }

    @Test
    fun `a failed resolution is not cached`() = runBlocking {
        whenever(dotNsResolver.getMetadataEntry(base, "manifest"))
            .thenReturn(Result.failure(RuntimeException("registry down")), Result.success(null))
        val useCase = useCase()

        assertTrue(useCase.resolve(productId).isFailure)
        assertTrue(useCase.resolve(productId).isSuccess)
    }

    @Test
    fun `a successful resolution is served from cache`() = runBlocking<Unit> {
        whenever(dotNsResolver.getMetadataEntry(base, "manifest")).thenReturn(Result.success(null))
        val useCase = useCase()

        useCase.resolve(productId).getOrThrow()
        useCase.resolve(productId).getOrThrow()

        verify(dotNsResolver, times(1)).getMetadataEntry(base, "manifest")
    }

    @Test
    fun `an executable subname resolves as its product`() = runBlocking {
        whenever(dotNsResolver.getMetadataEntry(base, "manifest")).thenReturn(Result.success(null))

        val servingHost = ProductId.fromString("APP.$base", DotNsTld.parse("dot")!!).getOrThrow()
        val resolved = useCase().resolve(servingHost).getOrThrow()

        assertEquals(base, resolved.product.id.value)
    }

    @Test
    fun `surfaces failure when manifest record is malformed`() = runBlocking {
        whenever(dotNsResolver.getMetadataEntry(base, "manifest")).thenReturn(Result.success("not json"))

        val result = useCase().resolve(productId)

        assertEquals(ProductResolutionError.MalformedManifest, result.exceptionOrNull())
    }
}
