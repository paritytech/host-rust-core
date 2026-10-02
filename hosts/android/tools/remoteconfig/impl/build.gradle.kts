plugins {
    id("polkadotapp.android.library")
    id("polkadotapp.android.hilt")
}

android {
    namespace = "io.paritytech.polkadotapp.tools_remoteconfig_impl"

    defaultConfig {
        buildConfigField("boolean", "LOCAL_CONFIG_FALLBACK", "false")
    }

    buildTypes {
        getByName("debug") { buildConfigField("boolean", "LOCAL_CONFIG_FALLBACK", "true") }
    }
}

dependencies {
    api(project(":tools:remoteconfig:api"))

    implementation(project(":tools:common"))

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.remote.config)
}