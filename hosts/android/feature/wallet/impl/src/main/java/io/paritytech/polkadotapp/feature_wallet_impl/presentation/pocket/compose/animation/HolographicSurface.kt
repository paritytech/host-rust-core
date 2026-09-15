package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation

import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.ui.Modifier

@Composable
internal fun Modifier.holographicSurface(
    tiltState: State<TiltState>,
    lagged: Boolean = false
): Modifier = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    holographicShader(tiltState, lagged)
} else {
    holographicFallback(tiltState, lagged)
}
