package dev.selector.kivo_player.update

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class UpdatePlannerTest {
    @get:Rule val temporary = TemporaryFolder()

    private val packageName = "dev.selector.kivo_player"
    private val root = "https://github.com/yt-kevincarrera/kivo-player/releases/download/v1.2.3/"
    private val apk = "kivo-v1.2.3-arm64-v8a.apk"

    private inner class Fixture {
        val base = temporary.newFile("installed.apk").apply { writeBytes(ByteArray(90) { it.toByte() }) }
        var split = false
        var fetchCalls = 0
        var hashCalls = 0
        var fetchFailure = false
        var hashFailure = false
        var text = metadata(base)
        val planner = UpdatePlanner(packageName,
            installedBase = { InstalledUpdateBase(base, split) },
            fetchManifest = {
                fetchCalls++
                if (fetchFailure) throw IOException("Metadata unavailable")
                text
            },
            hashApk = {
                hashCalls++
                if (hashFailure) throw IOException("Installed APK unreadable")
                DeltaPatch.sha256(it)
            })
    }

    private fun metadata(base: File, version: String = "1.2.3", patchSize: Long = 50,
                         baseSize: Long = base.length(), baseHash: String = DeltaPatch.sha256(base)): String =
        JSONObject().put("schema", 1).put("package", packageName).put("version", version)
            .put("versionCode", 9).put("artifacts", org.json.JSONArray().put(
                JSONObject().put("abi", "arm64-v8a").put("apk", "kivo-v$version-arm64-v8a.apk")
                    .put("versionCode", 4009).put("size", 100).put("sha256", "a".repeat(64))
                    .put("patches", org.json.JSONArray().put(
                        JSONObject().put("fromSha256", baseHash).put("fromSize", baseSize)
                            .put("file", "from-base.kdelta").put("size", patchSize)
                            .put("sha256", "c".repeat(64)))))).toString()

    private fun preview(fixture: Fixture): Map<String, Any?> =
        fixture.planner.preview(root + apk, root + "kivo-update-v1.json")

    @Test fun compatiblePreviewSharesTheExactCachedDownloadPlanWithoutCreatingJobFiles() {
        val fixture = Fixture()
        val before = temporary.root.walkTopDown().map { it.relativeTo(temporary.root).path }.toList()
        val installedBytes = fixture.base.readBytes()

        assertEquals(mapOf("bytes" to 50L, "fullBytes" to 100L, "partial" to true), preview(fixture))
        val enqueuePlan = fixture.planner.plan(root + apk, root + "kivo-update-v1.json")

        assertTrue(enqueuePlan.partial)
        assertEquals(root + "from-base.kdelta", enqueuePlan.downloadUrl)
        assertEquals(50L, enqueuePlan.patch!!.size)
        assertSame(enqueuePlan, fixture.planner.plan(root + apk, root + "kivo-update-v1.json"))
        assertEquals(1, fixture.fetchCalls)
        assertEquals(1, fixture.hashCalls)
        assertArrayEquals(installedBytes, fixture.base.readBytes())
        assertEquals(before, temporary.root.walkTopDown().map { it.relativeTo(temporary.root).path }.toList())
    }

    @Test fun legacyReleaseHasUnknownNativeSizeAndDoesNotFetchOrHash() {
        val fixture = Fixture()
        val plan = fixture.planner.plan(root + apk, null)

        assertEquals(mapOf("bytes" to null, "fullBytes" to null, "partial" to false), plan.preview())
        assertEquals(root + apk, plan.downloadUrl)
        assertEquals("1.2.3", plan.version)
        assertNull(plan.manifest)
        assertEquals(0, fixture.fetchCalls)
        assertEquals(0, fixture.hashCalls)
    }

    @Test fun unavailableMetadataUsesFullRouteAndCanRecoverOnTheNextRequest() {
        val fixture = Fixture().apply { fetchFailure = true }

        val unavailable = fixture.planner.plan(root + apk, root + "kivo-update-v1.json")
        assertFalse(unavailable.partial)
        assertEquals(root + apk, unavailable.downloadUrl)
        assertNull(unavailable.preview()["bytes"])
        assertEquals(0, fixture.hashCalls)

        fixture.fetchFailure = false
        assertEquals(true, preview(fixture)["partial"])
        assertEquals(2, fixture.fetchCalls)
        assertEquals(1, fixture.hashCalls)
    }

    @Test fun invalidManifestNeverAdvertisesAnUnverifiedPatchOrSize() {
        val fixture = Fixture().apply {
            text = JSONObject(text).put("package", "another.application").toString()
        }

        assertEquals(mapOf("bytes" to null, "fullBytes" to null, "partial" to false), preview(fixture))
        assertEquals(0, fixture.hashCalls)
    }

    @Test fun splitInstallationUsesTheKnownFullSizeWithoutHashingItsBase() {
        val fixture = Fixture().apply { split = true }

        assertEquals(mapOf("bytes" to 100L, "fullBytes" to 100L, "partial" to false), preview(fixture))
        assertEquals(root + apk, fixture.planner.plan(root + apk, root + "kivo-update-v1.json").downloadUrl)
        assertEquals(0, fixture.hashCalls)
    }

    @Test fun incompatibleBaseHashUsesTheKnownFullSize() {
        val fixture = Fixture().apply { text = metadata(base, baseHash = "b".repeat(64)) }

        assertEquals(mapOf("bytes" to 100L, "fullBytes" to 100L, "partial" to false), preview(fixture))
        assertEquals(1, fixture.hashCalls)
    }

    @Test fun incompatibleBaseSizeDoesNotNeedAnApkHash() {
        val fixture = Fixture().apply { text = metadata(base, baseSize = base.length() + 1) }

        assertEquals(false, preview(fixture)["partial"])
        assertEquals(0, fixture.hashCalls)
    }

    @Test fun missingOrUnreadableBaseRetainsTheVerifiedFullRoute() {
        val fixture = Fixture().apply { hashFailure = true }
        assertEquals(mapOf("bytes" to 100L, "fullBytes" to 100L, "partial" to false), preview(fixture))
        assertEquals(1, fixture.hashCalls)

        assertTrue(fixture.base.delete())
        assertEquals(mapOf("bytes" to 100L, "fullBytes" to 100L, "partial" to false), preview(fixture))
        assertEquals(1, fixture.hashCalls)
    }

    @Test fun patchesThatDoNotSaveBytesUseTheFullApkWithoutHashing() {
        val fixture = Fixture().apply { text = metadata(base, patchSize = 100) }

        assertEquals(mapOf("bytes" to 100L, "fullBytes" to 100L, "partial" to false), preview(fixture))
        assertEquals(0, fixture.hashCalls)
    }

    @Test fun changedBaseAndSplitStateInvalidateThePreviewSelection() {
        val fixture = Fixture()
        assertEquals(50L, preview(fixture)["bytes"])

        fixture.base.appendBytes(byteArrayOf(42))
        fixture.text = metadata(fixture.base, patchSize = 40)
        assertEquals(40L, preview(fixture)["bytes"])
        assertEquals(2, fixture.hashCalls)

        fixture.split = true
        assertEquals(mapOf("bytes" to 100L, "fullBytes" to 100L, "partial" to false), preview(fixture))
        assertEquals(2, fixture.hashCalls)
        assertEquals(3, fixture.fetchCalls)
    }

    @Test fun unchangedInstalledBaseHashIsReusedAcrossReleasePlans() {
        val fixture = Fixture()
        preview(fixture)
        fixture.text = metadata(fixture.base, version = "1.2.4")

        val next = fixture.planner.plan((root + apk).replace("1.2.3", "1.2.4"),
            (root + "kivo-update-v1.json").replace("1.2.3", "1.2.4"))

        assertTrue(next.partial)
        assertEquals(2, fixture.fetchCalls)
        assertEquals(1, fixture.hashCalls)
    }

    @Test fun previewAndEnqueueOverlappingShareOneManifestAndBaseHash() {
        val base = temporary.newFile("installed.apk").apply { writeBytes(ByteArray(90) { it.toByte() }) }
        val text = metadata(base)
        val fetches = AtomicInteger()
        val hashes = AtomicInteger()
        val fetchEntered = CountDownLatch(1)
        val finishFetch = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        val planner = UpdatePlanner(packageName, { InstalledUpdateBase(base, false) }, {
            fetches.incrementAndGet()
            fetchEntered.countDown()
            check(finishFetch.await(5, TimeUnit.SECONDS))
            text
        }, { hashes.incrementAndGet(); DeltaPatch.sha256(it) })
        try {
            val preview = pool.submit<Map<String, Any?>> { planner.preview(root + apk, root + "kivo-update-v1.json") }
            assertTrue(fetchEntered.await(5, TimeUnit.SECONDS))
            val enqueuePlan = pool.submit<UpdatePlan> { planner.plan(root + apk, root + "kivo-update-v1.json") }
            finishFetch.countDown()

            assertEquals(50L, preview.get(5, TimeUnit.SECONDS)["bytes"])
            assertEquals(root + "from-base.kdelta", enqueuePlan.get(5, TimeUnit.SECONDS).downloadUrl)
            assertEquals(1, fetches.get())
            assertEquals(1, hashes.get())
        } finally {
            finishFetch.countDown()
            pool.shutdownNow()
        }
    }
}
