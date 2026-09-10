plugins {
    id("polkadotapp.android.library")
    id("polkadotapp.android.compose")
    alias(libs.plugins.kotlin.parcelize)
}

android {
    namespace = "io.paritytech.polkadotapp.feature_identity_impl"
}

dependencies {
    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)

    implementation(libs.hilt.lifecycle.viewmodel.compose)
    implementation(libs.androidx.fragment.ktx)
    implementation(libs.kirich.viewbinding)

    api(project(":common"))
    api(project(":chains"))
    api(project(":design"))

    api(project(":feature:identity:api"))
    api(project(":feature:transactions:api"))
    api(project(":feature:people:api"))
}
