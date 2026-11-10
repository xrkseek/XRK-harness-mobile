package com.xrkseek.harness.files

import android.webkit.MimeTypeMap
import java.io.File

/**
 * MIME for guest open-via-FileProvider. Android's [MimeTypeMap] often returns
 * null for Office Open XML (`pptx` / `docx` / `xlsx`), which collapses to
 * `application/octet-stream` and hides WPS / Office from ACTION_VIEW.
 *
 * Prefer the extension table for those types; otherwise ask MimeTypeMap.
 */
object OpenPathMime {
    private val BY_EXT = mapOf(
        "ppt" to "application/vnd.ms-powerpoint",
        "pptx" to "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "pps" to "application/vnd.ms-powerpoint",
        "ppsx" to "application/vnd.openxmlformats-officedocument.presentationml.slideshow",
        "doc" to "application/msword",
        "docx" to "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls" to "application/vnd.ms-excel",
        "xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "pdf" to "application/pdf",
        "txt" to "text/plain",
        "md" to "text/markdown",
        "csv" to "text/csv",
        "json" to "application/json",
        "zip" to "application/zip",
        "png" to "image/png",
        "jpg" to "image/jpeg",
        "jpeg" to "image/jpeg",
        "gif" to "image/gif",
        "webp" to "image/webp",
        "svg" to "image/svg+xml",
        "mp4" to "video/mp4",
        "webm" to "video/webm",
        "mp3" to "audio/mpeg",
        "wav" to "audio/wav",
        "html" to "text/html",
        "htm" to "text/html",
    )

    /** Table lookup only (JVM-testable without MimeTypeMap). */
    fun fromExtension(ext: String): String? = BY_EXT[ext.trim().lowercase().removePrefix(".")]

    fun forFile(file: File): String {
        val ext = file.extension.lowercase()
        fromExtension(ext)?.let { return it }
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }
}
