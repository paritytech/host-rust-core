package io.paritytech.polkadotapp.common.presentation.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import io.paritytech.polkadotapp.common.utils.CurrencyConfig
import io.paritytech.polkadotapp.design.theme.lightCounterpart

@Composable
fun String.withCurrencyTickerStyle(style: TextStyle): AnnotatedString {
    val spanStyle = rememberTickerSpanStyle(style)

    return remember(this, spanStyle) {
        buildAnnotatedString {
            append(this@withCurrencyTickerStyle)
            styleTickerOccurrences(this@withCurrencyTickerStyle, spanStyle)
        }
    }
}

@Composable
fun AnnotatedString.withCurrencyTickerStyle(style: TextStyle): AnnotatedString {
    val spanStyle = rememberTickerSpanStyle(style)

    return remember(this, spanStyle) {
        buildAnnotatedString {
            append(this@withCurrencyTickerStyle)
            styleTickerOccurrences(this@withCurrencyTickerStyle.text, spanStyle)
        }
    }
}

internal fun tickerRanges(source: String, ticker: String): List<TextRange> {
    if (ticker.isEmpty()) return emptyList()

    val ranges = mutableListOf<TextRange>()
    var start = source.indexOf(ticker)

    while (start >= 0) {
        val end = start + ticker.length
        if (source.standsAlone(start, end)) ranges += TextRange(start, end)
        start = source.indexOf(ticker, end)
    }

    return ranges
}

@Composable
private fun rememberTickerSpanStyle(style: TextStyle): SpanStyle {
    val family = style.fontFamily

    return remember(family) {
        val light = family.lightCounterpart()
        SpanStyle(fontFamily = light, fontWeight = light?.let { FontWeight.Light })
    }
}

private fun AnnotatedString.Builder.styleTickerOccurrences(source: String, spanStyle: SpanStyle) {
    tickerRanges(source, CurrencyConfig.symbol).forEach { range ->
        addStyle(style = spanStyle, start = range.start, end = range.end)
    }
}

private fun String.standsAlone(start: Int, end: Int): Boolean =
    getOrNull(start - 1)?.isLetterOrDigit() != true && getOrNull(end)?.isLetterOrDigit() != true
