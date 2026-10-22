package dev.selector.kivo_player.update

import android.app.DownloadManager
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.AtomicFile
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import java.util.UUID
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Application-owned downloads. The original DownloadManager id remains the stable job handle. */
class UpdateDownloads private constructor(private val context: Context) {
    private val workers = Executors.newFixedThreadPool(2)
    private val downloads = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val directory = File(context.filesDir, "updates")
    private val jobs = ConcurrentHashMap<Long, Job>()
    private val preparing = Collections.newSetFromMap(ConcurrentHashMap<Long, Boolean>())
    private val invalidated = Collections.newSetFromMap(ConcurrentHashMap<Long, Boolean>())
    private val planner = UpdatePlanner(context.packageName,
        installedBase = {
            InstalledUpdateBase(File(context.applicationInfo.sourceDir),
                !context.applicationInfo.splitSourceDirs.isNullOrEmpty())
        }, fetchManifest = ::fetchManifest)

    private class Job(
        val handle: Long, val url: String, val version: String,
        val manifestUrl: String?, val manifestText: String?, val manifest: UpdateManifest?,
        val patch: PatchArtifact?, var activeId: Long,
        var partial: Boolean, var fallback: Boolean = false,
        var ready: Boolean = false, var failed: Boolean = false,
    ) {
        @Volatile var cancelled = false
    }

    init {
        directory.listFiles()?.filter { it.name.endsWith(".json") }?.forEach { file ->
            try {
                val json = AtomicFile(file).openRead().bufferedReader().use { it.readText() }.let(::JSONObject)
                val handle = json.getLong("handle")
                require(handle >= 0 && file.name == "$handle.json")
                if (json.optBoolean("cancelled", false)) {
                    downloads.remove(*setOf(handle, json.getLong("activeId")).filter { it >= 0 }.toLongArray())
                    listOf("$handle.input.tmp", "$handle.apk.tmp", "$handle.apk").forEach { File(directory, it).delete() }
                    AtomicFile(file).delete()
                    return@forEach
                }
                val url = json.getString("url")
                ReleaseUrls.parse(url)
                val manifestUrl = json.optString("manifestUrl").takeIf { it.isNotEmpty() }
                val text = json.optString("manifestText").takeIf { it.isNotEmpty() }
                val manifest = if (text != null && manifestUrl != null)
                    UpdateManifest.parse(text, manifestUrl, url, context.packageName) else null
                val patch = json.optString("patchHash").takeIf { it.isNotEmpty() }?.let { hash ->
                    manifest?.artifact?.patches?.singleOrNull { it.sha256 == hash }
                        ?: throw IOException("Unknown persisted patch")
                }
                jobs[handle] = Job(handle, url, json.getString("version"), manifestUrl, text,
                    manifest, patch, json.getLong("activeId"), json.getBoolean("partial"),
                    json.getBoolean("fallback"), json.getBoolean("ready"), json.getBoolean("failed"))
            } catch (_: Exception) { AtomicFile(file).delete() }
        }
        // Incomplete preparation is safe to restart from the system-owned download.
        directory.listFiles()?.filter { it.name.endsWith(".tmp") }?.forEach { it.delete() }
    }

    fun execute(action: () -> Unit) { workers.execute(action) }

    fun preview(url: String, manifestUrl: String?): Map<String, Any?> = planner.preview(url, manifestUrl)

    fun enqueue(url: String, fileName: String, manifestUrl: String?): Long {
        ReleaseUrls.requireBasename(fileName)
        require(fileName.endsWith(".apk"))
        val plan = planner.plan(url, manifestUrl)
        val handle = enqueueArtifact(plan.downloadUrl, plan.partial)
        if (handle < 0) return -1
        val job = Job(handle, url, plan.version, plan.manifestUrl, plan.manifestText,
            plan.manifest, plan.patch, handle, plan.partial)
        try {
            synchronized(job) { save(job); jobs[handle] = job }
        } catch (failure: Exception) {
            downloads.remove(handle)
            throw failure
        }
        return handle
    }

