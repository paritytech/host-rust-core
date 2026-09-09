package io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.upgrade.compose

import androidx.compose.ui.graphics.Color

internal object UpgradeUsernameScreenColors {
    val screenBg = Color(0xFF292A5B)

    val primaryText = Color.White // text_and_icons_primary
    val description = Color.White.copy(alpha = 0.48f) // text_and_icons_tertiary
    val placeholder = Color.White.copy(alpha = 0.48f) // text_and_icons_tertiary

    val fieldNeutralBorder = Color.White.copy(alpha = 0.30f)
    val fieldNeutralBg = Color.White.copy(alpha = 0.05f)
    val available = Color(0xFF35C759) // colors/green
    val availableBg = available.copy(alpha = 0.12f) // colors/green_12
    val error = Color(0xFFFF3123) // colors/red
    val errorBg = error.copy(alpha = 0.12f)
    val errorPillBg = Color.White.copy(alpha = 0.12f) // fills/fill_12

    val ctaBackground = Color.White // background/background_inverse
    val ctaContent = Color.Black // text_and_icons_inverse_primary
    val ctaDisabledBackground = Color.White.copy(alpha = 0.30f)
    val ctaDisabledContent = Color.Black.copy(alpha = 0.40f)
}
