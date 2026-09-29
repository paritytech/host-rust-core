plugins {
    id("polkadotapp.android.library")
    id("polkadotapp.android.compose")
    id("polkadotapp.android.hilt")
    alias(libs.plugins.kotlin.parcelize)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "io.paritytech.polkadotapp.feature_mobrules_impl"

    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    implementation(libs.hilt.androidx.work)
    ksp(libs.hilt.androidx.compiler)

    implementation(libs.hilt.lifecycle.viewmodel.compose)
    implementation(libs.androidx.fragment.ktx)

    implementation(project(":common"))
    implementation(project(":tools:ipfs:api"))
    implementation(project(":design"))
    implementation(project(":chains"))
    implementation(project(":feature:account:api"))
    implementation(project(":feature:balances:api"))
    implementation(project(":feature:become-citizen:api"))
    implementation(project(":feature:people:api"))
    implementation(project(":feature:vouchers:api"))
    implementation(project(":database"))
    api(project(":feature:mobrules:api"))

    implementation(project(":feature:transactions:api"))

    implementation(project(":feature:identity:api"))
    implementation(project(":feature:chats:api"))

    implementation(libs.kirich.viewbinding)

    implementation(libs.bundles.androidx.media3)

    implementation(libs.nova.substrate.sdk)

    implementation(libs.androidx.work.runtime)

    testImplementation(libs.junit)
}
