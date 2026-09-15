package io.paritytech.polkadotapp.feature_settings_impl.domain.model

enum class Language(
    val code: String,
    val flag: String,
    val nativeName: String,
    val englishName: String
) {
    ENGLISH("en", "🇺🇸", "English", "English"),
    SPANISH("es", "🇪🇸", "Español", "Spanish");

    companion object {
        val DEFAULT = ENGLISH
    }
}

fun Language.Companion.fromCode(code: String?): Language {
    return Language.entries.find { it.code == code } ?: DEFAULT
}
