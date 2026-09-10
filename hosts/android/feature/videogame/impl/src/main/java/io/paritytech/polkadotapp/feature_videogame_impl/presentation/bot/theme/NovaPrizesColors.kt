package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.lerp

internal object NovaPrizesColors {
    val backgroundGradientTop = Color(0xFF15152E)
    val backgroundGradientBottom = Color(0xFF28245B)

    // Solid white-12%-over-background equivalent, so borders read the same regardless of bubble fill.
    val cardStroke = Color.White.copy(alpha = 0.12f)
        .compositeOver(lerp(backgroundGradientTop, backgroundGradientBottom, 0.5f))

    val cardInnerBg = Color(0xFF141023)
    val chatWithPlayersBackground = Color(0xFF131338)

    val chatBubbleBackground = Color(0xFF292A5B)
    val chatBubbleBorder = cardStroke

    val dateSeparatorBackground = Color(0xFF1F1D45)
    val dateSeparatorText = Color(0xFF878696)

    val pastGameSecondaryText = Color.White.copy(alpha = 0.69f)
    val pastGameCardBorder = cardStroke
    val gameSucceededAccent = Color(0xFF0ABE71)
    val gameEndedTitle = Color.White.copy(alpha = 0.48f)

    // Fixed colors lifted from the BerlinNight theme so the in-chat Prize UI keeps its palette
    // regardless of the selected app theme.
    val textPrimary = Color(0xFFF4F4F5) // fg.primary / ZincZinc100
    val textSecondary = Color(0xFF8C8F98) // fg.secondary / ZincZinc400
    val textTertiary = Color(0xFF585B62) // fg.tertiary / ZincZinc600
    val warning = Color(0xFFF59E0B) // fg.warning / AmberAmber500
    val avatarRing = Color(0xFFFFFFFF) // bg.surface.containerInverted / NeutralWhite
    val avatarPlaceholderBg = Color(0xFF1A1B20) // bg.surface.container / ZincZinc900
    val disabledCtaBorder = Color(0xFF23252A) // stroke.primary / ZincZinc850

    // Prize bottom-sheet surface, pinned so modal sheets don't flip to a light surface on light themes.
    val bottomSheetBackground = Color(0xFF23252A) // bg.surface.nested / ZincZinc850
    val bottomSheetDivider = Color(0xFF404249) // stroke.secondary / ZincZinc700

    // Upgrade-username CTA, pinned to the inverse (white/black) chat tokens instead of the theme.
    val upgradeUsernameCtaBackground = Color(0xFFFFFFFF) // background/background_inverse
    val upgradeUsernameCtaContent = Color(0xFF000000) // text_and_icons/text_and_icons_inverse_primary

    val memberBannerBlueGradientTop = Color(0xFF3A59E5)
    val memberBannerBlueGradientBottom = Color(0xFF513DA7)

    val memberBannerGreenGradientTop = Color(0xFF6ADF6F)
    val memberBannerGreenGradientBottom = Color(0xFF227C4A)

    val memberBannerYellowGradientTop = Color(0xFFFFD166)
    val memberBannerYellowGradientBottom = Color(0xFFB87900)

    val memberBannerLightText = Color.White
    val memberBannerDarkText = Color.Black.copy(alpha = 0.7f)

    val stickerBlueStrokeTop = Color(0xFF3B60F5)
    val stickerBlueStrokeMid = Color(0xFF353FB7)
    val stickerBlueStrokeBottom = Color(0xFF503DA7)
    val stickerBlueHalo = Color(0xFF324BC3)

    val stickerGreenStrokeTop = Color(0xFF6BE170)
    val stickerGreenStrokeBottom = Color(0xFF227C4A)
    val stickerGreenHalo = Color(0xFF6BE170)

    val stickerYellowStrokeTop = Color(0xFFFFB300)
    val stickerYellowStrokeBottom = Color(0xFFB87900)
    val stickerYellowHalo = Color(0xFFFFB300)

    val registerCtaDisabledContent = Color.White.copy(alpha = 0.4f)

    val registerCtaTopBlue = Color(0xFF3B62FA)
    val registerCtaMidBlue = Color(0xFF343FB7)
    val registerCtaBottomPurple = Color(0xFF543CA5)
    val registerCtaGlow = Color(0xFF0E0F40)
    val registerCtaDisabled = Color(0xFF2A2F45)

    val addToCalendarCtaTop = Color(0xFF6BE070)
    val addToCalendarCtaMid = Color(0xFF49B35F)
    val addToCalendarCtaBottom = Color(0xFF227C4A)
    val addToCalendarCtaGlow = Color(0xFF69DE6F)
    val addToCalendarCtaDisabled = Color(0xFF131338)
    val addToCalendarCtaDisabledContent = Color(0x45FFFFFF)
}
