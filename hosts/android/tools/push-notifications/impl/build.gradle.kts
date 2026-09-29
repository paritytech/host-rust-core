plugins {
    id("polkadotapp.android.library")
    id("polkadotapp.android.hilt")
}

android {
    namespace = "io.paritytech.polkadotapp.tools_push_notifications_impl"

    flavorDimensions += "distribution"

    productFlavors {
        create("gp") { dimension = "distribution" }
        create("vanilla") { dimension = "distribution" }
    }
}

dependencies {
    api(project(":tools:push-notifications:api"))
    implementation(project(":tools:jwt-auth:api"))

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
}
