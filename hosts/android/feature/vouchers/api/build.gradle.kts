plugins {
    id("polkadotapp.android.library")
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "io.paritytech.polkadotapp.feature_vouchers_api"
}

dependencies {
    api(project(":chains"))
    api(project(":common"))

    api(project(":feature:balances:api"))
    api(project(":feature:transactions:api"))

    api(project(":bindings:bandersnatch-crypto"))
}
