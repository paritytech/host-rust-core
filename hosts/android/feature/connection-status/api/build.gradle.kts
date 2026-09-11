plugins {
    id("polkadotapp.android.library")
    id("polkadotapp.android.compose")
}

android {
    namespace = "io.paritytech.polkadotapp.feature_connection_status_api"
}

dependencies {
    api(project(":common"))
    api(project(":design"))
    api(project(":chains"))
}