    fun pending(): Map<String, Any?>? {
        jobs.values.sortedByDescending { it.handle }.forEach { job ->
            if (alreadyInstalled(job)) { cancel(job.handle); return@forEach }
            synchronized(job) {
                if (!job.cancelled) return mapOf("id" to job.handle, "version" to job.version)
            }
        }
        return null
    }

    fun status(handle: Long): Map<String, Any?>? {
        val job = jobs[handle] ?: return rawStatus(handle) // pre-delta persisted downloads
        if (alreadyInstalled(job)) { cancel(handle); return null }
        synchronized(job) {
            if (job.cancelled) return null
            if (job.failed) return progress(job, "failed")
            if (job.ready && prepared(job).isFile) return progress(job, "done", size(job), size(job))
            if (preparing.contains(handle)) return progress(job, "preparing", size(job), size(job))
            val raw = rawStatus(job.activeId)
            val state = raw?.get("status")
            if (state == "failed" || raw == null) {
                if (job.partial && !job.fallback && job.manifest != null) {
                    fallback(job)
                    return progress(job, "pending")
                }
                if (raw == null) { cancel(handle); return null }
                return raw.plus(mapOf("partial" to job.partial, "fallback" to job.fallback))
            }
            if (state == "done" && job.manifest != null) {
                if (preparing.add(handle)) workers.execute { prepare(job) }
                return progress(job, "preparing", (raw["received"] as Number).toLong(), (raw["total"] as Number).toLong())
            }
            return raw.plus(mapOf("partial" to job.partial, "fallback" to job.fallback))
        }
    }

    fun cancel(handle: Long) {
        invalidated.add(handle)
        val job = jobs[handle]
        if (job == null) { if (handle >= 0) downloads.remove(handle); return }
        job.cancelled = true
        synchronized(job) {
            // Persist intent first: a process killed during system cleanup must not revive the job.
            try { save(job) } catch (_: Exception) { AtomicFile(metadata(handle)).delete() }
            jobs.remove(handle, job)
            try {
                downloads.remove(*setOf(job.handle, job.activeId).filter { it >= 0 }.toLongArray())
            } finally {
                AtomicFile(metadata(handle)).delete()
                cleanup(job, includePrepared = true)
            }
        }
    }

    /** Cancellation invalidates the worker immediately, before its cleanup task is queued. */
    fun requestCancellation(handle: Long) {
        invalidated.add(handle)
        jobs[handle]?.cancelled = true
    }

    /** Final main-thread guard between verification and the explicit installer intent. */
    fun canInstall(handle: Long): Boolean {
        if (invalidated.contains(handle)) return false
        val job = jobs[handle] ?: return true // pre-delta downloads have no native receipt
        return !job.cancelled && !job.failed && (job.ready || job.manifest == null)
    }

    /** Heavy checks run on our worker; the Activity launches the returned URI on the UI thread. */
    fun installationUri(handle: Long): Uri? {
        val job = jobs[handle] ?: return downloads.getUriForDownloadedFile(handle)
        synchronized(job) {
            if (job.cancelled || job.failed) return null
            if (job.manifest == null) return downloads.getUriForDownloadedFile(job.activeId)
            if (!job.ready) return null
            val output = prepared(job)
            verifyApk(output, job)
            if (job.cancelled) return null
            return FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", output)
        }
    }

