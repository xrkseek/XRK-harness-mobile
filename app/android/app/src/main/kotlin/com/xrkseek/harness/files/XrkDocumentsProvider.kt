package com.xrkseek.harness.files

import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.webkit.MimeTypeMap
import com.xrkseek.harness.R
import com.xrkseek.harness.phone.PhoneGuest
import com.xrkseek.harness.runtime.PhoneStorage
import java.io.File
import java.io.FileNotFoundException

/**
 * System document picker roots for MT Manager / Files (Termux-style).
 *
 * | Picker root | Host path | Guest path for the AI |
 * |---|---|---|
 * | XRK Harness | `filesDir/runtime/rootfs/root` | `/root` (Linux home, not Android su) |
 * | XRK · 手机存储 | shared storage | `/sdcard` — **same** tree the engine binds when「访问手机文件」is on |
 *
 * Path math lives in [XrkDocumentTree]. This class only talks to Android SAF.
 */
class XrkDocumentsProvider : DocumentsProvider() {
    companion object {
        const val AUTHORITY_SUFFIX = ".documents"

        private val DEFAULT_ROOT_PROJECTION = arrayOf(
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_MIME_TYPES,
            Root.COLUMN_FLAGS,
            Root.COLUMN_ICON,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_AVAILABLE_BYTES,
        )
        private val DEFAULT_DOC_PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
        )

        /** Re-query roots after storage permission /「访问手机文件」changes. */
        fun notifyRootsChanged(context: Context) {
            val authority = context.packageName + AUTHORITY_SUFFIX
            context.contentResolver.notifyChange(DocumentsContract.buildRootsUri(authority), null)
        }
    }

    private lateinit var app: Context

    override fun onCreate(): Boolean {
        app = context!!.applicationContext
        return true
    }

    private fun tree(): XrkDocumentTree {
        val guest = File(app.filesDir, "runtime/rootfs/root")
        val xrk = File(app.filesDir, "runtime/rootfs/${PhoneGuest.XRK_HOME_REL}")
        // Same gate as the engine bind: setting + grant + readable host root.
        // MT's second root then means the AI can also see /sdcard after restart.
        val phone = PhoneStorage.boundHostRoot(app)
        return XrkDocumentTree(guest, xrk, phone)
    }

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val cols = projection ?: DEFAULT_ROOT_PROJECTION
        val result = MatrixCursor(cols)
        val guest = File(app.filesDir, "runtime/rootfs/root")
        if (!guest.isDirectory) guest.mkdirs()
        addRoot(
            result, cols,
            rootId = XrkDocumentTree.ROOT_GUEST,
            documentId = XrkDocumentTree.DOC_GUEST,
            title = "XRK Harness",
            summary = "机内 /root · 含 .xrk",
            bytes = guest.usableSpace,
        )
        PhoneStorage.boundHostRoot(app)?.let { phone ->
            addRoot(
                result, cols,
                rootId = XrkDocumentTree.ROOT_PHONE,
                documentId = XrkDocumentTree.DOC_PHONE,
                title = "XRK · 手机存储",
                summary = PhoneStorage.GUEST_PATH,
                bytes = phone.usableSpace,
            )
        }
        return result
    }

    private fun addRoot(
        result: MatrixCursor,
        cols: Array<out String>,
        rootId: String,
        documentId: String,
        title: String,
        summary: String,
        bytes: Long,
    ) {
        val row = result.newRow()
        for (col in cols) {
            when (col) {
                Root.COLUMN_ROOT_ID -> row.add(rootId)
                Root.COLUMN_MIME_TYPES -> row.add("*/*")
                Root.COLUMN_FLAGS -> row.add(
                    Root.FLAG_SUPPORTS_CREATE or
                        Root.FLAG_SUPPORTS_IS_CHILD or
                        Root.FLAG_LOCAL_ONLY,
                )
                Root.COLUMN_ICON -> row.add(R.mipmap.ic_launcher)
                Root.COLUMN_TITLE -> row.add(title)
                Root.COLUMN_SUMMARY -> row.add(summary)
                Root.COLUMN_DOCUMENT_ID -> row.add(documentId)
                Root.COLUMN_AVAILABLE_BYTES -> row.add(bytes)
                else -> row.add(null)
            }
        }
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val cols = projection ?: DEFAULT_DOC_PROJECTION
        val result = MatrixCursor(cols)
        val t = tree()
        includeFile(result, cols, t.resolve(documentId), documentId)
        return result
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val cols = projection ?: DEFAULT_DOC_PROJECTION
        val result = MatrixCursor(cols)
        val t = tree()
        val parent = t.resolve(parentDocumentId)
        if (!parent.isDirectory) return result
        if (parentDocumentId == XrkDocumentTree.DOC_HOME ||
            parentDocumentId == XrkDocumentTree.DOC_GUEST
        ) {
            t.ensureInbox()
        }
        for (child in t.listChildren(parent)) {
            includeFile(result, cols, child, t.docIdFor(child))
        }
        return result
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor {
        val file = tree().resolve(documentId)
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.parseMode(mode))
    }

    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
        val t = tree()
        val parent = t.resolve(parentDocumentId)
        if (!parent.isDirectory) throw FileNotFoundException("not a directory")
        val safe = displayName.replace(Regex("[\\\\/]+"), "_").trim().ifEmpty { "file" }
        val dest = File(parent, safe)
        if (Document.MIME_TYPE_DIR == mimeType) {
            if (!dest.mkdirs() && !dest.isDirectory) throw FileNotFoundException("mkdir failed")
        } else {
            if (!dest.createNewFile() && !dest.isFile) throw FileNotFoundException("create failed")
        }
        return t.docIdFor(dest)
    }

    override fun deleteDocument(documentId: String) {
        val t = tree()
        if (t.isProtectedRoot(documentId)) {
            throw UnsupportedOperationException("cannot delete root folders")
        }
        val file = t.resolve(documentId)
        if (!file.deleteRecursively()) throw FileNotFoundException("delete failed")
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean =
        tree().isChildDocument(parentDocumentId, documentId)

    private fun includeFile(result: MatrixCursor, cols: Array<out String>, file: File, docId: String) {
        val row = result.newRow()
        val isDir = file.isDirectory
        val flags = when {
            isDir -> Document.FLAG_DIR_SUPPORTS_CREATE or Document.FLAG_SUPPORTS_DELETE
            else -> Document.FLAG_SUPPORTS_WRITE or Document.FLAG_SUPPORTS_DELETE
        }
        for (col in cols) {
            when (col) {
                Document.COLUMN_DOCUMENT_ID -> row.add(docId)
                Document.COLUMN_DISPLAY_NAME -> row.add(
                    when (docId) {
                        XrkDocumentTree.DOC_GUEST -> "机内 /root"
                        XrkDocumentTree.DOC_HOME -> ".xrk"
                        XrkDocumentTree.DOC_INBOX -> "inbox"
                        XrkDocumentTree.DOC_PHONE -> "手机存储"
                        else -> file.name
                    },
                )
                Document.COLUMN_MIME_TYPE -> row.add(
                    if (isDir) Document.MIME_TYPE_DIR else mimeOf(file.name),
                )
                Document.COLUMN_FLAGS -> row.add(flags)
                Document.COLUMN_SIZE -> row.add(if (isDir) null else file.length())
                Document.COLUMN_LAST_MODIFIED -> row.add(file.lastModified())
                else -> row.add(null)
            }
        }
    }

    private fun mimeOf(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        if (ext.isEmpty()) return "application/octet-stream"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }
}
