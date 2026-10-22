package dev.selector.kivo_player.update

import org.json.JSONObject
import java.io.IOException
import java.net.URI

internal data class PatchArtifact(
    val fromSha256: String, val fromSize: Long,
    val file: String, val size: Long, val sha256: String,
)

internal data class ApkArtifact(
    val abi: String, val apk: String, val versionCode: Long, val size: Long, val sha256: String,
    val patches: List<PatchArtifact>,
)

internal data class UpdateManifest(
    val version: String, val versionCode: Long, val artifact: ApkArtifact,
) {
    companion object {
        fun parse(text: String, manifestUrl: String, apkUrl: String, packageName: String): UpdateManifest {
            val manifest = ReleaseUrls.parse(manifestUrl)
            val full = ReleaseUrls.parse(apkUrl)
            require(manifest.first == full.first && manifest.second == "kivo-update-v1.json")
            val json = JSONObject(text)
            require(json.integer("schema", 1) == 1L)
            require(json.getString("package") == packageName)
            val version = json.getString("version")
            require(version == manifest.first.removePrefix("v"))
            val versionCode = json.integer("versionCode", Long.MAX_VALUE)
            val artifacts = json.getJSONArray("artifacts")
            require(artifacts.length() in 1..8)
            val selected = ArrayList<ApkArtifact>()
            for (i in 0 until artifacts.length()) {
                val item = artifacts.getJSONObject(i)
                val abi = item.getString("abi")
                require(abi in setOf("arm64-v8a", "armeabi-v7a", "x86_64"))
                val apk = item.getString("apk").also(ReleaseUrls::requireBasename)
                require(apk.endsWith("-$abi.apk"))
                val artifactVersionCode = item.integer("versionCode", Long.MAX_VALUE)
                val size = item.integer("size", DeltaPatch.MAX_APK_BYTES)
                val sha = item.hash("sha256")
                val patches = item.optJSONArray("patches")
                require(patches == null || patches.length() <= 32)
                val entries = ArrayList<PatchArtifact>()
                if (patches != null) for (j in 0 until patches.length()) {
                    val patch = patches.getJSONObject(j)
                    val file = patch.getString("file").also(ReleaseUrls::requireBasename)
                    require(file.endsWith(".kdelta"))
                    entries.add(PatchArtifact(
                        patch.hash("fromSha256"), patch.integer("fromSize", DeltaPatch.MAX_APK_BYTES),
                        file, patch.integer("size", DeltaPatch.MAX_PATCH_BYTES), patch.hash("sha256"),
                    ))
                }
                if (apk == full.second) selected.add(ApkArtifact(abi, apk, artifactVersionCode, size, sha, entries))
            }
            require(selected.size == 1)
            return UpdateManifest(version, versionCode, selected.single())
        }
    }
}

/** Only release assets from this repository, with no traversal, credentials or query. */
internal object ReleaseUrls {
    private val basename = Regex("[A-Za-z0-9][A-Za-z0-9._+-]{0,180}")
    fun requireBasename(value: String) {
        require(basename.matches(value) && value != "." && value != "..")
    }
    fun parse(value: String): Pair<String, String> {
        val uri = URI(value)
        require(uri.scheme == "https" && uri.host == "github.com" && uri.port == -1 &&
            uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null)
        val parts = uri.rawPath.split('/')
        require(parts.size == 7 && parts.take(5) == listOf("", "yt-kevincarrera", "kivo-player", "releases", "download"))
        requireBasename(parts[5])
        requireBasename(parts[6])
        return parts[5] to parts[6]
    }
    fun asset(manifestUrl: String, name: String): String {
        requireBasename(name)
        parse(manifestUrl)
        return manifestUrl.substringBeforeLast('/') + "/" + name
    }
}

internal fun JSONObject.integer(key: String, limit: Long): Long {
    val raw = get(key)
    if (raw !is Int && raw !is Long) throw IOException("Invalid integer: $key")
    return (raw as Number).toLong().also { require(it > 0 && it <= limit) }
}

internal fun JSONObject.hash(key: String): String = getString(key).also {
    require(Regex("[0-9a-f]{64}").matches(it))
}
