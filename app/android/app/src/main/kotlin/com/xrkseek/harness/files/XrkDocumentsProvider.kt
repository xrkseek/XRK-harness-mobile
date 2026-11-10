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
import java.io.File
import java.io.FileNotFoundException

/**
 * Surfaces guest `$XRK_HOME` (and its `inbox/`) in the system document picker —
 * the same place Termux appears — so people can open / save files without ADB.
 *
 * Host path: `filesDir/runtime/rootfs/root/.xrk`. Absent until the runtime is
 * installed; the root still lists so the entry is discoverable.
 */
class XrkDocumentsProvider : DocumentsProvider() {
    companion object {
        const val AUTHORITY_SUFFIX = ".documents"
        private const val ROOT_ID = "xrk"
        private const val DOC_HOME = "home"
        private const val DOC_INBOX = "inbox"

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
    }

    private lateinit var app: Context

    override fun onCreate(): Boolean {
        app = context!!.applicationContext
        return true
    }

    private fun xrkHome(): File = File(app.filesDir, "runtime/rootfs/${PhoneGuest.XRK_HOME_REL}")

    private fun resolve(docId: String): File = when (docId) {
        ROOT_ID, DOC_HOME -> xrkHome()
        DOC_INBOX -> File(xrkHome(), "inbox")
        else -> {
            val rel = docId.removePrefix("$DOC_HOME/").removePrefix("$DOC_INBOX/")
            val base = if (docId.startsWith("$DOC_INBOX/") || docId == DOC_INBOX) {
                File(xrkHome(), "inbox")
            } else {
                xrkHome()
            }
            val target = File(base, rel).canonicalFile
            if (!target.path.startsWith(xrkHome().canonicalFile.path)) {
                throw FileNotFoundException("outside XRK home")
            }
            target
        }
    }

    private fun docIdFor(file: File): String {
        val home = xrkHome().canonicalFile
        val path = file.canonicalFile.path
        if (path == home.path) return DOC_HOME
        val inbox = File(home, "inbox").canonicalFile
        if (path == inbox.path) return DOC_INBOX
        if (path.startsWith(inbox.path + File.separator)) {
            return "$DOC_INBOX/${path.removePrefix(inbox.path + File.separator).replace(File.separatorChar, '/')}"
        }
        if (path.startsWith(home.path + File.separator)) {
            return "$DOC_HOME/${path.removePrefix(home.path + File.separator).replace(File.separatorChar, '/')}"
        }
        throw FileNotFoundException(path)
    }

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val cols = projection ?: DEFAULT_ROOT_PROJECTION
        val result = MatrixCursor(cols)
        val home = xrkHome()
        if (!home.isDirectory) home.mkdirs()
        val row = result.newRow()
        for (col in cols) {
            when (col) {
                Root.COLUMN_ROOT_ID -> row.add(ROOT_ID)
                Root.COLUMN_MIME_TYPES -> row.add("*/*")
                Root.COLUMN_FLAGS -> row.add(
                    Root.FLAG_SUPPORTS_CREATE or
                        Root.FLAG_SUPPORTS_IS_CHILD or
                        Root.FLAG_LOCAL_ONLY,
                )
                Root.COLUMN_ICON -> row.add(R.mipmap.ic_launcher)
                Root.COLUMN_TITLE -> row.add("XRK Harness")
                Root.COLUMN_SUMMARY -> row.add("机内工作区 · inbox")
                Root.COLUMN_DOCUMENT_ID -> row.add(DOC_HOME)
                Root.COLUMN_AVAILABLE_BYTES -> row.add(home.usableSpace)
                else -> row.add(null)
            }
        }
        return result
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val cols = projection ?: DEFAULT_DOC_PROJECTION
        val result = MatrixCursor(cols)
        includeFile(result, cols, resolve(documentId), documentId)
        return result
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val cols = projection ?: DEFAULT_DOC_PROJECTION
        val result = MatrixCursor(cols)
        val parent = resolve(parentDocumentId)
        if (!parent.isDirectory) return result
        // Ensure inbox exists so the first open is useful.
        if (parentDocumentId == DOC_HOME) {
            File(parent, "inbox").mkdirs()
        }
        val children = parent.listFiles()?.sortedWith(compareBy({ !it.isDirectory }, { it.name.lowercase() }))
            ?: emptyList()
        for (child in children) {
            if (child.name.startsWith('.')) continue
            includeFile(result, cols, child, docIdFor(child))
        }
        return result
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor {
        val file = resolve(documentId)
        val access = ParcelFileDescriptor.parseMode(mode)
        return ParcelFileDescriptor.open(file, access)
    }

    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
        val parent = resolve(parentDocumentId)
        if (!parent.isDirectory) throw FileNotFoundException("not a directory")
        val safe = displayName.replace(Regex("[\\\\/]+"), "_").trim().ifEmpty { "file" }
        val dest = File(parent, safe)
        if (Document.MIME_TYPE_DIR == mimeType) {
            if (!dest.mkdirs() && !dest.isDirectory) throw FileNotFoundException("mkdir failed")
        } else {
            if (!dest.createNewFile() && !dest.isFile) throw FileNotFoundException("create failed")
        }
        return docIdFor(dest)
    }

    override fun deleteDocument(documentId: String) {
        val file = resolve(documentId)
        if (documentId == DOC_HOME || documentId == DOC_INBOX) {
            throw UnsupportedOperationException("cannot delete root folders")
        }
        if (!file.deleteRecursively()) throw FileNotFoundException("delete failed")
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        return documentId == parentDocumentId ||
            documentId.startsWith("$parentDocumentId/") ||
            (parentDocumentId == DOC_HOME && (documentId == DOC_INBOX || documentId.startsWith("$DOC_INBOX/")))
    }

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
                        DOC_HOME -> "XRK Home"
                        DOC_INBOX -> "inbox"
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
