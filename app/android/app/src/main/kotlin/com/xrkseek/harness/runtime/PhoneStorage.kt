package com.xrkseek.harness.runtime

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings

/**
 * Optional access to the phone's **shared storage** from the Linux guest.
 *
 * This is **not** Android su/root. Turning on「访问手机文件」grants ordinary
 * storage permission and, on engine start, bind-mounts the same host tree at
 * guest [/GUEST_PATH] (`/sdcard`). The AI then reads/writes that path; MT
 * Manager sees the same tree as the DocumentsProvider「手机存储」root when
 * [boundHostRoot] is non-null (setting + grant + readable).
 *
 * With targetSdk 28 the app keeps legacy external storage, so the classic
 * READ/WRITE_EXTERNAL_STORAGE grant is enough; "All files access" is the fallback
 * for devices that don't honour legacy mode.
 */
object PhoneStorage {
    /** Guest path the phone's internal storage appears at. */
    const val GUEST_PATH = "/sdcard"

    /** Flutter SharedPreferences keys for Settings toggles (see LaunchStart / settings_state). */
    const val PREFS_NAME = "FlutterSharedPreferences"
    const val PREFS_ENABLED_KEY = "flutter.phone_storage"
    const val PREFS_VISUAL_REPLIES_KEY = "flutter.visual_replies"

    fun hostRoot(): String = Environment.getExternalStorageDirectory().absolutePath // /storage/emulated/0

    fun isGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) return true
        val write = context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        if (!write) return false
        // Legacy view: the permission really grants file-path access to shared storage.
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || Environment.isExternalStorageLegacy()
    }

    /** Settings →「访问手机文件」persisted by Flutter. */
    fun settingEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(PREFS_ENABLED_KEY, false)

    /** Settings →「可视化回复」; default on (matches Flutter AppSettings). */
    fun visualRepliesEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(PREFS_VISUAL_REPLIES_KEY, true)

    /**
     * Host directory the engine would bind at [/GUEST_PATH], or null when the
     * AI would not see phone storage (setting off, no grant, or unreadable).
     * Single gate for SAF「手机存储」, listOutputs, and proot `/sdcard` binds.
     */
    fun boundHostRoot(context: Context): java.io.File? {
        if (!settingEnabled(context) || !isGranted(context)) return null
        val root = java.io.File(hostRoot())
        return if (root.canRead()) root else null
    }

    fun status(context: Context): Map<String, Any?> = mapOf(
        "granted" to isGranted(context),
        "permission" to (context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED),
        "legacy" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || Environment.isExternalStorageLegacy()),
        "setting" to settingEnabled(context),
        "bound" to (boundHostRoot(context) != null),
        "guestPath" to GUEST_PATH,
        "hostPath" to hostRoot(),
    )

    /** proot `-b` values: the phone's storage at /sdcard, plus /storage for absolute paths apps share. */
    fun binds(): List<String> {
        // Skip the mount rather than fail the launch when the path isn't readable.
        if (!java.io.File(hostRoot()).canRead()) return emptyList()
        return listOf("${hostRoot()}:$GUEST_PATH", "/storage")
    }

    /** `/root/手机存储` → `/sdcard` inside the rootfs, present only while the mode is on. */
    fun syncShortcut(rootfs: java.io.File, enabled: Boolean) {
        // l10n:keep guest filesystem path
        val link = java.io.File(rootfs, "root/手机存储")
        try {
            val info = android.system.Os.lstat(link.path)
            if (!enabled && android.system.OsConstants.S_ISLNK(info.st_mode) &&
                android.system.Os.readlink(link.path) == GUEST_PATH) {
                link.delete()
            }
            return
        } catch (_: Exception) {
            // absent
        }
        if (enabled) runCatching { android.system.Os.symlink(GUEST_PATH, link.path) }
    }

    /** Opens the system "All files access" page for this app (Android 11+). */
    fun allFilesAccessIntent(context: Context): Intent? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
