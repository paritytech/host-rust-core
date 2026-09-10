plugins {
    id("polkadotapp.android.library")
}

android {
    namespace = "io.paritytech.polkadotapp.feature_mobrules_api"
}

dependencies {
    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)

    api(project(":common"))
    api(project(":chains"))
    api(project(":feature:become-citizen:api"))
    api(project(":feature:balances:api"))
}
