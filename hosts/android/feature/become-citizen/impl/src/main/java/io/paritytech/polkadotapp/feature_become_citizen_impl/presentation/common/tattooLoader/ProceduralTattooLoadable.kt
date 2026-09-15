@file:OptIn(ExperimentalEncodingApi::class, ExperimentalUnsignedTypes::class)

package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.tattooLoader

import android.content.Context
import android.graphics.drawable.Drawable
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.util.addressOf
import io.paritytech.polkadotapp.common.data.image.fetchers.JSImageLoaderWebView
import io.paritytech.polkadotapp.common.data.image.loadables.JsImageLoadable
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.await
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_impl.R
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsContentLookup
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Request
import timber.log.Timber
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.time.Duration.Companion.seconds
import kotlin.time.measureTimedValue

class ProceduralTattooLoadable(
    private val context: Context,
    private val familyId: ByteArray,
    private val tattooId: TattooId,
    private val okHttpClient: OkHttpClient,
    private val tattooRepository: TattooRepository,
    private val chainRegistry: ChainRegistry,
    private val ipfsContentLookup: IpfsContentLookup
) : JsImageLoadable {
    override suspend fun getDrawable(webView: JSImageLoaderWebView): Drawable? {
        val familyIndex = tattooId.familyIndex
        Timber.d("Started loading procedural image for $familyIndex")

        val metadata = tattooRepository.getTattooFamilyMetadata(familyId).getOrNull() ?: return null

        Timber.d("Fetched metadata for $familyIndex")

        Timber.d("Fetching js file for $familyIndex...")
        val jsFile = getJSFile(metadata.cid) ?: return null
        Timber.d("Fetched js file for $familyIndex")

        val seed = tattooId.getSeed() ?: return null
        val htmlPage = readHtmlPageEncoded(seed, jsFile.readText().trim())

        return withTimeout(5.seconds) {
            Timber.d("Started webview rendering for $familyIndex")

            val (result, duration) = measureTimedValue {
                webView.renderScriptIntoDrawable(htmlPage)
            }

            Timber.d("Finished webview rendering for $familyIndex family tattoo in $duration")

            result
        }
    }

    override fun getCacheKey() = tattooId.getUniqueKey()

    private suspend fun getJSFile(cid: String): File? {
        val fileDir = File("${context.cacheDir}/generated_images")
        fileDir.mkdir()
        val file = File(fileDir, cid)

        if (file.exists()) return file

        val url = ipfsContentLookup.getIpfsLinkFor(cid)
            .logFailure("Failed to resolve IPFS link for procedural tattoo")
            .getOrNull() ?: return null
        val request = Request.Builder().url(url).build()
        val response = okHttpClient.newCall(request).await()

        if (!response.isSuccessful) return null

        return try {
            file.createNewFile()
            FileOutputStream(file).use {
                it.write(requireNotNull(response.body).bytes())
            }
            file
        } catch (e: Exception) {
            file.delete()
            null
        }
    }

    private fun readHtmlPageEncoded(seed: String, moduleCode: String): String {
        val escapedModuleCode = escapeJsTemplateLiteral(moduleCode)
        val inputStream = context.resources.openRawResource(R.raw.procedural_tattoo_canvas)
        val bufferedReader = BufferedReader(InputStreamReader(inputStream))
        val pageCode = bufferedReader.use { it.readText() }
            .replace("<SEED>", seed)
            .replace("<MODULE_CODE>", escapedModuleCode)

        return Base64.encode(pageCode.toByteArray())
    }

    private fun escapeJsTemplateLiteral(code: String): String {
        return code
            .replace("\\", "\\\\")
            .replace("`", "\\`")
            .replace("\${", "\\\${")
    }

    private suspend fun TattooId.getSeed(): String? = when (this) {
        is TattooId.Procedural -> seed.getBytes().contentToString()
        is TattooId.ProceduralAccount -> accountIdToSeed(accountId)
        is TattooId.ProceduralPersonal -> personIdToSeed(personId).contentToString()
        else -> null
    }

    private fun TattooId.getUniqueKey() = "image_key_$familyIndex" + when (this) {
        is TattooId.Procedural -> "procedural_${seed.getUniqueSeedKey()}"
        is TattooId.ProceduralAccount -> "procedural_account_${accountId.value.contentToString()}"
        is TattooId.ProceduralPersonal -> "procedural_personal_$personId"
        else -> hashCode()
    }

    private suspend fun accountIdToSeed(accountId: AccountId) = "'${chainRegistry.peopleChain().addressOf(accountId)}'"
    private fun personIdToSeed(personId: PersonId): UByteArray = personId.id.toByteArray().toUByteArray()
}
