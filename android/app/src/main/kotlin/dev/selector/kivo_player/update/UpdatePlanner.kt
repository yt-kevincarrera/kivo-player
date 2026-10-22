package dev.selector.kivo_player.update

import java.io.File

internal data class InstalledUpdateBase(val apk: File, val splitInstall: Boolean)

/** An immutable selection shared by the preview and the actual download. */
internal data class UpdatePlan(
    val url: String,
    val version: String,
    val manifestUrl: String?,
    val manifestText: String?,
    val manifest: UpdateManifest?,
    val patch: PatchArtifact?,
) {
    val partial: Boolean get() = patch != null
    val downloadUrl: String get() = patch?.let { ReleaseUrls.asset(manifestUrl!!, it.file) } ?: url

    fun preview(): Map<String, Any?> = mapOf(
        "bytes" to (patch?.size ?: manifest?.artifact?.size),
        "fullBytes" to manifest?.artifact?.size,
        "partial" to partial,
    )
}

/** Reads only metadata and the installed APK; it has no download or job-storage dependency. */
internal class UpdatePlanner(
    private val packageName: String,
    private val installedBase: () -> InstalledUpdateBase,
    private val fetchManifest: (String) -> String,
    private val hashApk: (File) -> String = { DeltaPatch.sha256(it) },
) {
    private data class BaseStamp(
        val path: String, val size: Long, val modified: Long,
        val readable: Boolean, val splitInstall: Boolean,
    )
    private data class Key(val url: String, val manifestUrl: String?, val base: BaseStamp)

    private val plans = LinkedHashMap<Key, UpdatePlan>(4, 0.75f, true)
    private var baseHash: Pair<BaseStamp, String>? = null

    /** Serialized to share a single manifest fetch/hash when preview and enqueue overlap. */
    @Synchronized
    fun plan(url: String, manifestUrl: String?): UpdatePlan {
        val release = ReleaseUrls.parse(url)
        val base = installedBase()
        val stamp = BaseStamp(base.apk.absolutePath, base.apk.length(), base.apk.lastModified(),
            base.apk.isFile && base.apk.canRead(), base.splitInstall)
        val key = Key(url, manifestUrl, stamp)
        plans[key]?.let { return it }

        var text: String? = null
        var manifest: UpdateManifest? = null
        if (manifestUrl != null) {
            try {
                val fetched = fetchManifest(manifestUrl)
                manifest = UpdateManifest.parse(fetched, manifestUrl, url, packageName)
                text = fetched
            } catch (_: Exception) { /* Legacy or unavailable metadata uses the full APK. */ }
        }

        var patch: PatchArtifact? = null
        if (manifest != null && !stamp.splitInstall && stamp.readable &&
            stamp.size in 1..DeltaPatch.MAX_APK_BYTES) {
            val candidates = manifest.artifact.patches.filter {
                it.fromSize == stamp.size && it.size < manifest.artifact.size
            }
            if (candidates.isNotEmpty()) {
                try {
                    // The installed APK is OS-owned and immutable during this process.
                    // Reconstruction still checks its exact size and hash before applying a patch.
                    val hash = baseHash?.takeIf { it.first == stamp }?.second
                        ?: hashApk(base.apk).also { baseHash = stamp to it }
                    patch = candidates.firstOrNull { it.fromSha256 == hash }
                } catch (_: Exception) { /* An unreadable base still has the verified full route. */ }
            }
        }

        val plan = UpdatePlan(url, manifest?.version ?: release.first.removePrefix("v"),
            if (manifest != null) manifestUrl else null, text, manifest, patch)
        // Never pin a transient network failure: a later preview/enqueue may recover metadata.
        if (manifestUrl == null || manifest != null) {
            plans[key] = plan
            if (plans.size > 4) plans.remove(plans.keys.first())
        }
        return plan
    }

    fun preview(url: String, manifestUrl: String?): Map<String, Any?> = plan(url, manifestUrl).preview()
}
