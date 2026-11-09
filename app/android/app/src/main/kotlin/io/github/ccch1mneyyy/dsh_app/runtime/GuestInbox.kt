package io.github.ccch1mneyyy.dsh_app.runtime

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import io.github.ccch1mneyyy.dsh_app.phone.PhoneGuest
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.nio.file.Files
import java.util.Locale

/**
 * Stages a host-side share/open-with file into the guest `$XRK_HOME/inbox/` so
 * xrkh can read it by path without base64 through the WebView.
 */
object GuestInbox {
    const val GUEST_DIR = "/${PhoneGuest.XRK_HOME_REL}/inbox"
    private const val MAX_NAME = 180
    /** Same ceiling as SharePlugin — paperclip oversized files stage here, not through WebView. */
    const val MAX_BYTES = 512L * 1024 * 1024

    /**
     * Stream-copy [hostPath] into the guest inbox. Returns guest absolute path
     * (`/root/.xrk/inbox/…`) and byte length.
     */
    fun stage(rootfs: File, hostPath: String, preferredName: String?): Map<String, Any?> {
        val src = File(hostPath)
        if (!src.isFile) throw IOException("source missing")
        src.inputStream().use { input ->
            return stageStream(rootfs, input, preferredName?.takeIf { it.isNotBlank() } ?: src.name)
        }
    }

    /**
     * Stream-copy a `content://` pick into the guest inbox (mobile WebView paperclip
     * for files too large for Face byte attachments — no Desktop path bridge).
     */
    fun stageUri(context: Context, rootfs: File, uri: Uri, preferredName: String?): Map<String, Any?> {
        val resolver = context.contentResolver
        var name = preferredName?.takeIf { it.isNotBlank() }
        var size = -1L
        runCatching {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use {
                if (it.moveToFirst()) {
                    val n = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val s = it.getColumnIndex(OpenableColumns.SIZE)
                    if (name == null && n >= 0 && !it.isNull(n)) name = it.getString(n)
                    if (s >= 0 && !it.isNull(s)) size = it.getLong(s)
                }
            }
        }
        if (size > MAX_BYTES) throw IOException("file too large")
        val input = resolver.openInputStream(uri) ?: throw IOException("unreadable uri")
        input.use { stream ->
            return stageStream(rootfs, stream, name ?: uri.lastPathSegment ?: "file", maxBytes = MAX_BYTES)
        }
    }

    private fun stageStream(
        rootfs: File,
        input: InputStream,
        preferredName: String,
        maxBytes: Long = MAX_BYTES,
    ): Map<String, Any?> {
        val inbox = PhoneGuest.guestFile(rootfs, GUEST_DIR)
        if (Files.isSymbolicLink(inbox.toPath()) || (inbox.exists() && !inbox.isDirectory)) {
            inbox.delete()
        }
        if (!inbox.isDirectory && !inbox.mkdirs()) throw IOException("could not create inbox")
        val name = sanitizeName(preferredName)
        var dest = File(inbox, name)
        if (dest.exists()) {
            val stem = name.substringBeforeLast('.', name)
            val ext = if (name.contains('.')) ".${name.substringAfterLast('.')}" else ""
            var n = 1
            while (dest.exists()) {
                dest = File(inbox, "$stem-$n$ext")
                n++
                if (n > 999) throw IOException("inbox name collision")
            }
        }
        dest.outputStream().use { output ->
            val buffer = ByteArray(256 * 1024)
            var copied = 0L
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                copied += read
                if (copied > maxBytes) {
                    output.close()
                    dest.delete()
                    throw IOException("file too large")
                }
                output.write(buffer, 0, read)
            }
        }
        val guestPath = "$GUEST_DIR/${dest.name}"
        return mapOf(
            "guestPath" to guestPath,
            "hostPath" to dest.absolutePath,
            "bytes" to dest.length(),
            "name" to dest.name,
        )
    }

    private fun sanitizeName(raw: String): String {
        val base = raw.replace('\\', '/').substringAfterLast('/').trim()
        val cleaned = buildString(base.length.coerceAtMost(MAX_NAME)) {
            for (c in base) {
                when {
                    c.isLetterOrDigit() || c == '.' || c == '-' || c == '_' || c == ' ' -> append(c)
                    else -> append('_')
                }
                if (length >= MAX_NAME) break
            }
        }.trim().trim('.')
        return if (cleaned.isEmpty()) "file-${System.currentTimeMillis()}" else cleaned.lowercase(Locale.ROOT).let {
            // Keep original casing for readability; only reject empty.
            cleaned
        }
    }
}
