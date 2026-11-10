package com.xrkseek.harness.runtime

import java.io.File

/**
 * Message search for the local engine. Product runtime is `xrkh serve` (Host owns
 * session search without a Cordis `--patch` overlay). This helper only clears any
 * leftover guest patch from older installs.
 */
object SessionSearchGuest {
    const val PATCH = "/opt/xrk-app/search.patch.yml"

    private const val WEB_PATCH_ARG = "--patch /etc/xrk-app/xrk-web.patch.yml"
    private const val XRK_WEB = "/usr/local/bin/xrkh serve"

    // Kept for launchArg callers that still inspect legacy templates.
    val PATCH_YAML = """# xrk-app: message search (unused on xrkh Host).
- id: session-query-sqlite
  config:
    path: /root/.xrk/session-search.sqlite
    openAt: first-search
"""

    /** Legacy `xrkh serve --patch` only. Current launch templates return null. */
    fun launchArg(arg: String): String? {
        val web = arg.indexOf("$XRK_WEB ")
        if (web < 0 || arg.indexOf("$XRK_WEB ", web + 1) >= 0 || arg.contains("--profile")) return null
        val patch = arg.indexOf(WEB_PATCH_ARG, web)
        val at = if (patch >= 0 && arg.indexOf(WEB_PATCH_ARG, patch + 1) < 0) patch + WEB_PATCH_ARG.length else web + XRK_WEB.length
        return arg.substring(0, at) + " --patch $PATCH" + arg.substring(at)
    }

    fun file(rootfs: File) = File(rootfs, PATCH.removePrefix("/"))

    /** Clear legacy overlay files; xrkh Host does not need them. */
    fun writeFiles(rootfs: File): Boolean {
        file(rootfs).delete()
        File(rootfs, "opt/dsh-app/search.patch.yml").delete()
        return false
    }
}
