package com.xrkseek.harness.runtime

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Enabled process / client plugins and their installed versions at one moment.
 * [patch] is unused under xrkh (no Cordis YAML layer); kept null for the wire shape.
 */
data class ProfileSnapshot(
    /** Enabled plugin names, in inventory order. */
    val bundles: List<String>,
    /** Every inventory entry (enabled or soft-disabled). */
    val deps: Set<String>,
    /** Installed versions from inventory when present. */
    val versions: Map<String, String>,
    /** Always null for xrkh Host; retained so older lkg.json / Flutter maps still parse. */
    val patch: String?,
)

/**
 * What restoring the last good snapshot changes: soft-disable list so the enabled
 * set matches the snapshot (minus packages removed or upgraded since). Nothing is
 * installed or removed from disk.
 */
data class LkgPlan(
    val target: List<String>,
    val disable: List<String>,
    val enable: List<String>,
    /** Enabled packages whose installed version differs from the snapshot's (part of [disable]). */
    val changed: List<String>,
    val patchChanged: Boolean,
    val bundlesChanged: Boolean,
) {
    val isEmpty: Boolean get() = !bundlesChanged && !patchChanged

    fun toMap(): Map<String, Any?> = mapOf(
        "disable" to disable,
        "enable" to enable,
        "changed" to changed,
        "patchChanged" to patchChanged,
        "empty" to isEmpty,
    )

    companion object {
        fun of(lkg: ProfileSnapshot, current: ProfileSnapshot): LkgPlan {
            fun sameVersion(name: String): Boolean {
                val then = lkg.versions[name]
                val now = current.versions[name]
                return then == null || now == null || then == now
            }
            val target = lkg.bundles.filter { name ->
                when {
                    name !in lkg.deps -> true
                    name !in current.deps -> false
                    else -> sameVersion(name)
                }
            }.distinct()
            return LkgPlan(
                target = target,
                disable = current.bundles.filter { it !in target }.distinct(),
                enable = target.filter { it !in current.bundles },
                changed = lkg.bundles.filter { it in lkg.deps && it in current.deps && it in current.bundles && !sameVersion(it) }.distinct(),
                patchChanged = false,
                bundlesChanged = target != current.bundles,
            )
        }
    }
}

/**
 * Last good plugin enable-set for xrkh, kept outside the rootfs in
 * `filesDir/runtime/lkg/lkg.json` and recorded after each healthy two-minute normal run.
 * Truth source: `$XRK_HOME/plugins/.xrk-plugins.json` + `.xrk-plugins-disabled.json`.
 */
object LastKnownGood {
    class Record(val at: Long, val snapshot: ProfileSnapshot)

    fun pluginsDir(rootfs: File): File = File(rootfs, "root/.xrk/plugins")

    fun inventoryFile(rootfs: File): File = File(pluginsDir(rootfs), ".xrk-plugins.json")

    fun disabledFile(rootfs: File): File = File(pluginsDir(rootfs), ".xrk-plugins-disabled.json")

    /** The plugin inventory as it is now; null before xrkh has created it. */
    fun read(rootfs: File): ProfileSnapshot? {
        val inv = inventoryFile(rootfs)
        if (!inv.isFile) return null
        return try {
            parse(JSONObject(wrapInventory(inv.readText())), disabledFile(rootfs))
        } catch (_: Exception) {
            null
        }
    }

    /**
     * What a normal run booted with, fixed when it reports ready: [atLaunch], or on a first boot
     * (Host creates the inventory after the launch read found none) the snapshot [readNow] returns.
     */
    fun bootedAtReady(atLaunch: ProfileSnapshot?, readNow: () -> ProfileSnapshot?): ProfileSnapshot? =
        atLaunch ?: try {
            readNow()
        } catch (_: Exception) {
            null
        }

    /**
     * A healthy run pins exactly what it booted with, never a later read of the disk.
     */
    fun pinBooted(booted: ProfileSnapshot?, save: (ProfileSnapshot) -> Unit): Boolean {
        save(booted ?: return false)
        return true
    }

    /** Accept bare array or `{ "plugins": [...] }`. */
    private fun wrapInventory(text: String): String {
        val trimmed = text.trim()
        return if (trimmed.startsWith("[")) """{"plugins":$trimmed}""" else trimmed
    }

