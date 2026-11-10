// Portions derived from DS Bot (https://github.com/Fei2411/DeepSeek-Bot), Apache-2.0, Copyright 2026 Fei2411 and the DS Bot contributors. See THIRD_PARTY_NOTICES.md.
// Modified: the `show_view` description and prompt rule (`ds-bot/src/host/tools.js`, `prompt.js`)
// rewritten as Chinese instructions for a ```dsh-ui fenced block in a phone chat.
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
        |- 你运行在 Android 手机上的 Ubuntu 24.04 环境里（proot，免 Root）。这里没有可用的沙箱后端（bubblewrap / Landlock 都不可用），`workspace-write` 沙箱模式一定会被拒绝。
""" +
        // l10n:keep agent prompt
        """        |- 需要执行 bash 命令时，直接用 `sandbox_permissions: "danger-full-access"` 申请运行，并用一句话写明理由；不要先试沙箱模式。
        |- 默认工作区是向阳空间（`${'$'}XRK_HOME/xiangyang-workspace`）；不要把 `/root` 当成项目工作区。{STORAGE_LINE}
        |- 家目录是 `${'$'}XRK_HOME`（`/root/.xrk`）。凭证、设置、会话、插件都在这里。
        |- 已预装 node / npm / pnpm、python3 / pip、git；npm 和 pnpm 默认用国内镜像 registry.npmmirror.com。缺别的工具可以 `apt-get update && apt-get install -y <包名>`（需要联网）。
        |- 手机屏幕小：回复尽量简洁，代码块不要太宽；用用户使用的语言回答。
        |
        |## 界面与技能
        |
        |- 这个 App 的对话壳是 Flutter；对话内容在机内 `xrkh serve` 的 Web UI。进程插件落在 `${'$'}XRK_HOME/plugins`。
        |- 用户报障、排查问题、写 bug 反馈时先读本机诊断快照（见下节），再动手。
        |""").trimMargin()

    /**
     * Appended while 「可视化回复」 is on (default): how to answer with a ```dsh-ui view. The
     * component list and the rules are adapted from DS Bot's `show_view` description and prompt
     * rule (`ds-bot/src/host/tools.js`, `prompt.js`), rewritten for a fenced block in a phone chat.
     */
    // l10n:keep agent prompt
    private val XRK_UI_SECTION = ("""
        |
        |## 可视化回复（dsh-ui）
        |
        |- 这个 App 能把带 ```dsh-ui 标记的代码块画成原生的图表和卡片。只在比文字更清楚时用：比较数值或看趋势用 chart，几个关键数字用 metric，方案对比用 compare，步骤和进度用 steps，需要用户点选时用 options 或 confirm。闲聊、单个数字、普通列表都不用。
        |- 先用一两句话给出结论，再放视图。同一份数据不要用文字、表格、图表各写一遍。一条回复最多两个视图。
        |- 必须写成围栏代码块：第一行单独写 ```dsh-ui，下一行开始是 JSON，最后一行单独写 ```。直接把 JSON 裸着写进正文是纯文本，画不出来。
        |- 围栏里只放一个 JSON 对象，不写注释和尾逗号，不超过 4 KB。数据必须真实；示例或估算的数字在 caption 里说明。
        |- 组件：stack / row {children}；text {text}；metric {label, value, tone?: good|warn|bad, caption?}；chart {kind: bar|hbar|line|donut, categories, series: [{name?, values}], unit?, caption?}（values 与 categories 一一对应，最多 6 组、每组 60 个点；donut 只放一组）；compare {items: [{title, badge?, rows: [[名称, 值]]}]}（2–4 项）；steps {items: [{label, status: done|current|todo|failed, detail?}]}；callout {text, tone?: info|good|warn|bad}；options {id, options: [{label, description?}], multi?, freetext?}（最多 8 个）；confirm {id, confirmLabel?, cancelLabel?}。根节点可以带 title。
        |- options 想允许「选项以外」的回答时加 `freetext: true`（也可以写成一句提示词，如 `freetext: "自己写一个"`）：选项下面会出现输入框，用户填的内容会以「其他：…」跟选择一起回传。
""" +
        // l10n:keep agent prompt
        """        |- 例：
        |```dsh-ui
        |{"type":"stack","title":"近 6 个月支出","children":[{"type":"metric","label":"月均","value":"¥4,180"},{"type":"chart","kind":"bar","categories":["5月","6月"],"series":[{"values":[3800,4100]}],"unit":"元"}]}
        |```
""" +
        // l10n:keep agent prompt
        """        |- 含 options 或 confirm 的视图放在回复最后，然后结束这一轮；用户的选择会以一条 "[dsh-ui reply]" 开头的消息发回来（如「选择：方案 A」「确认：开始」；自己填的另起一行「其他：…」）。只问一个简单问题时用 ask_user_question。
        |- 不要用视图收集密码、密钥或验证码。
        |""").trimMargin()

    // l10n:keep agent prompt
    private val DIAGNOSTICS_SECTION = """
        |
        |## 本机诊断
        |
        |- 用户报障（卡顿、发热、连不上、更新失败、闪退、插件不生效、手机操控失败）时，读取可用诊断：用户刚主动发布时优先读同目录的 `diagnostics-manual.md`，否则先读自动快照 `{PATH}`。核对报告时间、版本和设备，再分析引擎状态、连接方式、性能与有限日志；有一份可用就不要因另一份缺失反复要求刷新，读取前不用另问。
        |- 用户点过「让 AI 看诊断」后，同目录的 `diagnostics-manual.md` 保留最近一次手动报告（可能含本次同意采集的输入法证据）；存在时也读它并核对采集时间。后续自动快照不会覆盖它；下一次手动发布才替换，清除 App 内存证据不会撤回已发布文件。
        |- 需要更多细节时，让用户在 设置 → 诊断 里导出诊断包（zip）；它仍受日志数量和大小限制。数据不足就直说，不要凭猜测下结论。
        |- 报告会尝试脱敏，但不能保证没有遗漏。外发前人工检查凭据、路径和设备信息，不把完整报告或秘密原样贴到聊天或 issue 里。
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
        visualReplies: Boolean = true,
        directEngine: Boolean = false,
    ) {
        try {
            val file = File(rootfs, "root/.xrk/AGENTS.md")
            if (file.exists() && !file.readText().startsWith(AGENTS_MARKER)) return
            val environment = if (directEngine) {
                // l10n:keep agent prompt
                AGENTS_MD.replace(
                    "Ubuntu 24.04 环境里（proot，免 Root）",
                    "Ubuntu 24.04 运行环境里（引擎直接启动，bash/git/python/apt 工具仍经 proot）",
                ) +
                    "\n- 文件工具、会话目录、@ 引用、AGENTS 和 skills 使用同一个完整绝对路径；该路径在 shell 内也同名可见。旧的 `/root` 路径仍可用于文件工具。shell 的输出不改写，不要删除路径的前缀。\n"
            } else AGENTS_MD
            val text = environment.replace(
                "{STORAGE_LINE}",
                if (phoneStorage) {
                    // l10n:keep agent prompt
                    "用户已授权访问手机存储：手机内部存储挂载在 `/sdcard`（`/root/手机存储` 是它的快捷方式；相册在 `/sdcard/DCIM`，下载在 `/sdcard/Download`）。改动或删除用户文件前先说明并确认；给用户的产出文件放到 `/sdcard/Download/XRK-Harness/`。"
                } else {
                    // l10n:keep agent prompt
                    "手机相册、下载等用户文件不在这个环境里，看不到；如需访问，请用户在 App 设置里打开「访问手机文件」。"
                },
            ) + (if (visualReplies) XRK_UI_SECTION else "") +
                (if (phoneControl) PhoneGuest.AGENTS_SECTION else "") +
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
