package com.xrkseek.harness.runtime

import java.io.File

/**
 * Message search for the local engine. Host owns session search without Cordis overlays.
 * Clears leftover guest YAML from older installs.
 */
object SessionSearchGuest {
    fun writeFiles(rootfs: File): Boolean {
        File(rootfs, "opt/xrk-app/search.patch.yml").delete()
        File(rootfs, "opt/dsh-app/search.patch.yml").delete()
        return false
    }
}
