package dev.selector.kivo_player.update

import android.app.DownloadManager
import android.os.PowerManager
import org.junit.Assert.*
import org.junit.Test

class DownloadStatusTest {
    @Test fun queuedHotDeviceKeepsPendingAndReportsASeparateHint() {
        val result = DownloadStatus.progress(DownloadManager.STATUS_PENDING,
            DownloadManager.PAUSED_WAITING_FOR_NETWORK, 0, -1, PowerManager.THERMAL_STATUS_MODERATE)
        assertEquals("pending", result["status"])
        assertNull(result["reason"])
        assertEquals(true, result["deviceHot"])
        assertEquals(0L, result["received"])
        assertEquals(-1L, result["total"])
    }

    @Test fun unavailableOrLowThermalStatusDoesNotInventARestriction() {
        for (thermal in listOf(null, PowerManager.THERMAL_STATUS_NONE, PowerManager.THERMAL_STATUS_LIGHT)) {
            assertEquals(false, DownloadStatus.progress(DownloadManager.STATUS_PENDING, 0, 0, -1, thermal)["deviceHot"])
        }
    }

    @Test fun knownPauseReasonsTakePrecedenceOverDeviceHeat() {
        for ((reason, expected) in listOf(
            DownloadManager.PAUSED_WAITING_FOR_NETWORK to "network",
            DownloadManager.PAUSED_WAITING_TO_RETRY to "retry",
            DownloadManager.PAUSED_QUEUED_FOR_WIFI to "wifi",
            DownloadManager.PAUSED_UNKNOWN to "unknown",
            999 to "unknown",
        )) {
            val result = DownloadStatus.progress(DownloadManager.STATUS_PAUSED, reason, 5, 10,
                PowerManager.THERMAL_STATUS_SEVERE)
            assertEquals(expected, result["reason"])
            assertEquals(false, result["deviceHot"])
        }
    }

    @Test fun progressAndCompletionDoNotLookThermallyBlocked() {
        for (status in listOf(DownloadManager.STATUS_RUNNING, DownloadManager.STATUS_SUCCESSFUL,
            DownloadManager.STATUS_FAILED)) {
            val result = DownloadStatus.progress(status, 1, 10, 100, PowerManager.THERMAL_STATUS_SEVERE)
            assertEquals(false, result["deviceHot"])
            assertNull(result["reason"])
        }
    }
}
