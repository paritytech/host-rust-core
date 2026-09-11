// TrUAPI Android host adapter.
//
// Publishes `io.parity:truapi-host-android` to Maven. Products running in a
// `WebView` connect to the Rust core via its localhost WebSocket bridge
// (`TrUAPIProductExecution.startWsBridge`); the Rust core (compiled to
// `libtruapi_server.so`) handles wire decoding, routing, subscription
// lifecycle, and host capability dispatch.

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
    id("signing")
}

android {
    namespace = "io.parity.truapi"
    compileSdk = 34

    lint {
        // Suppresses the NewApi false positive on the UniFFI-generated cleaner
        // (runtime-guarded via Class.forName). See lint.xml.
        lintConfig = file("lint.xml")
    }

    defaultConfig {
        // minSdk 29 matches the polkadot-app-android-v2 floor; raise here
        // first and bump consumers' floors if we ever depend on a newer API.
        minSdk = 29
        consumerProguardFiles("consumer-rules.pro")
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            manifest.srcFile("src/main/AndroidManifest.xml")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
            withJavadocJar()
        }
    }
}

dependencies {
    // UniFFI Kotlin bindings use JNA for FFI.
    api("net.java.dev.jna:jna:5.14.0@aar")
    // UniFFI async functions and callbacks use cancellable continuations and
    // jobs, and `TrUAPIProductExecution.renderCustomMessage` returns a `Flow`,
    // so consumers compile against this.
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
}

// Coordinates for the Maven publication. Releases are published to Maven
// Central by .github/workflows/release-android.yml, which passes the real
// version via -PtruapiHostVersion; local publishes default to 0.0.0-local.
val publicationGroup = "io.parity"
val publicationArtifact = "truapi-host-android"
val publicationVersion = (findProperty("truapiHostVersion") as String?) ?: "0.0.0-local"
val publicationPath = "${publicationGroup.replace('.', '/')}/$publicationArtifact/$publicationVersion"
val centralStagingDir = layout.buildDirectory.dir("central-staging")

group = publicationGroup
version = publicationVersion

// Maven Central rejects unsigned files. The release workflow supplies the
// armored key through ORG_GRADLE_PROJECT_signingKey, which Gradle maps to this
// property; without one the publication stays unsigned so
// `make android-publish-local` needs no key.
val signingKey = findProperty("signingKey") as String?

if (signingKey != null) {
    // An unprotected key has no passphrase, and the signatory is left
    // unconfigured if this is null rather than empty.
    val passphrase = findProperty("signingPassword") as String? ?: ""
    signing { useInMemoryPgpKeys(signingKey, passphrase) }
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = publicationGroup
            artifactId = publicationArtifact
            version = publicationVersion

            afterEvaluate {
                from(components["release"])
            }

            pom {
                name.set("TrUAPI Android host adapter")
                description.set(
                    "Kotlin wrapper around the TrUAPI Rust core (UniFFI). " +
                        "Hosts integrating a `WebView`-based product link the " +
                        "`libtruapi_server` cdylib and route product traffic " +
                        "through the localhost WebSocket bridge."
                )
                url.set("https://github.com/paritytech/host-rust-core")
                licenses {
                    license {
                        name.set("MIT")
                        url.set("https://github.com/paritytech/host-rust-core/blob/main/LICENSE")
                    }
                }
                scm {
                    connection.set("scm:git:https://github.com/paritytech/host-rust-core.git")
                    developerConnection.set("scm:git:ssh://git@github.com/paritytech/host-rust-core.git")
                    url.set("https://github.com/paritytech/host-rust-core")
                }
                developers {
                    developer {
                        name.set("Parity Technologies")
                        email.set("admin@parity.io")
                        organization.set("Parity Technologies")
                        organizationUrl.set("https://parity.io")
                    }
                }
            }
        }
    }

    repositories {
        // Maven Local for `gradle publishToMavenLocal` during development.
        mavenLocal()
        // Release target. The Central Portal takes one signed bundle rather
        // than per-file writes, so the release path stages the repository
        // layout on disk and `centralBundle` zips it for upload.
        maven {
            name = "CentralStaging"
            url = centralStagingDir.get().asFile.toURI()
        }
    }
}

// AGP contributes the release component in an afterEvaluate of its own, so the
// publication has no artifacts to sign until after that one has run.
afterEvaluate {
    if (signingKey != null) signing.sign(publishing.publications["release"])
}

// Maven Central rejects an incomplete deployment as a whole, and the Portal
// only says so minutes after the upload. Checking the staged tree first turns
// that into a build failure naming the missing file. The provider module's
// `verifyJniLibs` guards its publication the same way.
val verifyCentralBundle =
    tasks.register("verifyCentralBundle") {
        description = "Fails unless the staged tree carries every file Maven Central requires."
        dependsOn("publishReleasePublicationToCentralStagingRepository")
        doLast {
            val staged = centralStagingDir.get().dir(publicationPath).asFile
            if (!staged.isDirectory) {
                throw GradleException("nothing staged at ${staged.path}")
            }

            // Gradle also writes .sha256 and .sha512, which Central accepts but
            // does not require. Only .md5, .sha1 and the signature are demanded
            // of every file, so the check asks for exactly those.
            val required = listOf(".asc", ".md5", ".sha1")
            val derived = required + listOf(".sha256", ".sha512")
            val files = staged.listFiles()?.toList() ?: emptyList()
            val artifacts = files.filterNot { file -> derived.any { file.name.endsWith(it) } }

            val missing = mutableListOf<String>()
            for (suffix in listOf(".aar", ".pom", "-sources.jar", "-javadoc.jar")) {
                val expected = "$publicationArtifact-$publicationVersion$suffix"
                if (artifacts.none { it.name == expected }) missing += expected
            }
            // Every file Central receives needs its own signature, including the
            // Gradle module metadata that is easy to forget.
            for (artifact in artifacts) {
                for (suffix in required) {
                    if (!File(staged, artifact.name + suffix).isFile) {
                        missing += artifact.name + suffix
                    }
                }
            }

            if (missing.isNotEmpty()) {
                throw GradleException(
                    "staged bundle is missing ${missing.size} file(s):\n" +
                        missing.sorted().joinToString("\n") { "  $it" }
                )
            }
            logger.lifecycle("staged ${artifacts.size} artifact(s) with signatures and checksums")
        }
    }

// The Portal's upload endpoint takes the repository layout as one zip, so the
// bundle is scoped to this version's directory: a stale version left in the
// staging tree by an earlier local run cannot ride along.
tasks.register<Zip>("centralBundle") {
    description = "Packages the staged tree as the bundle the Central Portal upload endpoint takes."
    dependsOn(verifyCentralBundle)
    from(centralStagingDir) { include("$publicationPath/**") }
    archiveFileName.set("$publicationArtifact-$publicationVersion-bundle.zip")
    destinationDirectory.set(layout.buildDirectory.dir("central-bundle"))
}
