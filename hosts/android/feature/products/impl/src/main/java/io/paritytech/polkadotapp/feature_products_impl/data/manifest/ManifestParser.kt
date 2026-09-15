package io.paritytech.polkadotapp.feature_products_impl.data.manifest

import com.google.gson.Gson
import io.paritytech.polkadotapp.common.utils.enumValueOfOrNull
import io.paritytech.polkadotapp.feature_products_api.model.ExecutableHost
import io.paritytech.polkadotapp.feature_products_api.model.ExecutableKind
import io.paritytech.polkadotapp.feature_products_api.model.ProductExecutable
import io.paritytech.polkadotapp.feature_products_api.model.ProductIcon
import io.paritytech.polkadotapp.tools_ipfs_api.Cid
import javax.inject.Inject

/** Rejections are `Result.failure`: the record exists but the publisher got it wrong. */
internal class ManifestParser @Inject constructor(
    private val gson: Gson,
) {
    fun parseRoot(rawText: String): Result<RootManifest> = runCatching {
        val remote = requireNotNull(gson.fromJson(rawText, RootManifestRemote::class.java)) { "empty manifest" }

        require(remote.version == SCHEMA_VERSION) { "unsupported \$v=${remote.version}" }
        val displayName = requireNotNull(remote.displayName) { "missing displayName" }
        // Unused here, but required by RFC-0001: a stricter Host must not see a different manifest.
        requireNotNull(remote.description) { "missing description" }
        val icon = requireNotNull(remote.icon) { "missing icon" }

        RootManifest(displayName = displayName, icon = icon.toDomain())
    }

    /** [host] is the subname read from, and the executable's serving host. */
    fun parseExecutable(rawText: String, expectedKind: ExecutableKind, host: ExecutableHost): Result<ProductExecutable> =
        runCatching {
            val remote = requireNotNull(gson.fromJson(rawText, ExecutableManifestRemote::class.java)) { "empty manifest" }

            require(remote.version == SCHEMA_VERSION) { "unsupported \$v=${remote.version}" }
            require(remote.kind == expectedKind.manifestKind) {
                "kind '${remote.kind}' does not match subname kind '${expectedKind.manifestKind}'"
            }
            val appVersion = requireNotNull(remote.appVersion) { "missing appVersion" }

            when (expectedKind) {
                ExecutableKind.APP -> ProductExecutable.App(host, appVersion)

                ExecutableKind.WIDGET -> {
                    val dimensions = requireNotNull(remote.dimensions) { "widget missing dimensions" }
                    val heights = dimensions.height?.takeIf { it.isNotEmpty() }
                    ProductExecutable.Widget(
                        host = host,
                        appVersion = appVersion,
                        description = remote.description,
                        heights = requireNotNull(heights) { "widget dimensions.height must list at least one height" },
                        width = dimensions.width ?: DEFAULT_WIDGET_WIDTH,
                    )
                }

                ExecutableKind.WORKER -> {
                    val entrypoint = requireNotNull(remote.entrypoint) { "worker missing entrypoint" }
                    val includes = requireNotNull(remote.includes) { "worker missing includes" }
                    ProductExecutable.Worker(
                        scriptUrl = "https://${host.value}/$entrypoint",
                        appVersion = appVersion,
                        includesChat = requireNotNull(includes.chat) { "worker includes missing 'chat'" },
                        includesPocket = requireNotNull(includes.pocket) { "worker includes missing 'pocket'" },
                    )
                }
            }
        }

    private fun IconRemote.toDomain(): ProductIcon? {
        val cid = Cid.decode(requireNotNull(cid) { "icon missing cid" })
        val rawFormat = requireNotNull(format) { "icon missing format" }

        // An unsupported format still leaves the product launchable, with a placeholder icon.
        return enumValueOfOrNull<ProductIcon.Format>(rawFormat.uppercase())?.let { ProductIcon(cid, it) }
    }

    private companion object {
        const val SCHEMA_VERSION = 1
        const val DEFAULT_WIDGET_WIDTH = 1
    }
}
