package com.xrkseek.harness.files

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.FileObserver
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.core.content.FileProvider
import com.xrkseek.harness.phone.Json
import com.xrkseek.harness.phone.PhoneGuest
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Watches guest `open-request.json` (xdg-open / termux-open shim inside the
 * proot virtual container) and opens a *copy* via FileProvider.
 *
 * Surfaces: phone thin shell only. Desktop / ordinary browsers never hit this
 * path; guest Termux-in-container open still lands here through the shim.
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
        if (inside != null && inside.canRead() && underRoot(rootCanon, inside) && (inside.isFile || inside.isDirectory)) {
            return inside
        }
        val direct = runCatching { File(guestPath).canonicalFile }.getOrNull()
        if (direct != null && direct.canRead() && underRoot(rootCanon, direct) && (direct.isFile || direct.isDirectory)) {
            return direct
        }
        return null
    }

    private fun underRoot(root: File, file: File): Boolean =
        file == root || file.path.startsWith(root.path + File.separator)

    private fun openCopy(file: File) {
        // System Files cannot browse the proot rootfs. Directories stay in the
        // Host workspace panel; copy the guest path so the person can paste it.
        if (file.isDirectory) {
            val guestHint = file.absolutePath
            main.post {
                runCatching {
                    val cm = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("XRK path", guestHint))
                }
                Toast.makeText(
                    app,
                    "机内目录已复制路径：${file.name}（请在右侧「工作区文件」浏览；系统资源管理器打不开机内盘）",
                    Toast.LENGTH_LONG,
                ).show()
            }
            return
        }
        val share = File(app.cacheDir, "share").apply { mkdirs() }
        val dest = File(share, file.name.ifBlank { "open.bin" })
        runCatching { file.copyTo(dest, overwrite = true) }.onFailure {
            log("[xrk-mobile] open-request: copy failed ${it.message}")
            main.post {
                Toast.makeText(app, "打不开文件：${file.name}", Toast.LENGTH_SHORT).show()
            }
            return
        }
        val authority = "${app.packageName}.files"
        val mime = OpenPathMime.forFile(dest)
        val uri = try {
            FileProvider.getUriForFile(app, authority, dest)
        } catch (_: IllegalArgumentException) {
            log("[xrk-mobile] open-request: FileProvider refused ${dest.path}")
            main.post {
                Toast.makeText(app, "打不开文件：${dest.name}", Toast.LENGTH_SHORT).show()
            }
            return
        }
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        view.clipData = ClipData.newRawUri(dest.name, uri)

        val canView = app.packageManager
            .queryIntentActivities(view, PackageManager.MATCH_DEFAULT_ONLY)
            .isNotEmpty()
        if (canView) {
            try {
                app.startActivity(Intent.createChooser(view, dest.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: ActivityNotFoundException) {
                log("[xrk-mobile] open-request: VIEW chooser missing for $mime")
            } catch (e: Exception) {
                log("[xrk-mobile] open-request: VIEW ${e.message}")
            }
        }

        // No VIEW handler (common for pptx → octet-stream before the MIME table):
        // fall back to ACTION_SEND so the person can open in WPS / Drive / …
        val send = Intent(Intent.ACTION_SEND)
            .setType(mime)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        send.clipData = ClipData.newRawUri(dest.name, uri)
        try {
            app.startActivity(
                Intent.createChooser(send, "分享 ${dest.name}")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: ActivityNotFoundException) {
            log("[xrk-mobile] open-request: no app for VIEW/SEND $mime")
            main.post {
                Toast.makeText(app, "没有能打开 $mime 的应用，请安装 WPS / Office 后再试", Toast.LENGTH_LONG).show()
            }
        } catch (e: Exception) {
            log("[xrk-mobile] open-request: ${e.message}")
            main.post {
                Toast.makeText(app, "打开失败：${e.message ?: dest.name}", Toast.LENGTH_SHORT).show()
            }
        }
    }
}
