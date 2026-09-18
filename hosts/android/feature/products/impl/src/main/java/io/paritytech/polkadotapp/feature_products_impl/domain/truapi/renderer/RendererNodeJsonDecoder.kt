package io.paritytech.polkadotapp.feature_products_impl.domain.truapi.renderer

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import uniffi.truapi.Arrangement
import uniffi.truapi.Background
import uniffi.truapi.BlendingMode
import uniffi.truapi.BorderStyle
import uniffi.truapi.BoxProps
import uniffi.truapi.ButtonProps
import uniffi.truapi.ButtonVariant
import uniffi.truapi.ColorToken
import uniffi.truapi.ColumnProps
import uniffi.truapi.ContentAlignment
import uniffi.truapi.Dimensions
import uniffi.truapi.Effect
import uniffi.truapi.EffectProps
import uniffi.truapi.HorizontalAlignment
import uniffi.truapi.ImageFit
import uniffi.truapi.ImageProps
import uniffi.truapi.ImageSource
import uniffi.truapi.Modifier
import uniffi.truapi.RendererNode
import uniffi.truapi.RowProps
import uniffi.truapi.Shape
import uniffi.truapi.Size
import uniffi.truapi.TextFieldProps
import uniffi.truapi.TextProps
import uniffi.truapi.TypographyStyle
import uniffi.truapi.VerticalAlignment
import java.math.BigInteger
import javax.inject.Inject

/**
 * Reads a renderer tree written in the generated TypeScript shape (`{ tag, value }` per variant,
 * PascalCase enum names) into the same node type the core streams, so a static preview and a live
 * face go through one mapping. Trees deeper than [MAX_DEPTH] are rejected.
 */
class RendererNodeJsonDecoder @Inject constructor() {
    fun decode(json: String): Result<RendererNode> = runCatching {
        Json.parseToJsonElement(json).toNode(depth = 1)
    }

    private fun JsonElement.toNode(depth: Int): RendererNode {
        require(depth <= MAX_DEPTH) { "renderer tree deeper than $MAX_DEPTH levels" }
        val node = jsonObject
        val value = node.variantValue()
        return when (val tag = node.tag()) {
            "Nil" -> RendererNode.Nil
            "String" -> RendererNode.String(value.string("text"))
            "Box" -> RendererNode.Box(
                modifiers = value.modifiers(),
                props = BoxProps(contentAlignment = value.props().enumOrNull<ContentAlignment>("contentAlignment")),
                children = value.children(depth),
            )
            "Column" -> RendererNode.Column(
                modifiers = value.modifiers(),
                props = value.props().let {
                    ColumnProps(
                        horizontalAlignment = it.enumOrNull<HorizontalAlignment>("horizontalAlignment"),
                        verticalArrangement = it.enumOrNull<Arrangement>("verticalArrangement"),
                    )
                },
                children = value.children(depth),
            )
            "Row" -> RendererNode.Row(
                modifiers = value.modifiers(),
                props = value.props().let {
                    RowProps(
                        verticalAlignment = it.enumOrNull<VerticalAlignment>("verticalAlignment"),
                        horizontalArrangement = it.enumOrNull<Arrangement>("horizontalArrangement"),
                    )
                },
                children = value.children(depth),
            )
            "Spacer" -> RendererNode.Spacer(modifiers = value.modifiers())
            "Text" -> RendererNode.Text(
                modifiers = value.modifiers(),
                props = value.props().let {
                    TextProps(
                        style = it.enumOrNull<TypographyStyle>("style"),
                        color = it.enumOrNull<ColorToken>("color"),
                    )
                },
                children = value.children(depth),
            )
            "Button" -> RendererNode.Button(
                modifiers = value.modifiers(),
                props = value.props().let {
                    ButtonProps(
                        text = it.string("text"),
                        variant = it.enumOrNull<ButtonVariant>("variant"),
                        enabled = it.booleanOrNull("enabled"),
                        loading = it.booleanOrNull("loading"),
                        clickAction = it.stringOrNull("clickAction"),
                    )
                },
                children = value.children(depth),
            )
            "TextField" -> RendererNode.TextField(
                modifiers = value.modifiers(),
                props = value.props().let {
                    TextFieldProps(
                        text = it.string("text"),
                        placeholder = it.stringOrNull("placeholder"),
                        label = it.stringOrNull("label"),
                        enabled = it.booleanOrNull("enabled"),
                        valueChangeAction = it.stringOrNull("valueChangeAction"),
                    )
                },
            )
            "Image" -> RendererNode.Image(
                modifiers = value.modifiers(),
                props = value.props().let {
                    ImageProps(
                        source = it.required("source").toImageSource(),
                        fit = it.enumOrNull<ImageFit>("fit"),
                    )
                },
            )
            "Effect" -> RendererNode.Effect(
                props = EffectProps(effect = value.props().enum<Effect>("effect")),
                children = value.children(depth),
            )
            else -> throw IllegalArgumentException("unknown renderer node '$tag'")
        }
    }

    private fun JsonObject.children(depth: Int): List<RendererNode> =
        this["children"]?.jsonArray?.map { it.toNode(depth + 1) }.orEmpty()

