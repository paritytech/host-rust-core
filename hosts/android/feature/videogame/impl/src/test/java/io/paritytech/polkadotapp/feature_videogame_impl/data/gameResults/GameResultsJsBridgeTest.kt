package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import junit.framework.TestCase.assertEquals
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Test

class GameResultsJsBridgeTest {
    @Test
    fun `decodes flow_ready`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.ready"}""")
        assertEquals(FlowEvent.Ready, bridge.events.first())
    }

    @Test
    fun `decodes flow_results_shown`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.results_shown"}""")
        assertEquals(FlowEvent.ResultsShown, bridge.events.first())
    }

    @Test
    fun `decodes flow_prize_draw_started`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.prize_draw_started"}""")
        assertEquals(FlowEvent.PrizeDrawStarted, bridge.events.first())
    }

    @Test
    fun `decodes flow_prize_draw_complete with won true`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.prize_draw_complete","won":true}""")
        assertEquals(FlowEvent.PrizeDrawComplete(won = true), bridge.events.first())
    }

    @Test
    fun `decodes flow_prize_draw_complete with missing won as false`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.prize_draw_complete"}""")
        assertEquals(FlowEvent.PrizeDrawComplete(won = false), bridge.events.first())
    }

    @Test
    fun `decodes flow_nft_reveal_started with count`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.nft_reveal_started","count":10}""")
        assertEquals(FlowEvent.NftRevealStarted(count = 10), bridge.events.first())
    }

    @Test
    fun `decodes flow_nft_reveal_complete`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.nft_reveal_complete"}""")
        assertEquals(FlowEvent.NftRevealComplete, bridge.events.first())
    }

    @Test
    fun `decodes flow_username_claim_requested`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.username_claim_requested"}""")
        assertEquals(FlowEvent.UsernameClaimRequested, bridge.events.first())
    }

    @Test
    fun `decodes flow_request_display_name`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.request_display_name"}""")
        assertEquals(FlowEvent.RequestDisplayName, bridge.events.first())
    }

    @Test
    fun `decodes flow_username_availability_needed with name`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.username_availability_needed","name":"byteboro"}""")
        assertEquals(
            FlowEvent.UsernameAvailabilityNeeded(name = "byteboro"),
            bridge.events.first()
        )
    }

    @Test
    fun `decodes flow_error with phase and detail`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.error","phase":"assets","detail":"composite_failures=2"}""")
        assertEquals(
            FlowEvent.Error(phase = "assets", detail = "composite_failures=2"),
            bridge.events.first()
        )
    }

    @Test
    fun `decodes flow_error with missing detail as null`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.error","phase":"boot_timeout"}""")
        assertEquals(
            FlowEvent.Error(phase = "boot_timeout", detail = null),
            bridge.events.first()
        )
    }

    @Test
    fun `decodes flow_complete`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"flow.complete"}""")
        assertEquals(FlowEvent.Complete, bridge.events.first())
    }

    @Test
    fun `unknown type lands as Unknown`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("""{"type":"future_event"}""")
        assertEquals(FlowEvent.Unknown(type = "future_event"), bridge.events.first())
    }

    @Test
    fun `malformed json is silently dropped`() = runBlocking<Unit> {
        val bridge = GameResultsJsBridge()
        bridge.postMessage("not-json")
        bridge.postMessage("""{"type":"flow.ready"}""")
        assertEquals(FlowEvent.Ready, bridge.events.first())
    }
}
