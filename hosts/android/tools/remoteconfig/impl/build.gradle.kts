plugins {
    id("polkadotapp.android.library")
    id("polkadotapp.android.hilt")
}

android {
    namespace = "io.paritytech.polkadotapp.tools_remoteconfig_impl"

    defaultConfig {
        // Not BuildConfig.DEBUG: nightly/safetynet initWith(debug) but have real credentials.
        buildConfigField("boolean", "LOCAL_CONFIG_FALLBACK", "true")
    }

    buildTypes {
        getByName("release") { buildConfigField("boolean", "LOCAL_CONFIG_FALLBACK", "false") }
        getByName("nightly") { buildConfigField("boolean", "LOCAL_CONFIG_FALLBACK", "false") }
        getByName("safetynet") { buildConfigField("boolean", "LOCAL_CONFIG_FALLBACK", "false") }
    }
}

dependencies {
    api(project(":tools:remoteconfig:api"))

    implementation(project(":tools:common"))

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.remote.config)
}