package io.github.ccch1mneyyy.dsh_app.links

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.github.ccch1mneyyy.dsh_app.MainActivity
import io.github.ccch1mneyyy.dsh_app.share.SharePlugin

/**
 * Receives VIEW (WeChat / file manager "open with") and dshgo:// links, then
 * hands them to MainActivity's own task.
 *
 * Apps like WeChat start a VIEW activity inside their own task, without
 * FLAG_ACTIVITY_NEW_TASK; aimed at MainActivity that would create a second Flutter activity
 * there. Forwarding with NEW_TASK | SINGLE_TOP | CLEAR_TOP brings the existing MainActivity
 * forward. File VIEW intents are remapped to [SharePlugin.ACTION_SHARE] so the share
 * pipeline copies bytes into cache and the thin shell drops them on the composer.
 */
class LinkTrampolineActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val received = intent
        val data: Uri? = received.data
        val isFileView = received.action == Intent.ACTION_VIEW &&
            data != null &&
            (data.scheme == "content" || data.scheme == "file")
        val forward = Intent(received).apply {
            setClass(this@LinkTrampolineActivity, MainActivity::class.java)
            if (isFileView) {
                action = SharePlugin.ACTION_SHARE
                putExtra(SharePlugin.EXTRA_SENT_AS, Intent.ACTION_VIEW)
                putExtra(Intent.EXTRA_STREAM, data)
                if (clipData == null && data != null) {
                    clipData = ClipData.newRawUri(null, data)
                }
            }
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        try {
            startActivity(forward)
        } catch (_: SecurityException) {
            forward.removeFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            try {
                startActivity(forward)
            } catch (_: Exception) {
            }
        } catch (_: Exception) {
        }
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}
