plugins {
    id("polkadotapp.android.library")
}

android {
    namespace = "io.paritytech.polkadotapp.feature_vouchers_impl"
}

dependencies {
    api(project(":feature:vouchers:api"))

    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)

    implementation(project(":database"))
    implementation(project(":feature:account:api"))

    implementation(libs.androidx.work.runtime)
}