    private fun prepare(job: Job) {
        val input = File(directory, "${job.handle}.input.tmp")
        val output = File(directory, "${job.handle}.apk.tmp")
        try {
            if (job.cancelled) return
            val manifest = job.manifest ?: return
            val artifact = manifest.artifact
            val patch = if (job.partial) job.patch else null
            val inputSize = patch?.size ?: artifact.size
            val inputHash = patch?.sha256 ?: artifact.sha256
            if (directory.usableSpace < inputSize + (if (patch != null) artifact.size else 0) + 1024 * 1024) {
                throw IOException("Not enough space to prepare update")
            }
            copyDownload(job, input, inputSize, inputHash)
            if (patch != null) {
                DeltaPatch.apply(File(context.applicationInfo.sourceDir), input, output,
                    patch.fromSize, artifact.size, patch.fromSha256, artifact.sha256) { job.cancelled }
            } else {
                if (!input.renameTo(output)) throw IOException("Cannot prepare APK")
            }
            verifyApk(output, job)
            synchronized(job) {
                if (job.cancelled) return
                val final = prepared(job)
                if (!output.renameTo(final)) throw IOException("Cannot publish verified APK")
                job.ready = true
                save(job)
            }
        } catch (_: Exception) {
            synchronized(job) {
                if (!job.cancelled) {
                    if (job.partial && !job.fallback) fallback(job)
                    else { job.failed = true; save(job) }
                }
            }
        } finally {
            input.delete()
            output.delete()
            preparing.remove(job.handle)
        }
    }

