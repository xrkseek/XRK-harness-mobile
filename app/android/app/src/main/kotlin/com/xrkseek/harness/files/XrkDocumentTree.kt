package com.xrkseek.harness.files

import java.io.File
import java.io.FileNotFoundException

/**
 * Pure document-id ↔ host-path map for [XrkDocumentsProvider].
 *
 * Two trees the picker (and bookmarks) can walk:
 * 1. **guest** — proot home `…/rootfs/root` (Linux `/root`). Contains `.xrk`
 *    (`$XRK_HOME`), workspaces, `.agents`. Not Android su/root.
 * 2. **phone** — shared storage host root (guest `/sdcard` when the engine
 *    binds it). Same directory the AI sees after「访问手机文件」; omitted when
 *    [phoneRoot] is null.
 *
 * Legacy ids `home` / `inbox` stay under `$XRK_HOME` so old SAF bookmarks keep
 * resolving after the primary root moved from `.xrk` up to `/root`.
 */
internal class XrkDocumentTree(
    private val guestHome: File,
    private val xrkHome: File,
    private val phoneRoot: File?,
) {
    fun resolve(docId: String): File = when (docId) {
        DOC_GUEST, ROOT_GUEST -> guestHome
        DOC_HOME -> xrkHome
        DOC_INBOX -> File(xrkHome, "inbox")
        DOC_PHONE, ROOT_PHONE -> phoneRoot ?: throw FileNotFoundException("phone storage not available")
        else -> when {
            docId.startsWith("$DOC_PHONE/") -> {
                val base = phoneRoot ?: throw FileNotFoundException("phone storage not available")
                childUnder(base, docId.removePrefix("$DOC_PHONE/"), "outside phone storage")
            }
            docId.startsWith("$DOC_INBOX/") -> {
                childUnder(File(xrkHome, "inbox"), docId.removePrefix("$DOC_INBOX/"), "outside XRK home")
                    .also { requireUnder(xrkHome, it, "outside XRK home") }
            }
            docId.startsWith("$DOC_HOME/") ->
                childUnder(xrkHome, docId.removePrefix("$DOC_HOME/"), "outside XRK home")
            docId.startsWith("$DOC_GUEST/") ->
                childUnder(guestHome, docId.removePrefix("$DOC_GUEST/"), "outside guest home")
            else -> throw FileNotFoundException(docId)
        }
    }

    fun docIdFor(file: File): String {
        val path = file.canonicalFile.path
        phoneRoot?.canonicalFile?.let { phone ->
            if (path == phone.path) return DOC_PHONE
            if (path.startsWith(phone.path + File.separator)) {
                return "$DOC_PHONE/${rel(phone.path, path)}"
            }
        }
        val home = xrkHome.canonicalFile
        val inbox = File(home, "inbox").canonicalFile
        if (path == inbox.path) return DOC_INBOX
        if (path.startsWith(inbox.path + File.separator)) {
            return "$DOC_INBOX/${rel(inbox.path, path)}"
        }
        if (path == home.path) return DOC_HOME
        if (path.startsWith(home.path + File.separator)) {
            // Prefer short `home/…` under $XRK_HOME (legacy + visible `.xrk` child).
            return "$DOC_HOME/${rel(home.path, path)}"
        }
        val guest = guestHome.canonicalFile
        if (path == guest.path) return DOC_GUEST
        if (path.startsWith(guest.path + File.separator)) {
            return "$DOC_GUEST/${rel(guest.path, path)}"
        }
        throw FileNotFoundException(path)
    }

    fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        if (documentId == parentDocumentId || documentId.startsWith("$parentDocumentId/")) return true
        if (parentDocumentId == DOC_GUEST) {
            if (documentId == DOC_HOME || documentId.startsWith("$DOC_HOME/")) return true
            if (documentId == DOC_INBOX || documentId.startsWith("$DOC_INBOX/")) return true
        }
        if (parentDocumentId == DOC_HOME &&
            (documentId == DOC_INBOX || documentId.startsWith("$DOC_INBOX/"))
        ) {
            return true
        }
        return false
    }

    fun isProtectedRoot(docId: String): Boolean =
        docId == DOC_GUEST || docId == DOC_HOME || docId == DOC_INBOX || docId == DOC_PHONE

    /** Children for a directory listing; keeps product dot-dirs, hides other dots. */
    fun listChildren(parent: File): List<File> {
        val children = parent.listFiles()
            ?.sortedWith(compareBy({ !it.isDirectory }, { it.name.lowercase() }))
            ?: return emptyList()
        return children.filter { child ->
            val name = child.name
            !name.startsWith('.') || name in VISIBLE_DOT_DIRS
        }
    }

    fun ensureInbox() {
        File(xrkHome, "inbox").mkdirs()
    }

    private fun childUnder(base: File, rel: String, escapeMessage: String): File {
        // Reject empty / absolute segments so `File(base, "/x")` cannot jump off base
        // before the canonical check (platform-dependent).
        if (rel.isEmpty() || rel.startsWith("/") || rel.startsWith("\\")) {
            throw FileNotFoundException(escapeMessage)
        }
        val target = File(base, rel).canonicalFile
        requireUnder(base, target, escapeMessage)
        return target
    }

    private fun requireUnder(base: File, candidate: File, escapeMessage: String) {
        if (!under(base, candidate)) throw FileNotFoundException(escapeMessage)
    }

    companion object {
        const val ROOT_GUEST = "guest"
        const val ROOT_PHONE = "phone"
        const val DOC_GUEST = "guest"
        const val DOC_HOME = "home"
        const val DOC_INBOX = "inbox"
        const val DOC_PHONE = "phone"

        val VISIBLE_DOT_DIRS: Set<String> = setOf(".xrk", ".agents")

        fun under(base: File, candidate: File): Boolean {
            val root = base.canonicalFile.path
            val path = candidate.canonicalFile.path
            return path == root || path.startsWith(root + File.separator)
        }

        private fun rel(parentPath: String, childPath: String): String =
            childPath.removePrefix(parentPath + File.separator).replace(File.separatorChar, '/')
    }
}
