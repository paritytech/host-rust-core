package io.paritytech.polkadotapp.feature_products_impl.domain.pocket

import io.paritytech.polkadotapp.feature_products_api.model.JsAlignment
import io.paritytech.polkadotapp.feature_products_api.model.JsArrangement
import io.paritytech.polkadotapp.feature_products_api.model.JsBlendingMode
import io.paritytech.polkadotapp.feature_products_api.model.JsColor
import io.paritytech.polkadotapp.feature_products_api.model.JsEffect
import io.paritytech.polkadotapp.feature_products_api.model.JsImageFit
import io.paritytech.polkadotapp.feature_products_api.model.JsImageSource
import io.paritytech.polkadotapp.feature_products_api.model.JsModifier
import io.paritytech.polkadotapp.feature_products_api.model.JsShape
import io.paritytech.polkadotapp.feature_products_api.model.JsTypographyStyle
import io.paritytech.polkadotapp.feature_products_api.model.JsWidget
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.renderer.RendererNodeJsonDecoder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PocketFaceJsonDecoderTest {
    private val decoder = PocketFaceJsonDecoder(RendererNodeJsonDecoder())

    @Test
    fun `decodes the generated TypeScript shape into the shared widget vocabulary`() {
        val face = decoder.decode(
            """
            {"tag":"Column","value":{
              "modifiers":[
                {"tag":"FillWidth","value":true},
                {"tag":"Padding","value":{"top":16,"end":8}},
                {"tag":"Background","value":{"color":"BgSurfaceContainer","shape":{"tag":"Rounded","value":12}}},
                {"tag":"Height","value":200}
              ],
              "props":{"verticalArrangement":"SpaceBetween"},
              "children":[
                {"tag":"Text","value":{"modifiers":[],"props":{"style":"HeadlineLarge","color":"FgPrimary"},
                  "children":[{"tag":"String","value":{"text":"Loyalty"}}]}},
                {"tag":"Box","value":{"modifiers":[],"props":{"contentAlignment":"CenterEnd"},"children":[{"tag":"Nil"}]}},
                {"tag":"Button","value":{"modifiers":[],"props":{"text":"Open","variant":"Text","clickAction":"open"},"children":[]}},
                {"tag":"Spacer","value":{"modifiers":[{"tag":"Opacity","value":128}]}}
              ]
            }}
            """.trimIndent()
        ).getOrThrow()

        val column = face as JsWidget.Column
        assertEquals(JsArrangement.SPACE_BETWEEN, column.verticalArrangement)
        assertEquals(
            listOf(
                JsModifier.FillMaxWidth(),
                JsModifier.Padding(top = 16, end = 8, bottom = 16, start = 8),
                JsModifier.Background(JsColor.BG_SURFACE_CONTAINER, JsShape.Rounded(12)),
                JsModifier.Size(width = null, height = 200, minWidth = null, minHeight = null),
            ),
            column.modifiers,
        )

        val title = column.children[0] as JsWidget.Text
        assertEquals("Loyalty", title.text)
        assertEquals(JsTypographyStyle.HEADLINE_LARGE, title.style)
        assertEquals(JsColor.FG_PRIMARY, title.color)

        val box = column.children[1] as JsWidget.Box
        assertEquals(JsAlignment.CENTER_END, box.contentAlignment)
        assertTrue("Nil children draw nothing", box.children.isEmpty())

        val button = column.children[2] as JsWidget.Button
        assertEquals("open", button.onClick)

        val spacer = column.children[3] as JsWidget.Spacer
        assertEquals(listOf(JsModifier.Opacity(128)), spacer.modifiers)
    }

    @Test
    fun `decodes the nodes the unified renderer added`() {
        val face = decoder.decode(
            """
            {"tag":"Effect","value":{"props":{"effect":"Rainbow"},"children":[
              {"tag":"Image","value":{
                "modifiers":[{"tag":"Width","value":40},{"tag":"BlendingMode","value":"Multiply"},
                             {"tag":"Border","value":{"width":1,"color":"FgTertiary","shape":{"tag":"Square"}}}],
                "props":{"source":{"tag":"Archive","value":"images/stamp.png"},"fit":"Cover"}}},
              {"tag":"Image","value":{"modifiers":[],"props":{"source":{"tag":"Bulletin","value":"bafy"}}}}
            ]}}
            """.trimIndent()
        ).getOrThrow()

        val effect = face as JsWidget.Effect
        assertEquals(JsEffect.RAINBOW, effect.effect)

        val stamp = effect.children[0] as JsWidget.Image
        assertEquals(JsImageSource.Archive("images/stamp.png"), stamp.source)
        assertEquals(JsImageFit.COVER, stamp.fit)
        assertEquals(
            listOf(
                JsModifier.BlendingMode(JsBlendingMode.MULTIPLY),
                JsModifier.Border(1, JsColor.FG_TERTIARY, JsShape.Square),
                JsModifier.Size(width = 40, height = null, minWidth = null, minHeight = null),
            ),
            stamp.modifiers,
        )

        val remote = effect.children[1] as JsWidget.Image
        assertEquals(JsImageSource.Bulletin("bafy"), remote.source)
        assertEquals("fit defaults to Fill", JsImageFit.FILL, remote.fit)
    }

    @Test
    fun `rejects a tree deeper than the host bound, so a hostile preview cannot blow the stack`() {
        val nested = (1..40).fold("""{"tag":"Nil"}""") { inner, _ ->
            """{"tag":"Box","value":{"modifiers":[],"props":{},"children":[$inner]}}"""
        }

        val failure = decoder.decode(nested).exceptionOrNull()

        assertTrue(failure?.message.orEmpty().contains("deeper than 32"))
    }

    @Test
    fun `a tree exactly at the bound still decodes`() {
        val nested = (1..31).fold("""{"tag":"Nil"}""") { inner, _ ->
            """{"tag":"Box","value":{"modifiers":[],"props":{},"children":[$inner]}}"""
        }

        assertTrue(decoder.decode(nested).isSuccess)
    }

    // A size is read back as an Int when the face is drawn, where a negative padding throws at
    // composition of the card or the approval sheet, taking the screen rather than the one preview.
    @Test
    fun `a size the host cannot draw is refused instead of wrapping into a huge or negative one`() {
        assertTrue(decoder.decode(sizedSpacer("""{"tag":"Padding","value":{"top":-1,"end":0}}""")).isFailure)
        assertTrue(decoder.decode(sizedSpacer("""{"tag":"Width","value":4294967297}""")).isFailure)
        assertTrue(decoder.decode(sizedSpacer("""{"tag":"Width","value":40}""")).isSuccess)
    }

    // 256 wraps to 0, which draws nothing at all rather than reporting a bad preview.
    @Test
    fun `an opacity outside the byte it is carried in is refused`() {
        assertTrue(decoder.decode(sizedSpacer("""{"tag":"Opacity","value":256}""")).isFailure)
        assertTrue(decoder.decode(sizedSpacer("""{"tag":"Opacity","value":-1}""")).isFailure)
        assertTrue(decoder.decode(sizedSpacer("""{"tag":"Opacity","value":255}""")).isSuccess)
    }

    private fun sizedSpacer(modifier: String) = """{"tag":"Spacer","value":{"modifiers":[$modifier]}}"""

    @Test
    fun `unknown nodes, modifiers and enum names are rejected rather than drawn as something else`() {
        assertTrue(decoder.decode("""{"tag":"Video","value":{}}""").isFailure)
        assertTrue(decoder.decode("""{"tag":"Spacer","value":{"modifiers":[{"tag":"Rotate","value":90}]}}""").isFailure)
        assertTrue(decoder.decode("""{"tag":"Text","value":{"props":{"color":"Purple"},"children":[]}}""").isFailure)
        assertTrue(decoder.decode("not json").isFailure)
    }
}
