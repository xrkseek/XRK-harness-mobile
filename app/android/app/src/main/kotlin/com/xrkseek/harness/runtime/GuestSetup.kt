// Portions derived from DS Bot (https://github.com/Fei2411/DeepSeek-Bot), Apache-2.0, Copyright 2026 Fei2411 and the DS Bot contributors. See THIRD_PARTY_NOTICES.md.
// Modified: the `show_view` description and prompt rule (`ds-bot/src/host/tools.js`, `prompt.js`)
// rewritten as Chinese instructions for a ```xrk-ui fenced block in a phone chat.
package com.xrkseek.harness.runtime

import android.content.Context
import android.net.ConnectivityManager
import android.system.ErrnoException
import android.system.Os
import com.xrkseek.harness.phone.PhoneGuest
import java.io.File
import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress

/** Small files inside the rootfs that must reflect the device before each start. */
object GuestSetup {
    private val FALLBACK_DNS = listOf("223.5.5.5", "119.29.29.29", "8.8.8.8")

    private const val AGENTS_MARKER = "<!-- xrkh-app:managed"

    // l10n:keep agent prompt
    private val AGENTS_MD = ("""
        |<!-- xrkh-app:managed — 删除这一行后，App 不再覆盖本文件 -->
        |# 运行环境（XRK-Harness 手机版）
        |
        |- Android 上的 Ubuntu 24.04（proot，免 Root）。无 bubblewrap / Landlock → `workspace-write` 沙箱必拒。
""" +
        // l10n:keep agent prompt
        """        |- bash：直接 `sandbox_permissions: "danger-full-access"` + 一句理由；别先试沙箱。
        |- 默认工作区：向阳（`${'$'}XRK_HOME/xiangyang-workspace`）；别把 `/root` 当项目 cwd。{STORAGE_LINE}
        |- 家目录 `${'$'}XRK_HOME`（`/root/.xrk`）：凭证、设置、会话、插件。
        |- 预装 node / npm / pnpm、python3 / pip、git；npm / pnpm 默认 registry.npmmirror.com。缺包：`apt-get update && apt-get install -y <包名>`（需联网）。
        |- 屏小：回复短、代码块别太宽；跟用户语言。
        |
        |## 界面与技能
        |
        |- 本机 `xrkh serve`（harness-cli Host）；进程插件在 `${'$'}XRK_HOME/plugins`。
        |- 报障 / 排查 / 写 bug：先读本机诊断（下节），再动手。
        |""").trimMargin()

    // l10n:keep agent prompt
    private val DIAGNOSTICS_SECTION = """
        |
        |## 本机诊断
        |
        |- 报障（卡顿、发热、连不上、更新失败、闪退、插件、手机操控）：先 `skill` **`xrk-support`**，再读诊断——有同目录 `diagnostics-manual.md`（用户刚「让 AI 看诊断」）优先，否则 `{PATH}`。核对时间 / 版本 / 设备；有一份可用就别因另一份缺失催刷新，读取前不必另问。
        |- `diagnostics-manual.md` 只被下次手动发布替换；自动快照不覆盖；清 App 内存证据不撤回已发布文件。
        |- 要更多细节：请用户 设置 → 诊断 导出 zip（仍有日志限额）。数据不够就直说，别猜。
        |- 报告会脱敏但不保证全净。外发前人工查凭据 / 路径 / 设备；勿把完整报告或秘密贴进聊天 / issue。
        |""".trimMargin()

    /** Where the engine's agent finds that snapshot, inside the guest. */
    private const val DIAGNOSTICS_FILE = "root/.xrk/diagnostics.md"

    /** Atomically replaces one fixed report and returns its actual host file. */
    fun writeDiagnostics(rootfs: File, markdown: String, safe: Boolean = false, manual: Boolean = false): File {
        val path = if (safe) "${SafeMode.HOME.removePrefix("/")}/diagnostics.md" else DIAGNOSTICS_FILE
        val main = File(rootfs, path)
        val dir = main.parentFile ?: throw IOException("no diagnostics directory")
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("cannot create ${dir.path}")
        val file = if (manual) File(dir, "diagnostics-manual.md") else main
        val temp = File(dir, ".${file.name}.xrk-tmp")
        try {
            temp.writeText(markdown)
            if (!temp.renameTo(file)) throw IOException("cannot replace ${file.path}")
        } finally {
            temp.delete()
        }
        return file
    }

