package com.xrkseek.harness.runtime

import java.io.File

/**
 * Overlay-update gate for the local runtime.
 *
 * Product rule: chats / credentials / settings / skills live under guest `/root`
 * and must survive APK replace. The old gate only compared [runtimeVersion], so a
 * shell-only bump (same bundled runtime) skipped heal and could start Host against
 * interrupted leftover trees (`home.carry`, broken essentials) — clean install
 * worked, 16→17 overlay failed, 17→17 looked fine.
 *
 * Algorithm:
 * 1. Interrupted upgrade leftovers → force reinstall (activateRootfs restores carry).
 * 2. Version / rootfs sha mismatch → reinstall (carry `/root`).
 * 3. Same runtime, app versionCode changed → soft-heal volatiles only; keep `/root`.
 * 4. Otherwise ready.
 */
internal object RuntimeUpgrade {
    const val K_APP_VERSION_CODE = "appVersionCode"
    const val K_INSTALLED_ROOTFS_SHA = "installedRootfsSha256"

    data class Snapshot(
        val installedVersion: String?,
        val bundledVersion: String,
        val bundledSha: String?,
        val stampedAppCode: Long,
        val currentAppCode: Long,
        val stampedSha: String?,
        val carryExists: Boolean,
        val stagingExists: Boolean,
        val retiredExists: Boolean,
        val essentialsOk: Boolean,
        val homeExists: Boolean,
    )

    data class Plan(
        /** Full rootfs extract + [activateRootfs] (preserves carry/`/root`). */
        val needInstall: Boolean,
        /** Same runtime; clear volatiles / host failure card; keep user home. */
        val softHeal: Boolean,
        /** Move `rootfs/root` → `home.carry` before the next install. */
        val prepareCarry: Boolean,
        /** Drop a stale `rootfs.version` so [RuntimeInstaller.isCurrent] is false. */
        val clearVersionMarker: Boolean,
        val clearStaging: Boolean,
        val clearRetired: Boolean,
        val clearHostFailureCard: Boolean,
        val stampAppCode: Boolean,
        val stampSha: Boolean,
        val note: String?,
    )

    fun plan(s: Snapshot): Plan {
        // 1) Interrupted upgrade: never call the tree "current".
        if (s.carryExists) {
            return Plan(
                needInstall = true,
                softHeal = false,
                prepareCarry = false,
                clearVersionMarker = true,
                clearStaging = true,
                clearRetired = true,
                clearHostFailureCard = true,
                stampAppCode = true,
                stampSha = true,
                note = "overlay: resume interrupted runtime upgrade (home.carry)",
            )
        }

        val versionMatch = s.installedVersion != null && s.installedVersion == s.bundledVersion
        val shaMismatch = !s.bundledSha.isNullOrEmpty() &&
            !s.stampedSha.isNullOrEmpty() &&
            !s.bundledSha.equals(s.stampedSha, ignoreCase = true)

        // 2) Marker claims ready but tree is incomplete / sha drifted → reinstall, keep home.
        if (versionMatch && (!s.essentialsOk || shaMismatch)) {
            return Plan(
                needInstall = true,
                softHeal = false,
                prepareCarry = s.homeExists,
                clearVersionMarker = true,
                clearStaging = true,
                clearRetired = true,
                clearHostFailureCard = true,
                stampAppCode = true,
                stampSha = true,
                note = if (shaMismatch) "overlay: bundled rootfs sha changed; reinstall keeping /root"
                else "overlay: runtime marker present but essentials missing; reinstall keeping /root",
            )
        }

        // 3) Different runtime fingerprint → normal upgrade install (activateRootfs carries /root).
        if (!versionMatch) {
            return Plan(
                needInstall = s.installedVersion != null || s.homeExists || s.stagingExists || s.retiredExists,
                softHeal = false,
                prepareCarry = false, // activateRootfs moves home itself when rootfs still present
                clearVersionMarker = false,
                clearStaging = s.stagingExists && s.installedVersion == null,
                clearRetired = false,
                clearHostFailureCard = s.installedVersion != null,
                stampAppCode = true,
                stampSha = true,
                note = if (s.installedVersion == null) null else "overlay: runtime version ${s.installedVersion} → ${s.bundledVersion}",
            )
        }

        // 4) Same runtime, new app build → soft heal only (preserve all of /root).
        val appBumped = s.stampedAppCode >= 0L && s.currentAppCode != s.stampedAppCode
        val firstStamp = s.stampedAppCode < 0L
        if (appBumped || firstStamp) {
            return Plan(
                needInstall = false,
                softHeal = appBumped,
                prepareCarry = false,
                clearVersionMarker = false,
                clearStaging = s.stagingExists,
                clearRetired = s.retiredExists,
                clearHostFailureCard = appBumped,
                stampAppCode = true,
                stampSha = s.stampedSha.isNullOrEmpty() && !s.bundledSha.isNullOrEmpty(),
                note = if (appBumped) "overlay: app build ${s.stampedAppCode} → ${s.currentAppCode}; soft-heal, keep /root"
                else null,
            )
        }

        // 5) Ready; still drop junk dirs if any.
        if (s.stagingExists || s.retiredExists) {
            return Plan(
                needInstall = false,
                softHeal = false,
                prepareCarry = false,
                clearVersionMarker = false,
                clearStaging = s.stagingExists,
                clearRetired = s.retiredExists,
                clearHostFailureCard = false,
                stampAppCode = false,
                stampSha = false,
                note = "overlay: drop leftover staging/rootfs.old",
            )
        }

        return Plan(
            needInstall = false,
            softHeal = false,
            prepareCarry = false,
            clearVersionMarker = false,
            clearStaging = false,
            clearRetired = false,
            clearHostFailureCard = false,
            stampAppCode = false,
            stampSha = false,
            note = null,
        )
    }

