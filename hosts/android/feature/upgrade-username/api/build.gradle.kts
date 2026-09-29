plugins {
    id("polkadotapp.android.library")
    id("polkadotapp.android.compose")
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.kotlin.parcelize)
}

android {
    namespace = "io.paritytech.polkadotapp.feature_upgrade_username_api"
}

dependencies {
    api(project(":common"))
    api(project(":design"))

    api(project(":feature:chats:api"))
    api(project(":feature:usernames:api"))

    implementation(libs.hilt.android)
}
