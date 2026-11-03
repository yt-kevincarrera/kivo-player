package dev.selector.kivo_player.update

import android.app.DownloadManager
import android.os.PowerManager

/** Public DownloadManager state plus separately observed device conditions. */
internal object DownloadStatus {
    fun progress(
        status: Int, reason: Int, received: Long, total: Long, thermalStatus: Int? = null,
    ): Map<String, Any?> = mapOf(
        "status" to when (status) {
            DownloadManager.STATUS_PENDING -> "pending"
            DownloadManager.STATUS_RUNNING -> "running"
            DownloadManager.STATUS_PAUSED -> "paused"
            DownloadManager.STATUS_SUCCESSFUL -> "done"
            else -> "failed"
        },
        // COLUMN_REASON is undefined for pending/running/successful downloads.
        "reason" to if (status == DownloadManager.STATUS_PAUSED) when (reason) {
            DownloadManager.PAUSED_WAITING_TO_RETRY -> "retry"
            DownloadManager.PAUSED_WAITING_FOR_NETWORK -> "network"
            DownloadManager.PAUSED_QUEUED_FOR_WIFI -> "wifi"
            else -> "unknown"
        } else null,
        // This is a hint, not proof that the scheduler blocked this download.
        "deviceHot" to (status == DownloadManager.STATUS_PENDING &&
            thermalStatus != null && thermalStatus >= PowerManager.THERMAL_STATUS_MODERATE),
        "received" to received,
        "total" to total,
    )
}