    private fun parse(json: JSONObject, disabledFile: File): ProfileSnapshot {
        val entries = json.optJSONArray("plugins") ?: JSONArray()
        val deps = LinkedHashSet<String>()
        val versions = LinkedHashMap<String, String>()
        val order = ArrayList<String>()
        for (i in 0 until entries.length()) {
            val entry = entries.optJSONObject(i) ?: continue
            val name = sequenceOf("name", "id", "package")
                .map { entry.optString(it) }
                .firstOrNull { it.isNotEmpty() }
                ?: continue
            deps += name
            order += name
            val version = entry.optString("version")
            if (version.isNotEmpty()) versions[name] = version
        }
        val disabled = readDisabled(disabledFile)
        val bundles = order.filter { it !in disabled }
        return ProfileSnapshot(bundles, deps, versions, patch = null)
    }

    private fun readDisabled(file: File): Set<String> {
        if (!file.isFile) return emptySet()
        return try {
            val raw = JSONObject(wrapDisabled(file.readText()))
            raw.optJSONArray("ids").strings().toCollection(LinkedHashSet())
        } catch (_: Exception) {
            emptySet()
        }
    }

    private fun wrapDisabled(text: String): String {
        val trimmed = text.trim()
        return if (trimmed.startsWith("[")) """{"ids":$trimmed}""" else trimmed
    }

    fun load(file: File): Record? {
        if (!file.isFile) return null
        return try {
            val json = JSONObject(file.readText())
            val versionsJson = json.optJSONObject("versions")
            val versions = LinkedHashMap<String, String>()
            versionsJson?.keys()?.forEach { versions[it] = versionsJson.optString(it) }
            Record(
                at = json.optLong("at"),
                snapshot = ProfileSnapshot(
                    bundles = json.optJSONArray("bundles").strings(),
                    deps = json.optJSONArray("deps").strings().toCollection(LinkedHashSet()),
                    versions = versions,
                    patch = null,
                ),
            )
        } catch (_: Exception) {
            null
        }
    }

    fun save(file: File, snapshot: ProfileSnapshot, at: Long) {
        val versions = JSONObject()
        snapshot.versions.forEach { (k, v) -> versions.put(k, v) }
        val json = JSONObject()
            .put("at", at)
            .put("bundles", JSONArray(snapshot.bundles))
            .put("deps", JSONArray(snapshot.deps.toList()))
            .put("versions", versions)
            .put("patch", JSONObject.NULL)
        file.parentFile?.mkdirs()
        SafeMode.writeAtomic(file, json.toString(2) + "\n")
    }

    /**
     * Applies [LkgPlan.of] by rewriting `.xrk-plugins-disabled.json` so enabled names match
     * the plan target. Inventory files stay on disk.
     */
    fun restore(
        rootfs: File, lkg: ProfileSnapshot, stamp: String,
        missingConfig: String = "找不到插件清单 plugins/.xrk-plugins.json", // l10n:keep test default
        busyConfig: String = "插件配置正被别的程序修改，稍后再试", // l10n:keep test default
    ): LkgPlan {
        val inv = inventoryFile(rootfs)
        if (!inv.isFile) throw IllegalStateException(missingConfig)
        val disabledPath = disabledFile(rootfs)
        return withLock(disabledPath, busyConfig) {
            val current = parse(JSONObject(wrapInventory(inv.readText())), disabledPath)
            val plan = LkgPlan.of(lkg, current)
            if (plan.bundlesChanged) {
                if (disabledPath.isFile) {
                    disabledPath.copyTo(File(disabledPath.parentFile, ".xrk-plugins-disabled.json.bak-$stamp"), overwrite = true)
                }
                val disable = current.deps.filter { it !in plan.target }.sorted()
                SafeMode.writeAtomic(
                    disabledPath,
                    JSONObject().put("ids", JSONArray(disable)).toString(2) + "\n",
                )
            }
            plan
        }
    }

    /**
     * Writer lock: sibling `<file>.lock` created exclusively, holding the writer's pid;
     * a lock whose pid no longer exists is taken over.
     */
    private fun <T> withLock(file: File, busyConfig: String, block: () -> T): T {
        file.parentFile?.mkdirs()
        val lock = File(file.path + ".lock")
        val deadline = System.currentTimeMillis() + 3000
        while (true) {
            if (lock.createNewFile()) {
                break
            }
            val holder = try {
                lock.readText().trim().toIntOrNull()
            } catch (_: Exception) {
                null
            }
            if (holder != null && !File("/proc/$holder").exists()) {
                lock.delete()
                continue
            }
            if (System.currentTimeMillis() > deadline) throw IllegalStateException(busyConfig)
            Thread.sleep(50)
        }
        try {
            lock.writeText("${android.os.Process.myPid()}\n")
            return block()
        } finally {
            lock.delete()
        }
    }

    private fun JSONArray?.strings(): List<String> {
        if (this == null) return emptyList()
        val out = ArrayList<String>(length())
        for (i in 0 until length()) optString(i).takeIf { it.isNotEmpty() }?.let { out += it }
        return out
    }
}
