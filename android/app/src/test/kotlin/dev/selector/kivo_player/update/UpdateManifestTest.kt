package dev.selector.kivo_player.update

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

class UpdateManifestTest {
    private val root = "https://github.com/yt-kevincarrera/kivo-player/releases/download/v1.2.3/"
    private val apk = "kivo-v1.2.3-arm64-v8a.apk"
    private fun valid(): JSONObject = JSONObject("""{
      "schema":1,"package":"dev.selector.kivo_player","version":"1.2.3","versionCode":9,
      "artifacts":[{"abi":"arm64-v8a","apk":"$apk","versionCode":4009,"size":100,"sha256":"${"a".repeat(64)}",
      "patches":[{"fromSha256":"${"b".repeat(64)}","fromSize":90,"file":"base.kdelta","size":50,"sha256":"${"c".repeat(64)}"}]}]
    }""")
    private fun parse(json: JSONObject) = UpdateManifest.parse(json.toString(), root + "kivo-update-v1.json", root + apk, "dev.selector.kivo_player")

    @Test fun selectsTheExactAbiApkAndPatchMetadata() {
        val parsed = parse(valid())
        assertEquals("1.2.3", parsed.version)
        assertEquals(9L, parsed.versionCode)
        assertEquals(4009L, parsed.artifact.versionCode)
        assertEquals(apk, parsed.artifact.apk)
        assertEquals("base.kdelta", parsed.artifact.patches.single().file)
    }

    @Test fun rejectsWrongPackageSchemaVersionAndSizeTypes() {
        for ((key, value) in listOf("package" to "other.app", "schema" to 2, "version" to "1.2.4", "versionCode" to "9")) {
            assertThrows(Exception::class.java) { parse(valid().put(key, value)) }
        }
        val huge = valid().apply { getJSONArray("artifacts").getJSONObject(0).put("size", DeltaPatch.MAX_APK_BYTES + 1) }
        assertThrows(Exception::class.java) { parse(huge) }
        val missingAbiCode = valid().apply { getJSONArray("artifacts").getJSONObject(0).remove("versionCode") }
        assertThrows(Exception::class.java) { parse(missingAbiCode) }
    }

    @Test fun rejectsUnsafeAssetNamesAndHashes() {
        for (name in listOf("../x.kdelta", "https://other.test/x.kdelta", "a/b.kdelta", "a%2fb.kdelta")) {
            val json = valid().apply { getJSONArray("artifacts").getJSONObject(0).getJSONArray("patches").getJSONObject(0).put("file", name) }
            assertThrows(Exception::class.java) { parse(json) }
        }
        val bad = valid().apply { getJSONArray("artifacts").getJSONObject(0).put("sha256", "abc") }
        assertThrows(Exception::class.java) { parse(bad) }
    }

    @Test fun rejectsMixedReleaseOtherRepoAndNonHttpsUrls() {
        for (url in listOf(root.replace("https:", "http:"), root.replace("yt-kevincarrera", "someone"), root.replace("v1.2.3", "v1.2.4"))) {
            assertThrows(Exception::class.java) {
                UpdateManifest.parse(valid().toString(), root + "kivo-update-v1.json", url + apk, "dev.selector.kivo_player")
            }
        }
        for (url in listOf(root + apk + "?x=1", root + "%2e%2e", root.replace("github.com", "github.com.evil.test") + apk)) {
            assertThrows(Exception::class.java) { ReleaseUrls.parse(url) }
        }
    }

    @Test fun generatorManifestUsesTheActualAbiVersionCodeWhenFixtureIsAvailable() {
        val path = System.getenv("KIVO_DELTA_FIXTURE_DIR")
        assumeTrue("Optional downloaded release fixture", !path.isNullOrEmpty())
        val fixture = File(path!!)
        val release = "https://github.com/yt-kevincarrera/kivo-player/releases/download/v1.31.1/"
        val fileName = "kivo-v1.31.1-arm64-v8a.apk"
        val parsed = UpdateManifest.parse(File(fixture, "production/kivo-update-v1.json").readText(),
            release + "kivo-update-v1.json", release + fileName, "dev.selector.kivo_player")
        assertEquals(2058L, parsed.versionCode)
        assertEquals(4058L, parsed.artifact.versionCode)
        assertEquals(File(fixture, fileName).length(), parsed.artifact.size)
        assertEquals(DeltaPatch.sha256(File(fixture, fileName)), parsed.artifact.sha256)
    }
}
