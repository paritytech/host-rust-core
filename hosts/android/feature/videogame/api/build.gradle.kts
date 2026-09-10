plugins {
    id("polkadotapp.android.library")
    alias(libs.plugins.kotlin.serialization)
}
android {
    namespace = "io.paritytech.polkadotapp.feature_videogame_api"
}
dependencies {
    api(project(":common"))
    api(project(":chains"))
    api(project(":feature:account:api"))
    api(project(":feature:balances:api"))
    api(project(":feature:transactions:api"))
}
