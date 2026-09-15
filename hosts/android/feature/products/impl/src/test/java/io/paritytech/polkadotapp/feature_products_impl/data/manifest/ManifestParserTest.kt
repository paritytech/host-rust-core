package io.paritytech.polkadotapp.feature_products_impl.data.manifest

import com.google.gson.Gson
import io.paritytech.polkadotapp.feature_products_api.model.ExecutableHost
import io.paritytech.polkadotapp.feature_products_api.model.ExecutableKind
import io.paritytech.polkadotapp.feature_products_api.model.ProductExecutable
import io.paritytech.polkadotapp.feature_products_api.model.ProductIcon
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private const val CID = "QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco"

class ManifestParserTest {
    private val parser = ManifestParser(Gson())

    private fun host(value: String) = ExecutableHost(value)

    private fun rejects(rawText: String) = assertTrue(
        "expected a rejection for $rawText",
        parser.parseRoot(rawText).isFailure,
    )

    private fun rejectsExecutable(rawText: String, kind: ExecutableKind) = assertTrue(
        "expected a rejection for $rawText",
        parser.parseExecutable(rawText, kind, host("${kind.manifestKind}.coinflip.dot")).isFailure,
    )

    @Test
    fun `parses valid root manifest`() {
        val root = parser.parseRoot(
            """{"${'$'}v":1,"displayName":"Coinflip","description":"A game","icon":{"cid":"$CID","format":"png"}}"""
        ).getOrNull()

        assertEquals("Coinflip", root?.displayName)
        assertEquals(CID, root?.icon?.cid?.toString())
        assertEquals(ProductIcon.Format.PNG, root?.icon?.format)
    }

    @Test
    fun `root manifests that a stricter host would reject do not load here either`() {
        // Unknown schema version, malformed JSON, and every RFC-0001 required field in turn.
        rejects("""{"${'$'}v":2,"displayName":"X","description":"d","icon":{"cid":"$CID","format":"png"}}""")
        rejects("not json")
        rejects("")
        rejects("""{"${'$'}v":1,"description":"d","icon":{"cid":"$CID","format":"png"}}""")
        rejects("""{"${'$'}v":1,"displayName":"X","icon":{"cid":"$CID","format":"png"}}""")
        rejects("""{"${'$'}v":1,"displayName":"X","description":"d"}""")
        rejects("""{"${'$'}v":1,"displayName":"X","description":"d","icon":{"format":"png"}}""")
        rejects("""{"${'$'}v":1,"displayName":"X","description":"d","icon":{"cid":"not-a-cid","format":"png"}}""")
    }

    @Test
    fun `root with unsupported icon format stays launchable without an icon`() {
        // RFC-0001: unknown icon format renders a placeholder; the product remains launchable.
        val root = parser.parseRoot(
            """{"${'$'}v":1,"displayName":"Coinflip","description":"d","icon":{"cid":"$CID","format":"gif"}}"""
        ).getOrNull()

        assertEquals("Coinflip", root?.displayName)
        assertNull(root?.icon)
    }

    @Test
    fun `parses app executable`() {
        val app = parser.parseExecutable(
            """{"${'$'}v":1,"kind":"app","appVersion":[1,2,3]}""",
            ExecutableKind.APP,
            host("app.coinflip.dot"),
        ).getOrNull() as? ProductExecutable.App

        assertEquals(host("app.coinflip.dot"), app?.host)
        assertEquals("1.2.3", app?.appVersion.toString())
    }

    @Test
    fun `parses widget executable with dimensions`() {
        val widget = parser.parseExecutable(
            """{"${'$'}v":1,"kind":"widget","appVersion":[0,1,0],"description":"w","dimensions":{"height":[1,2],"width":3}}""",
            ExecutableKind.WIDGET,
            host("widget.coinflip.dot"),
        ).getOrNull() as? ProductExecutable.Widget

        assertEquals(listOf(1, 2), widget?.heights)
        assertEquals(3, widget?.width)
        assertEquals("w", widget?.description)
    }

    @Test
    fun `widget without width defaults to one column`() {
        val widget = parser.parseExecutable(
            """{"${'$'}v":1,"kind":"widget","appVersion":[0,1,0],"dimensions":{"height":[2]}}""",
            ExecutableKind.WIDGET,
            host("widget.coinflip.dot"),
        ).getOrNull() as? ProductExecutable.Widget

        assertEquals(1, widget?.width)
    }

    @Test
    fun `parses worker executable and formats semver build`() {
        val worker = parser.parseExecutable(
            """{"${'$'}v":1,"kind":"worker","appVersion":[1,0,0,"abc"],"entrypoint":"index.js","includes":{"chat":true,"pocket":false}}""",
            ExecutableKind.WORKER,
            host("worker.coinflip.dot"),
        ).getOrNull() as? ProductExecutable.Worker

        assertEquals("https://worker.coinflip.dot/index.js", worker?.scriptUrl)
        assertEquals("1.0.0+abc", worker?.appVersion.toString())
        assertEquals(true, worker?.includesChat)
        assertEquals(false, worker?.includesPocket)
    }

    @Test
    fun `worker with no included surface is a valid background-only worker`() {
        // RFC: includes { chat: false, pocket: false } is valid — a worker that exposes no
        // user-facing surface and runs purely as background logic.
        val worker = parser.parseExecutable(
            """{"${'$'}v":1,"kind":"worker","appVersion":[1,0,0],"entrypoint":"index.js","includes":{"chat":false,"pocket":false}}""",
            ExecutableKind.WORKER,
            host("worker.coinflip.dot"),
        ).getOrNull() as? ProductExecutable.Worker

        assertEquals(false, worker?.includesChat)
        assertEquals(false, worker?.includesPocket)
    }

    @Test
    fun `executables that do not conform are rejected`() {
        // Incomplete includes: RFC-0001 types it as Record<'chat' | 'pocket', boolean>.
        rejectsExecutable("""{"${'$'}v":1,"kind":"worker","appVersion":[1,0,0],"entrypoint":"i.js","includes":{"chat":true}}""", ExecutableKind.WORKER)
        // A record read from worker.<base> that declares kind=app must not load as a worker.
        rejectsExecutable("""{"${'$'}v":1,"kind":"app","appVersion":[1,0,0]}""", ExecutableKind.WORKER)
        rejectsExecutable("""{"${'$'}v":2,"kind":"app","appVersion":[1,0,0]}""", ExecutableKind.APP)
        rejectsExecutable("""{"${'$'}v":1,"kind":"app","appVersion":[1,2]}""", ExecutableKind.APP)
        rejectsExecutable("""{"${'$'}v":1,"kind":"app","appVersion":[1,2,3,4,5]}""", ExecutableKind.APP)
        rejectsExecutable("""{"${'$'}v":1,"kind":"app"}""", ExecutableKind.APP)
        rejectsExecutable("""{"${'$'}v":1,"kind":"widget","appVersion":[1,0,0],"dimensions":{"height":[]}}""", ExecutableKind.WIDGET)
    }
}
