package io.github.ccch1mneyyy.dsh_app.files

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.os.FileObserver
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.github.ccch1mneyyy.dsh_app.phone.Json
import io.github.ccch1mneyyy.dsh_app.phone.PhoneGuest
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Watches guest `open-request.json` (xdg-open shim) and opens a *copy* via FileProvider.
 */
class OpenPathWatcher(
    private val app: Context,
    private val rootfs: () -> File?,
    private val log: (String) -> Unit,
) {
    private val running = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())
    private var observer: FileObserver? = null
    private var lastStamp = ""

    fun start() {
        if (!running.compareAndSet(false, true)) return
        val root = rootfs() ?: run {
            running.set(false)
            return
        }
        val queue = PhoneGuest.guestFile(root, PhoneGuest.OPEN_QUEUE)
        val dir = queue.parentFile ?: run {
            running.set(false)
            return
        }
        dir.mkdirs()
        @Suppress("DEPRECATION")
        observer = object : FileObserver(dir.absolutePath, CLOSE_WRITE or MOVED_TO or MODIFY) {
            override fun onEvent(event: Int, path: String?) {
                if (!running.get()) return
                if (path == null || path == queue.name) drain()
            }
        }.also { it.startWatching() }
        drain()
    }

    fun stop() {
        running.set(false)
        observer?.stopWatching()
        observer = null
    }

    /** Host.openPath / HTTP `POST /v1/open`. */
    fun openGuestPath(guestPath: String): Boolean {
        val root = rootfs() ?: return false
        val hostFile = resolveGuest(root, guestPath) ?: return false
        main.post { openCopy(hostFile) }
        return true
    }

    private fun drain() {
        if (!running.get()) return
        val root = rootfs() ?: return
        val queue = PhoneGuest.guestFile(root, PhoneGuest.OPEN_QUEUE)
        if (!queue.isFile) return
        val text = runCatching { queue.readText() }.getOrNull() ?: return
        if (text == lastStamp || text.trim().isEmpty() || text.trim() == "{}") return
        lastStamp = text
        val map = runCatching { Json.parse(text) as? Map<*, *> }.getOrNull() ?: return
        val path = map["path"] as? String ?: return
        if (path.isBlank()) return
        runCatching { queue.writeText("{}\n") }
        if (!openGuestPath(path)) log("[xrk-mobile] open-request: missing $path")
    }

    private fun resolveGuest(rootfs: File, guestPath: String): File? {
        val rootCanon = runCatching { rootfs.canonicalFile }.getOrNull() ?: return null
        val rel = guestPath.removePrefix("/")
        val inside = runCatching { File(rootfs, rel).canonicalFile }.getOrNull()
        if (inside != null && inside.isFile && inside.canRead() && underRoot(rootCanon, inside)) {
            return inside
        }
        val direct = runCatching { File(guestPath).canonicalFile }.getOrNull()
        if (direct != null && direct.isFile && direct.canRead() && underRoot(rootCanon, direct)) {
            return direct
        }
        return null
    }

    private fun underRoot(root: File, file: File): Boolean =
        file == root || file.path.startsWith(root.path + File.separator)

    private fun openCopy(file: File) {
        val share = File(app.cacheDir, "share").apply { mkdirs() }
        val dest = File(share, file.name.ifBlank { "open.bin" })
        runCatching { file.copyTo(dest, overwrite = true) }.onFailure {
            log("[xrk-mobile] open-request: copy failed ${it.message}")
            return
        }
        val authority = "${app.packageName}.files"
        val mime = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(dest.extension.lowercase())
            ?: "application/octet-stream"
        val uri = try {
            FileProvider.getUriForFile(app, authority, dest)
        } catch (_: IllegalArgumentException) {
            log("[xrk-mobile] open-request: FileProvider refused ${dest.path}")
            return
        }
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        view.clipData = ClipData.newRawUri(dest.name, uri)
        try {
            app.startActivity(Intent.createChooser(view, dest.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            log("[xrk-mobile] open-request: no app for $mime")
        } catch (e: Exception) {
            log("[xrk-mobile] open-request: ${e.message}")
        }
    }
}