    private fun copyDownload(job: Job, output: File, size: Long, sha256: String) {
        val digest = MessageDigest.getInstance("SHA-256")
        ParcelFileDescriptor.AutoCloseInputStream(downloads.openDownloadedFile(job.activeId)).use { source ->
            FileOutputStream(output).use { destination ->
                val buffer = ByteArray(64 * 1024)
                var received = 0L
                while (true) {
                    if (job.cancelled) throw IOException("Update cancelled")
                    val count = source.read(buffer)
                    if (count < 0) break
                    if (count > size - received) throw IOException("Downloaded artifact exceeds expected size")
                    destination.write(buffer, 0, count)
                    digest.update(buffer, 0, count)
                    received += count
                }
                if (received != size || DeltaPatch.hex(digest.digest()) != sha256) throw IOException("Downloaded artifact mismatch")
                destination.fd.sync()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun verifyApk(file: File, job: Job) {
        val manifest = job.manifest ?: throw IOException("Missing verification metadata")
        if (file.length() != manifest.artifact.size || DeltaPatch.sha256(file) { job.cancelled } != manifest.artifact.sha256) {
            throw IOException("APK hash mismatch")
        }
        // GET_SIGNATURES is also needed on Android 9 to trigger certificate collection.
        // AOSP collects VERIFIED signing details (skipVerify=false), not merely certificate metadata.
        val flags = PackageManager.GET_SIGNATURES or
            (if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else 0)
        val installed = context.packageManager.getPackageInfo(context.packageName, flags)
        val target = context.packageManager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: throw IOException("APK signature or archive invalid")
        if (target.packageName != context.packageName || target.versionName != manifest.version ||
            versionCode(target) != manifest.artifact.versionCode || versionCode(target) <= versionCode(installed) ||
            signers(target).isEmpty() || signers(target) != signers(installed)) {
            throw IOException("APK package, version or signing identity mismatch")
        }
    }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { DeltaPatch.hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }?.toSet() ?: emptySet()
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    private fun alreadyInstalled(job: Job): Boolean = try {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        job.manifest?.let { versionCode(info) >= it.artifact.versionCode } ?: (info.versionName == job.version)
    } catch (_: Exception) { false }

    /** Called with the job lock held. A corrupt patch can fall back only once. */
    private fun fallback(job: Job) {
        if (job.cancelled || job.fallback) return
        val previous = job.activeId
        job.fallback = true
        job.partial = false
        job.ready = false
        job.activeId = enqueueArtifact(job.url, false)
        job.failed = job.activeId < 0
        save(job)
        if (previous >= 0) downloads.remove(previous)
        cleanup(job, includePrepared = true)
    }

    private fun enqueueArtifact(url: String, patch: Boolean): Long {
        ReleaseUrls.parse(url)
        val parent = File(context.getExternalFilesDir(null) ?: throw IOException("No download storage"), "updates").apply { mkdirs() }
        val destination = File(parent, "${UUID.randomUUID()}.${if (patch) "kdelta" else "apk"}")
        return try { downloads.enqueue(DownloadManager.Request(Uri.parse(url))
            .setTitle("Kivo")
            .setMimeType(if (patch) "application/octet-stream" else "application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationUri(Uri.fromFile(destination))) } catch (_: Exception) { -1L }
    }

    private fun rawStatus(id: Long): Map<String, Any?>? {
        if (id < 0) return null
        downloads.query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            return mapOf(
                "status" to when (status) {
                    DownloadManager.STATUS_PENDING -> "pending"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    DownloadManager.STATUS_SUCCESSFUL -> "done"
                    else -> "failed"
                },
                "reason" to if (reason == DownloadManager.PAUSED_WAITING_TO_RETRY) "retry" else "network",
                "received" to cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                "total" to cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
            )
        }
        return null
    }

    private fun progress(job: Job, state: String, received: Long = 0, total: Long = -1): Map<String, Any?> = mapOf(
        "status" to state, "received" to received, "total" to total,
        "partial" to job.partial, "fallback" to job.fallback,
    )

    private fun size(job: Job): Long = if (job.partial) job.patch?.size ?: -1 else job.manifest?.artifact?.size ?: -1
    private fun metadata(handle: Long) = File(directory, "$handle.json")
    private fun prepared(job: Job) = File(directory, "${job.handle}.apk")
    private fun cleanup(job: Job, includePrepared: Boolean) {
        File(directory, "${job.handle}.input.tmp").delete()
        File(directory, "${job.handle}.apk.tmp").delete()
        if (includePrepared) prepared(job).delete()
    }

    private fun save(job: Job) {
        if (!directory.isDirectory && !directory.mkdirs() && !directory.isDirectory) {
            throw IOException("Cannot create update storage")
        }
        val json = JSONObject().put("handle", job.handle).put("activeId", job.activeId)
            .put("url", job.url).put("version", job.version)
            .put("manifestUrl", job.manifestUrl ?: "").put("manifestText", job.manifestText ?: "")
            .put("patchHash", job.patch?.sha256 ?: "").put("partial", job.partial)
            .put("fallback", job.fallback).put("ready", job.ready).put("failed", job.failed)
            .put("cancelled", job.cancelled)
        val atomic = AtomicFile(metadata(job.handle))
        val output = atomic.startWrite()
        try {
            output.write(json.toString().toByteArray(Charsets.UTF_8))
            atomic.finishWrite(output)
        } catch (failure: Exception) { atomic.failWrite(output); throw failure }
    }

    private fun fetchManifest(url: String): String {
        val initial = ReleaseUrls.parse(url)
        require(initial.second == "kivo-update-v1.json")
        var target = URI(url)
        repeat(6) {
            require(target.scheme == "https" && target.port == -1 && target.rawUserInfo == null &&
                target.host in setOf("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"))
            val connection = target.toURL().openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            connection.setRequestProperty("User-Agent", "kivo-player")
            try {
                val code = connection.responseCode
                if (code in setOf(301, 302, 303, 307, 308)) {
                    target = target.resolve(connection.getHeaderField("Location") ?: throw IOException("Missing redirect"))
                } else {
                    if (code != 200) throw IOException("Manifest HTTP $code")
                    return connection.inputStream.use { source ->
                        val bytes = source.readBytesLimited(512 * 1024)
                        String(bytes, Charsets.UTF_8)
                    }
                }
            } finally { connection.disconnect() }
        }
        throw IOException("Too many manifest redirects")
    }

    companion object {
        @Volatile private var instance: UpdateDownloads? = null
        fun get(context: Context): UpdateDownloads = instance ?: synchronized(this) {
            instance ?: UpdateDownloads(context.applicationContext).also { instance = it }
        }
    }
}

private fun java.io.InputStream.readBytesLimited(limit: Int): ByteArray {
    val output = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while (true) {
        val count = read(buffer)
        if (count < 0) return output.toByteArray()
        if (count > limit - output.size()) throw IOException("Manifest too large")
        output.write(buffer, 0, count)
    }
}