    fun essentialsPresent(rootfs: File): Boolean {
        if (!rootfs.isDirectory) return false
        val xrkh = File(rootfs, "usr/local/bin/xrkh")
        val node = File(rootfs, "opt/node/bin/node")
        return xrkh.isFile && node.isFile
    }

    /**
     * Volatile / shell-owned cleanup only. Preserves sessions, settings, credentials,
     * plugins, skills and workspaces under `root/` (including `root/.xrk` data files).
     * Returns short log lines for anything moved/removed.
     */
    fun softHealGuest(rootfs: File): List<String> {
        if (!rootfs.isDirectory) return emptyList()
        val notes = ArrayList<String>()
        val pid = File(rootfs, "tmp/xrk-web.pid")
        if (pid.delete()) notes += "removed tmp/xrk-web.pid"
        for (rel in listOf(
            "opt/xrk-app/auth/auth.patch.yml",
            "opt/dsh-app/auth/auth.patch.yml",
            "opt/xrk-app/phone/phone.patch.yml",
            "opt/dsh-app/phone/phone.patch.yml",
        )) {
            val f = File(rootfs, rel)
            if (f.isFile && f.delete()) notes += "removed $rel"
        }
        // Bootstrap-only names in .env make every Host profile refuse to start.
        val hazards = SafeMode.preflight(rootfs)
        if (hazards.isNotEmpty()) {
            val stamp = "shell-${System.currentTimeMillis()}"
            val moved = SafeMode.moveAside(rootfs, hazards.map { it.path }, stamp)
            moved.moved.forEach { (from, to) -> notes += "moved $from → $to" }
        }
        // Writer locks left by a killed previous shell (never user content).
        val xrk = File(rootfs, "root/.xrk")
        if (xrk.isDirectory) {
            xrk.walkTopDown().maxDepth(4).forEach { file ->
                if (file.isFile && file.name.endsWith(".lock") && file.delete()) {
                    notes += "removed ${file.relativeTo(rootfs).invariantSeparatorsPath}"
                }
            }
        }
        return notes
    }

    fun prepareCarry(base: File): Boolean {
        val carry = File(base, "home.carry")
        if (carry.exists()) return true
        val home = File(base, "rootfs/root")
        if (!home.isDirectory) return false
        return home.renameTo(carry)
    }

    fun clearVersionMarker(base: File) {
        File(base, "rootfs.version").delete()
    }
}
