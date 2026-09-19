package io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase

private val LOG_ENTRY_START = Regex("""^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}""")

// Filter whole entries, not individual lines. Each entry starts with a timestamp and tag
// stack trace lines belong to that entry but have no tag, so line-by-line filtering would discard
// the stack traces the export exists to preserve.
internal fun Sequence<String>.filterLogEntries(tags: Set<String>, maxLines: Int): List<String> {
    val lines = ArrayDeque<String>()
    var inRetainedEntry = false

    forEach { line ->
        if (LOG_ENTRY_START.containsMatchIn(line)) {
            inRetainedEntry = tags.any { it in line }
        }

        if (inRetainedEntry) {
            lines.addLast(line)
            if (lines.size > maxLines) lines.removeFirst()
        }
    }

    return lines
}