    /** Global Host instructions ($XRK_HOME/AGENTS.md); left alone once the user removes the marker. */
    fun writeAgentsMd(
        rootfs: File,
        phoneStorage: Boolean,
        phoneControl: Boolean = false,
        // Retired leftover (DS Bot / native ```xrk-ui fence). Session path is xrkh Host; do not inject.
        @Suppress("UNUSED_PARAMETER") visualReplies: Boolean = false,
        directEngine: Boolean = false,
    ) {
        try {
            val file = File(rootfs, "root/.xrk/AGENTS.md")
            if (file.exists() && !file.readText().startsWith(AGENTS_MARKER)) return
            val environment = if (directEngine) {
                // l10n:keep agent prompt
                AGENTS_MD.replace(
                    "Ubuntu 24.04（proot，免 Root）",
                    "Ubuntu 24.04（引擎直启；bash/git/python/apt 仍经 proot）",
                ) +
                    "\n- 文件工具、会话目录、@ 引用、AGENTS / skills 用同一绝对路径（shell 内同名可见）。旧 `/root` 仍可用于文件工具。shell 输出不改写，勿删路径前缀。\n"
            } else AGENTS_MD
            val text = environment.replace(
                "{STORAGE_LINE}",
                if (phoneStorage) {
                    // l10n:keep agent prompt
                    "已授权手机存储：`/sdcard`（快捷方式 `/root/手机存储`；相册 `/sdcard/DCIM`，下载 `/sdcard/Download`）。改删用户文件前先说明并确认；产出放到 `/sdcard/Download/XRK-Harness/`。"
                } else {
                    // l10n:keep agent prompt
                    "相册 / 下载等用户文件不可见；需要时请用户在 App 设置打开「访问手机文件」。"
                },
            ) + (if (phoneControl) PhoneGuest.AGENTS_SECTION else "") +
                DIAGNOSTICS_SECTION.replace(
                    "{PATH}",
                    if (directEngine) "${rootfs.canonicalPath}/root/.xrk/diagnostics.md"
                    else "\$XRK_HOME/diagnostics.md",
                )
            file.parentFile?.mkdirs()
            if (!file.exists() || file.readText() != text) file.writeText(text)
        } catch (_: Exception) {
        }
    }

    /** glibc in the guest reads /etc/resolv.conf; Android has none, so mirror the active network's DNS. */
    fun writeResolvConf(context: Context, rootfs: File): DnsConfigReport =
        writeResolvConfFromNetwork(rootfs, {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.getLinkProperties(cm.activeNetwork)?.dnsServers.orEmpty()
        }, Os::rename)

    internal fun writeResolvConfFromNetwork(
        rootfs: File,
        readNetwork: () -> List<InetAddress>,
        replace: (String, String) -> Unit,
    ): DnsConfigReport {
        var networkRead = DnsNetworkRead.READ
        val addresses = try {
            readNetwork().also { if (it.isEmpty()) networkRead = DnsNetworkRead.EMPTY }
        } catch (_: Exception) {
            networkRead = DnsNetworkRead.FAILED
            emptyList()
        }
        return writeResolvConf(rootfs, pickDns(addresses), replace).copy(networkRead = networkRead)
    }

    /** Up to two of the network's servers, IPv4 first, then the public fallbacks: three in all. */
    fun pickDns(addrs: List<InetAddress>): List<String> {
        val network = addrs.filterNot { it.isLinkLocalAddress }
            .sortedBy { if (it is Inet4Address) 0 else 1 }
            .mapNotNull { it.hostAddress?.substringBefore('%') }.distinct().take(2)
        return (network + FALLBACK_DNS).distinct().take(3)
    }

    fun writeResolvConf(rootfs: File, servers: List<String>): DnsConfigReport =
        writeResolvConf(rootfs, servers, Os::rename)

    internal fun writeResolvConf(
        rootfs: File,
        servers: List<String>,
        replace: (String, String) -> Unit,
    ): DnsConfigReport {
        val requested = servers.take(3).toList()
        val text = buildString {
            appendLine("# written by xrkh-app from the device's active network")
            servers.forEach { appendLine("nameserver $it") }
            appendLine("options ${DnsConfigReport.OPTIONS}")
        }
        var stage = DnsConfigStage.PREPARE
        try {
            val etc = File(rootfs, "etc")
            if (!etc.isDirectory && !etc.mkdirs() && !etc.isDirectory) throw IOException("Cannot prepare resolver directory")
            val target = File(etc, "resolv.conf")
            stage = DnsConfigStage.READ
            if (target.isFile && target.readText() == text) return DnsConfigReport(DnsConfigOutcome.UNCHANGED, requested)
            // Swapped in whole while XRK runs; also replaces a symlink (e.g. to systemd-resolved) with a plain file.
            val temp = File(etc, ".resolv.conf.xrk-tmp")
            stage = DnsConfigStage.WRITE
            temp.writeText(text)
            stage = DnsConfigStage.REPLACE
            replace(temp.path, target.path)
            return DnsConfigReport(DnsConfigOutcome.WRITTEN, requested)
        } catch (e: Exception) {
            val error = when (e) {
                is ErrnoException -> DnsConfigError.NATIVE
                is SecurityException -> DnsConfigError.SECURITY
                is IOException -> DnsConfigError.IO
                else -> DnsConfigError.OTHER
            }
            return DnsConfigReport(DnsConfigOutcome.FAILED, requested, stage, error, (e as? ErrnoException)?.errno)
        }
    }
}
