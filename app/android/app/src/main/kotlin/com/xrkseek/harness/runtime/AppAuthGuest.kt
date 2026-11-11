package com.xrkseek.harness.runtime

import android.content.Context
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption

/**
 * Subscription sign-in bridge modules for the local engine.
 *
 * Host CLI `--patch` is JSON config only — never Cordis YAML. Modules are staged under
 * [GUEST_DIR] for a future Host-native wire; leftover `auth.patch.yml` files are deleted
 * so they cannot be mistaken for a launch flag.
 */
object AppAuthGuest {
    const val GUEST_DIR = "/opt/xrk-app/auth"
    const val ENTRY = "$GUEST_DIR/index.mjs"

    private const val ASSET_DIR = "flutter_assets/assets/engine/auth"
    private val MODULES = listOf("index.mjs", "bridge.mjs")

    fun writeFiles(context: Context, rootfs: File): Boolean {
        return try {
            val dir = File(rootfs, GUEST_DIR.removePrefix("/"))
            if (Files.isSymbolicLink(dir.toPath()) || (dir.exists() && !dir.isDirectory)) dir.delete()
            if (!dir.isDirectory && !dir.mkdirs()) throw IOException("could not create ${dir.path}")
            for (name in MODULES) {
                val bytes = context.assets.open("$ASSET_DIR/$name").use { it.readBytes() }
                writeIfChanged(File(dir, name), bytes)
            }
            File(dir, "auth.patch.yml").delete()
            File(rootfs, "opt/dsh-app/auth/auth.patch.yml").delete()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun writeIfChanged(target: File, bytes: ByteArray) {
        if (Files.isRegularFile(target.toPath(), LinkOption.NOFOLLOW_LINKS) && target.readBytes().contentEquals(bytes)) return
        val tmp = File(target.parentFile, ".${target.name}.xrk-app-${System.nanoTime()}.tmp")
        try {
            tmp.writeBytes(bytes)
            tmp.setReadable(true, false)
            if (!tmp.renameTo(target)) throw IOException("could not replace ${target.path}")
        } finally {
            if (tmp.exists()) tmp.delete()
        }
    }
}
