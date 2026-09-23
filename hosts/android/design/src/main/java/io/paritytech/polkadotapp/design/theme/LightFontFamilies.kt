@file:OptIn(ExperimentalTextApi::class)

package io.paritytech.polkadotapp.design.theme

import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import io.paritytech.polkadotapp.designsystem.typography.PolkadotFontFamilies
import io.paritytech.polkadotapp.designsystem.R as RDesignSystem

private val lightVariation = FontVariation.Settings(FontVariation.weight(FontWeight.Light.weight))

private val interLight = FontFamily(
    Font(RDesignSystem.font.inter_variable, FontWeight.Light, variationSettings = lightVariation)
)

private val manropeLight = FontFamily(
    Font(RDesignSystem.font.manrope_variable, FontWeight.Light, variationSettings = lightVariation)
)

private val martianMonoLight = FontFamily(
    Font(RDesignSystem.font.martian_mono_variable, FontWeight.Light, variationSettings = lightVariation)
)

// The design system declares nothing below Normal for Inter or SemiBold for Manrope, so asking
// for FontWeight.Light alone snaps to the nearest declared face instead of thinning the text.
fun FontFamily?.lightCounterpart(): FontFamily? = when (this) {
    PolkadotFontFamilies.inter -> interLight
    PolkadotFontFamilies.manrope -> manropeLight
    PolkadotFontFamilies.martianMono -> martianMonoLight
    else -> null
}
