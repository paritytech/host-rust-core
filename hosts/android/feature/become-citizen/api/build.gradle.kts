plugins {
    id("polkadotapp.android.library")
    id("polkadotapp.android.compose")
    alias(libs.plugins.kotlin.parcelize)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "io.paritytech.polkadotapp.feature_become_citizen_api"
}

dependencies {
    api(project(":common"))
    api(project(":tools:ipfs:api"))
    api(project(":chains"))
    api(project(":design"))

    api(project(":feature:chats:api"))
    api(project(":feature:people:api"))
    api(project(":feature:account:api"))
    api(project(":feature:balances:api"))
    api(project(":feature:transactions:api"))

    implementation(libs.hilt.android)
}
