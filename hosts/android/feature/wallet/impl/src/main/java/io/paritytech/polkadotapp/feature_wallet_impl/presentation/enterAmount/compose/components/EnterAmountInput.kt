package io.paritytech.polkadotapp.feature_wallet_impl.presentation.enterAmount.compose.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.isUnspecified
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.design.utils.conditionalNotNull
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun EnterAmountInput(
    modifier: Modifier = Modifier,
    input: String,
    symbol: String,
    showError: Boolean,
    enabled: Boolean = true,
    focusRequester: FocusRequester? = null,
    onInputChange: (String) -> Unit,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box {
            val maxStyle = PolkadotTheme.typography.display.extraLarge
            val maxFontSize: TextUnit = maxStyle.fontSize
            val minFontSize: TextUnit = PolkadotTheme.typography.body.medium.fontSize

            var boxWidth by remember { mutableIntStateOf(0) }
            var textWidth by remember { mutableIntStateOf(0) }
            val density = LocalDensity.current

            val measuredText = remember(input) { input.ifEmpty { "0" } }

            var currentFontSize by remember { mutableStateOf(maxFontSize) }

            val baseStyle = maxStyle.copy(fontSize = currentFontSize)

            // This text view is needed to keep component height constant
            NovaText(
                modifier = Modifier.alpha(0f),
                text = "0",
                style = maxStyle,
            )

            // This text view is needed to cover autosize behaviour as native compose feature
            BasicText(
                text = measuredText,
                modifier = Modifier
                    .alpha(0f)
                    .onSizeChanged { textWidth = it.width },
                maxLines = 1,
                overflow = TextOverflow.Clip,
                style = baseStyle,
                autoSize = TextAutoSize.StepBased(minFontSize, maxFontSize),
                onTextLayout = { layout ->
                    val resolved = layout.layoutInput.style.fontSize
                    if (!resolved.isUnspecified) currentFontSize = resolved
                    textWidth = layout.size.width
                }
            )

            Box(
                modifier = Modifier.onSizeChanged { boxWidth = it.width },
                contentAlignment = Alignment.Center
            ) {
                val offsetX = with(density) { ((boxWidth - textWidth) / 2).coerceAtLeast(0).toDp() }

                val baseStyle = PolkadotTheme.typography.display.extraLarge
                    .copy(fontSize = currentFontSize)

                Row(
                    modifier = Modifier.offset(x = offsetX),
                ) {
                    BasicTextField(
                        value = input,
                        onValueChange = onInputChange,
                        singleLine = true,
                        enabled = enabled,
                        modifier = Modifier
                            .conditionalNotNull(focusRequester) { focusRequester(it) },
                        cursorBrush = SolidColor(PolkadotTheme.colors.fg.primary),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        textStyle = baseStyle.copy(
                            color = PolkadotTheme.colors.fg.primary,
                        ),
                        decorationBox = { inner ->
                            Box {
                                if (input.isEmpty()) {
                                    NovaText(
                                        text = "0",
                                        style = PolkadotTheme.typography.display.extraLarge,
                                        color = PolkadotTheme.colors.fg.tertiary
                                    )
                                }
                                inner()
                            }
                        }
                    )
                }
            }
        }

        NovaText(
            text = symbol,
            style = PolkadotTheme.typography.title.extraLarge,
            color = PolkadotTheme.colors.fg.secondary
        )

        val errorText =
            if (showError) stringResource(RCommon.string.send_enter_amount_not_enough_funds_error)
            else ""

        NovaText(
            text = errorText,
            style = PolkadotTheme.typography.body.medium,
            color = PolkadotTheme.colors.fg.error,
            textAlign = TextAlign.Center
        )
    }
}

@Preview
@Composable
private fun EnterAmountInputPreview() {
    PolkadotTheme {
        EnterAmountInput(
            input = "",
            symbol = "$",
            showError = true,
            enabled = true,
            onInputChange = {}
        )
    }
}
