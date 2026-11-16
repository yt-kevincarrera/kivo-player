package dev.selector.kivo_player

import java.io.File

/** Filesystem rules kept separate from Android's permission and media APIs. */
internal object TvStorageFiles {
    val videoExtensions = setOf("mkv", "mp4", "avi", "mov", "webm", "flv", "wmv", "m4v",
        "mpg", "mpeg", "mpe", "m1v", "m2v", "mpv", "ts", "mts", "m2ts", "m2t",
        "vob", "3gp", "3g2", "ogv", "ogg", "asf", "divx", "xvid", "f4v", "rm", "rmvb")

    fun children(directory: File): List<File> {
        check(directory.isDirectory) { "Storage is disconnected or the folder no longer exists" }
        val files = directory.listFiles() ?: throw SecurityException("Storage access is required")
        return files.filter { file ->
            !file.name.startsWith(".") && file.name != "Android" &&
                (file.isDirectory || file.extension.lowercase() in videoExtensions) &&
                file.canonicalPath == file.absolutePath
        }.sortedWith(compareBy<File> { !it.isDirectory }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    /** MediaStore can expose playable content URIs when FUSE hides filenames.
     * Derive only descendants of this directory; never match a sibling prefix,
     * hidden/private folders, or an indexed path outside the mounted root.
     */
    fun merge(directory: File, direct: List<Map<String, Any>>,
        indexed: List<Map<String, Any>>): List<Map<String, Any>> {
        val root = directory.canonicalFile
        val prefix = root.path + File.separator
        val entries = linkedMapOf<String, Map<String, Any>>()
        direct.forEach {
            val path = File(it["filePath"] as String).canonicalPath
            if (path.startsWith(prefix)) entries[path] = it + ("filePath" to path)
        }
        for (row in indexed) {
            val path = row["filePath"] as? String ?: continue
            if (path.isEmpty()) continue
            val file = File(path).canonicalFile
            if (!file.path.startsWith(prefix)) continue
            val parts = file.path.removePrefix(prefix).split(File.separatorChar)
            if (parts.any { it.startsWith(".") || it == "Android" }) continue
            if (parts.size == 1) {
                // Keep the content URI and metadata, even for a container not
                // present in our extension fallback. Android identified video.
                entries[file.path] = row + mapOf("filePath" to file.path, "directory" to false)
            } else {
                val child = File(root, parts.first())
                entries.putIfAbsent(child.path, mapOf(
                    "filePath" to child.path, "name" to child.name, "directory" to true,
                ))
            }
        }
        return entries.values.sortedWith(compareBy<Map<String, Any>> { it["directory"] != true }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it["name"] as String })
    }
}