    private fun JsonObject.modifiers(): List<Modifier> =
        this["modifiers"]?.jsonArray?.map { it.toModifier() }.orEmpty()

    private fun JsonElement.toModifier(): Modifier {
        val modifier = jsonObject
        val value = modifier.required("value")
        return when (val tag = modifier.tag()) {
            "Margin" -> Modifier.Margin(value.jsonObject.dimensions())
            "Padding" -> Modifier.Padding(value.jsonObject.dimensions())
            "Background" -> Modifier.Background(
                value.jsonObject.let { Background(color = it.enum<ColorToken>("color"), shape = it.shapeOrNull()) },
            )
            "Border" -> Modifier.Border(
                value.jsonObject.let {
                    BorderStyle(width = it.size("width"), color = it.enum<ColorToken>("color"), shape = it.shapeOrNull())
                },
            )
            "Height" -> Modifier.Height(value.toSize())
            "Width" -> Modifier.Width(value.toSize())
            "MinWidth" -> Modifier.MinWidth(value.toSize())
            "MinHeight" -> Modifier.MinHeight(value.toSize())
            "FillWidth" -> Modifier.FillWidth(value.jsonPrimitive.content.toBooleanStrict())
            "FillHeight" -> Modifier.FillHeight(value.jsonPrimitive.content.toBooleanStrict())
            "Opacity" -> Modifier.Opacity(value.toOpacity())
            "BlendingMode" -> Modifier.BlendingMode(value.toEnum<BlendingMode>())
            else -> throw IllegalArgumentException("unknown renderer modifier '$tag'")
        }
    }

    private fun JsonElement.toImageSource(): ImageSource {
        val source = jsonObject
        val value = source.required("value").jsonPrimitive.content
        return when (val tag = source.tag()) {
            "Bulletin" -> ImageSource.Bulletin(value)
            "Archive" -> ImageSource.Archive(value)
            else -> throw IllegalArgumentException("unknown image source '$tag'")
        }
    }

    private fun JsonObject.shapeOrNull(): Shape? {
        val shape = present("shape")?.jsonObject ?: return null
        return when (val tag = shape.tag()) {
            "Rounded" -> Shape.Rounded(shape.required("value").toSize())
            "Circle" -> Shape.Circle
            "Square" -> Shape.Square
            else -> throw IllegalArgumentException("unknown renderer shape '$tag'")
        }
    }

    private fun JsonObject.dimensions() = Dimensions(
        top = size("top"),
        end = size("end"),
        bottom = present("bottom")?.toSize(),
        start = present("start")?.toSize(),
    )

    private fun JsonObject.tag(): String = string("tag")

    // Unit variants carry no `value`; every field read off an absent one then fails as missing.
    private fun JsonObject.variantValue(): JsonObject = present("value")?.jsonObject ?: JsonObject(emptyMap())

    private fun JsonObject.props(): JsonObject = present("props")?.jsonObject ?: JsonObject(emptyMap())

    private fun JsonObject.present(key: String): JsonElement? = this[key]?.takeUnless { it is JsonNull }

    private fun JsonObject.required(key: String): JsonElement =
        requireNotNull(present(key)) { "renderer node missing '$key'" }

    private fun JsonObject.string(key: String): String = required(key).jsonPrimitive.content

    private fun JsonObject.stringOrNull(key: String): String? = present(key)?.jsonPrimitive?.content

    private fun JsonObject.booleanOrNull(key: String): Boolean? =
        present(key)?.jsonPrimitive?.content?.toBooleanStrict()

    private fun JsonObject.size(key: String): Size = required(key).toSize()

    /**
     * A size the host cannot draw is refused here rather than carried on. The mapping to Compose
     * reads it back as an Int, where a negative padding throws at composition of whatever shows the
     * face, and anything past Int.MAX silently truncates into a different number.
     */
    private fun JsonElement.toSize(): Size {
        val value = jsonPrimitive.content.toBigDecimal().toBigIntegerExact()
        require(value >= BigInteger.ZERO && value <= MAX_SIZE) { "renderer size out of range: $value" }

        return value.toLong().toULong()
    }

    // Anything outside 0..255 wraps into a different opacity, 256 into fully transparent.
    private fun JsonElement.toOpacity(): UByte = requireNotNull(jsonPrimitive.content.toUByteOrNull()) {
        "renderer opacity out of range: ${jsonPrimitive.content}"
    }

    private inline fun <reified E : Enum<E>> JsonObject.enum(key: String): E = required(key).toEnum()

    private inline fun <reified E : Enum<E>> JsonObject.enumOrNull(key: String): E? =
        present(key)?.let { it.toEnum<E>() }

    // "BgSurfaceMain" names the Kotlin constant BG_SURFACE_MAIN.
    private inline fun <reified E : Enum<E>> JsonElement.toEnum(): E =
        enumValueOf<E>(jsonPrimitive.content.replace(WORD_BOUNDARY, "_").uppercase())

    private companion object {
        const val MAX_DEPTH = 32
        val MAX_SIZE: BigInteger = BigInteger.valueOf(Int.MAX_VALUE.toLong())
        val WORD_BOUNDARY = Regex("(?<=[a-z0-9])(?=[A-Z])")
    }
}
