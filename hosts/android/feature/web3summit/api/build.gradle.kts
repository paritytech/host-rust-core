plugins {
    id("polkadotapp.android.library")
}

android {
    namespace = "io.paritytech.polkadotapp.feature_web3summit_api"
}

dependencies {
    api(project(":common"))
}
