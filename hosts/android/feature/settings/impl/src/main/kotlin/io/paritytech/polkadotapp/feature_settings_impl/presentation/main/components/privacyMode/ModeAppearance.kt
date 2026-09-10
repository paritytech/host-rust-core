package io.paritytech.polkadotapp.feature_settings_impl.presentation.main.components.privacyMode

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.BoltCircleFilled
import io.paritytech.polkadotapp.design.components.icon.vectors.ShieldHalf
import io.paritytech.polkadotapp.design.components.icon.vectors.VisibilityOffOutlined
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_coinage_api.domain.recycling.RecyclingStrategyType
import io.paritytech.polkadotapp.common.R as RCommon

@Immutable
internal data class ModeAppearance(
    val label: String,
    val description: String,
    val accessibilityDescription: String,
    val icon: ImageVector,
    // Fills the circle, tints the marker, and seeds every shade derived from them.
    val accentColor: Color,
    val iconColor: Color
)

@Composable
internal fun RecyclingStrategyType.appearance(): ModeAppearance {
    // Every accent below is the same value in all palettes, so one light glyph colour is chosen here and
    // holds in both themes.
    val onDarkAccent = PolkadotTheme.colors.fg.staticWhite

    return when (this) {
        RecyclingStrategyType.MIN_PRIVACY -> ModeAppearance(
            label = stringResource(RCommon.string.payment_privacy_mode_fastest_label),
            description = stringResource(RCommon.string.payment_privacy_mode_fastest_description),
            accessibilityDescription = stringResource(RCommon.string.payment_privacy_mode_fastest_accessibility),
            icon = NovaIcons.BoltCircleFilled,
            accentColor = PolkadotTheme.colors.bg.status.warning,
            iconColor = onDarkAccent
        )

        RecyclingStrategyType.BALANCED -> ModeAppearance(
            label = stringResource(RCommon.string.payment_privacy_mode_balanced_label),
            description = stringResource(RCommon.string.payment_privacy_mode_balanced_description),
            accessibilityDescription = stringResource(RCommon.string.payment_privacy_mode_balanced_accessibility),
            icon = NovaIcons.ShieldHalf,
            accentColor = PolkadotTheme.colors.bg.status.success,
            iconColor = onDarkAccent
        )

        RecyclingStrategyType.MAX_PRIVACY -> ModeAppearance(
            label = stringResource(RCommon.string.payment_privacy_mode_most_private_label),
            description = stringResource(RCommon.string.payment_privacy_mode_most_private_description),
            accessibilityDescription = stringResource(
                RCommon.string.payment_privacy_mode_most_private_accessibility
            ),
            icon = NovaIcons.VisibilityOffOutlined,
            accentColor = PolkadotTheme.colors.avatar.bg.amethyst,
            iconColor = onDarkAccent
        )
    }
}

// The design system carries one flat accent per mode, while the design asks for a lit sphere. The shades are
// therefore derived from that accent rather than tokenised: mixing towards the palette's own static white and
// onyx keeps every theme self-consistent, which hardcoded hex values would not.
// [selection] is the animated 0..1 selectedness of the mode, so a mode lights up and dims in step with the
// circle growing and shrinking instead of switching colour a frame apart from it.
@Composable
internal fun ModeAppearance.circleBrush(selection: Float): Brush {
    val light = PolkadotTheme.colors.fg.staticWhite
    val dark = PolkadotTheme.colors.avatar.bg.onyx

    val top = lerp(
        lerp(accentColor, dark, MUTED_TOP_SHADE),
        lerp(accentColor, light, SELECTED_TOP_TINT),
        selection
    )
    val bottom = lerp(
        lerp(accentColor, dark, MUTED_BOTTOM_SHADE),
        lerp(accentColor, dark, SELECTED_BOTTOM_SHADE),
        selection
    )

    return Brush.verticalGradient(listOf(top, bottom))
}

@Composable
internal fun ModeAppearance.circleBorderBrush(): Brush {
    val light = PolkadotTheme.colors.fg.staticWhite
    val dark = PolkadotTheme.colors.avatar.bg.onyx

    return remember(accentColor, light, dark) {
        Brush.verticalGradient(
            listOf(
                lerp(accentColor, light, BORDER_TOP_TINT),
                lerp(accentColor, dark, BORDER_BOTTOM_SHADE)
            )
        )
    }
}

@Composable
internal fun ModeAppearance.markerColor(selection: Float): Color {
    val dark = PolkadotTheme.colors.avatar.bg.onyx

    return lerp(lerp(accentColor, dark, MARKER_MUTED_SHADE), accentColor, selection)
}

// A dragged circle takes on the mode it is nearest to, so it changes appearance mid-gesture. Swapping the
// accent in a single frame is what reads as a jump; blending it lets the colour travel together with the
// glyph cross-fade in [ModeCircle]. [fraction] is 0 while the circle still shows [previous] and 1 once it
// has fully become this mode.
internal fun ModeAppearance.accentBlendedFrom(previous: ModeAppearance, fraction: Float): ModeAppearance =
    copy(accentColor = lerp(previous.accentColor, accentColor, fraction))

private const val SELECTED_TOP_TINT = 0.1f
private const val SELECTED_BOTTOM_SHADE = 0.35f

private const val MUTED_TOP_SHADE = 0.25f
private const val MUTED_BOTTOM_SHADE = 0.55f

private const val BORDER_TOP_TINT = 0.4f
private const val BORDER_BOTTOM_SHADE = 0.55f

private const val MARKER_MUTED_SHADE = 0.45f
