import com.android.build.gradle.internal.cxx.configure.gradleLocalProperties

plugins {
    id("polkadotapp.android.library")
    id("polkadotapp.android.compose")
    id("polkadotapp.android.hilt")
    alias(libs.plugins.kotlin.parcelize)
}

android {
    namespace = "io.paritytech.polkadotapp.feature_web3summit_impl"

    defaultConfig {
        val localProperties = gradleLocalProperties(rootDir, providers)
        buildConfigString(
            "W3S_AUTH_KEY",
            localProperties.readSecretOrThrow("W3S_AUTH_KEY")
        )
    }

    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    api(project(":feature:web3summit:api"))

    implementation(libs.hilt.lifecycle.viewmodel.compose)
    implementation(libs.androidx.fragment.ktx)

    implementation(project(":common"))
    implementation(project(":design"))
    implementation(project(":chains"))

    implementation(project(":feature:dotns:api"))
    implementation(project(":feature:people:api"))
    implementation(project(":feature:products:api"))
    implementation(project(":feature:revive:api"))
    implementation(project(":feature:transactions:api"))

    implementation(project(":tools:remoteconfig:api"))

    implementation(libs.web3j.abi)

    testImplementation(project(":test-shared"))
}
