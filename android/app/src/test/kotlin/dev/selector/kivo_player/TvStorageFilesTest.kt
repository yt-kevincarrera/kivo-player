package dev.selector.kivo_player

import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class TvStorageFilesTest {
    private fun row(path: String, uri: String = "content://media/external/video/media/42") = mapOf<String, Any>(
        "id" to "42", "name" to java.io.File(path).name, "filePath" to path, "uri" to uri,
    )

    @Test fun usesIndexedContentWhenDirectoryEnumerationIsEmpty() {
        val root = java.io.File("/storage/ABCD-1234/Movies")
        val video = row("/storage/ABCD-1234/Movies/movie.mp4")
        val entries = TvStorageFiles.merge(root, emptyList(), listOf(video))
        assertEquals(1, entries.size)
        assertEquals(video["uri"], entries.single()["uri"])
        assertEquals(false, entries.single()["directory"])
    }

    @Test fun derivesNestedFoldersWithoutLeakingSiblingOrPrivatePaths() {
        val root = java.io.File("/storage/ABCD-1234/Movies")
        val entries = TvStorageFiles.merge(root, emptyList(), listOf(
            row("${root.path}/Documentaries/nature.mkv"),
            row("${root.path}2/not-here.mp4"),
            row("${root.path}/.private/secret.mp4"),
            row("${root.path}/Android/data/private.mp4"),
            row("${root.path}/../other-volume.mp4"),
        ))
        assertEquals(listOf("Documentaries"), entries.map { it["name"] })
        assertEquals(true, entries.single()["directory"])
    }

    @Test fun keepsIndexedMetadataWhenTheSameFileIsAlsoVisibleDirectly() {
        val root = java.io.File("/storage/ABCD-1234/Movies")
        val video = row("${root.path}/movie.mp4")
        val direct = video + mapOf("id" to "tv:file", "uri" to "file://${root.path}/movie.mp4", "directory" to false)
        val entries = TvStorageFiles.merge(root, listOf(direct), listOf(video))
        assertEquals(1, entries.size)
        assertEquals("42", entries.single()["id"])
        assertEquals(video["uri"], entries.single()["uri"])
    }

    @Test fun showsCommonContainersInsideARealDirectory() {
        val root = Files.createTempDirectory("kivo-tv-storage-").toFile().canonicalFile
        try {
            val names = listOf("movie.MP4", "movie.mkv", "movie.avi", "movie.vob", "movie.mts", "movie.asf")
            names.forEach { root.resolve(it).writeBytes(byteArrayOf(1)) }
            root.resolve("notes.txt").writeText("not a video")
            assertEquals(names.toSet(), TvStorageFiles.children(root).map { it.name }.toSet())
        } finally {
            root.deleteRecursively()
        }
    }
}
