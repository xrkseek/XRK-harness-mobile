package com.xrkseek.harness.runtime

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Whether the next local start uses the rescue profile. */
enum class SafeState(val wire: String) {
    OFF("off"),

    /** Starts use the safe profile until the user asks for normal mode. */
    ON("on"),

    /** Back in normal mode on trial: a counted failure within the first two minutes returns to [ON]. */
    PROBATION("probation");

    companion object {
        fun parse(wire: String?): SafeState = entries.firstOrNull { it.wire == wire } ?: OFF
    }
}

/** The safe-mode state machine, free of Android so it can be checked on the JVM. */
object SafePolicy {
    const val STRIKE_LIMIT = 2
    const val HEALTHY_MS = 120_000L

    /**
     * Delay before restarting a run that was killed from outside after more than a minute up, or
     * null: at most three tries (5 s, 15 s, 45 s) in ten minutes. [recent] holds the earlier tries.
     */
    fun autoRestartDelay(kind: FailureKind, exitCode: Int, upMs: Long?, recent: List<Long>, now: Long): Long? {
        if (kind != FailureKind.KILLED || exitCode == 0 || upMs == null || upMs <= 60_000L) return null
        val count = recent.count { now - it < 600_000L }
        return listOf(5_000L, 15_000L, 45_000L).getOrNull(count)
    }

    /** [mode] is what the caller asked for: "safe", "normal", or null to keep the current mode. */
    fun onStartRequest(state: SafeState, mode: String?): SafeState = when (mode) {
        "safe" -> SafeState.ON
        "normal" -> if (state == SafeState.ON) SafeState.PROBATION else state
        else -> state
    }

    data class Outcome(
        val state: SafeState,
        val strikes: Int,
        /** Start again right away in safe mode. */
        val restartSafe: Boolean,
        val notice: String?,
        /** New value for the "why are we in safe mode" field; null keeps it. */
        val reason: String?,
    )

    fun onFailure(
        state: SafeState, strikes: Int, failure: RunFailure, autoSafe: Boolean,
        probationNotice: String = "正常模式还是起不来，已回到安全模式。", // l10n:keep test default
        autoNotice: String = "XRK 连续两次启动失败，已用安全模式启动。你的对话都在。", // l10n:keep test default
    ): Outcome {
        // Safe-mode runs never count against the main profile; uncounted kinds change nothing.
        if (failure.safeMode || !failure.kind.counts) return Outcome(state, strikes, false, null, null)
        val next = strikes + 1
        return when {
            state == SafeState.PROBATION ->
                Outcome(SafeState.ON, next, true, probationNotice, REASON_PROBATION)
            next >= STRIKE_LIMIT && autoSafe ->
                Outcome(SafeState.ON, next, true, autoNotice, REASON_AUTO)
            else -> Outcome(state, next, false, null, null)
        }
    }

    /**
     * A direct run that could not launch (the classifier's direct-only launch errors): start again
     * with PRoot instead of failing. Says nothing about plugins, so it never reaches [onFailure].
     */
    fun directLaunchFailed(failure: RunFailure, direct: Boolean): Boolean =
        direct && failure.kind == FailureKind.LAUNCH_FAILED

    const val REASON_MANUAL = "manual"
    const val REASON_AUTO = "auto"
    const val REASON_PROBATION = "probation"
}

/** A file in the shared XRK home that also applies to the safe profile. */
data class Hazard(val path: String, val kind: String, val detail: String) {
    fun toMap(): Map<String, Any?> = mapOf("path" to path, "kind" to kind, "detail" to detail)
}

/**
 * The rescue profile: rebuilt from XRK's shipped `web` template on every safe start, with the
 * app's overlay turning off plugin management and live recomposition, plus a briefing that tells
 * the agent what broke and how to repair the main profile.
 */
object SafeMode {
    const val PROFILE = "xrk-app-safe"
    const val GUEST_DIR = "/var/lib/xrk-app/safe-mode"
    const val ORIGINAL_HOME = "/root/.xrk"
    const val HOME = "$GUEST_DIR/home"
    const val AGENTS_HOME = "$GUEST_DIR/agents"
    const val TOOL = "$GUEST_DIR/bin/xrk-app-plugins"

    /** Optional launch-template placeholder; templates without it get [LEGACY_NORMAL] rewritten. */
    const val PROFILE_ARGS_PLACEHOLDER = "{XRK_PROFILE_ARGS}"
    // Host CLI: `serve` (alias `web`). No Cordis `--profile` / YAML `--patch`.
    const val NORMAL_PROFILE_ARGS = "serve"
    const val SAFE_PROFILE_ARGS = "serve"
    private const val LEGACY_NORMAL = "/usr/local/bin/xrkh serve "
    private const val LEGACY_SAFE = "/usr/local/bin/xrkh $SAFE_PROFILE_ARGS "

    /** Extra guest environment for safe starts only. */
    val GUEST_ENV: Map<String, String> = linkedMapOf(
        "XRK_HOME" to HOME, "XRK_APP_ORIGINAL_HOME" to ORIGINAL_HOME,
        "XRK_AGENTS_HOME" to AGENTS_HOME, "XRK_APP_SAFE_MODE" to "1",
    )

    /**
     * The launch argument with the profile selection for this mode, or null when [arg] selects
     * no profile (then it is used as is). A safe start whose template yields no rewrite must be
     * refused by the caller.
     */
    fun profileArg(arg: String, safe: Boolean): String? {
        if (arg.contains(PROFILE_ARGS_PLACEHOLDER)) {
            return arg.replace(PROFILE_ARGS_PLACEHOLDER, if (safe) SAFE_PROFILE_ARGS else NORMAL_PROFILE_ARGS)
        }
        if (!safe) return null
        val first = arg.indexOf(LEGACY_NORMAL)
        if (first < 0 || arg.indexOf(LEGACY_NORMAL, first + 1) >= 0) return null
        return arg.replace(LEGACY_NORMAL, LEGACY_SAFE)
    }

    // ── Preflight ───────────────────────────────────────────────────────────────────

    /**
     * Files that move aside on request; nothing else is ever renamed.
     * Cordis `cordis.patch.yml` is gone — xrkh reads `settings.yaml` / plugin inventory, not YAML overlays.
     */
    val MOVABLE = listOf("/root/.xrk/.env", "/root/.env")

    /** XRK 0.2.1's bootstrap-only names (`isBootstrapOnly` in xrk-app-boot): a `.env` setting one stops every profile. */
    private val BOOTSTRAP_NAMES = setOf(
        "PATH", "HOME", "USERPROFILE", "SHELL", "NODE_OPTIONS", "NODE_PATH", "NODE_EXTRA_CA_CERTS",
        "LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT", "BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS",
        "PERL5OPT", "PERL5LIB", "PYTHONSTARTUP", "PYTHONPATH", "RUBYOPT", "RUBYLIB", "JAVA_TOOL_OPTIONS",
        "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS", "PYTHONHOME", "GIT_SSH", "GIT_SSH_COMMAND", "GIT_EXTERNAL_DIFF",
        "GIT_PAGER", "GIT_EDITOR", "GIT_ASKPASS", "SSH_ASKPASS", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM",
        "GIT_CONFIG_COUNT", "EDITOR", "VISUAL", "PAGER", "BROWSER", "DEEPSEEK_BASE_URL", "DEEPSEEK_SEARCH_BASE_URL",
        "SSL_CERT_FILE", "SSL_CERT_DIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
        "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE", "NODE_TLS_REJECT_UNAUTHORIZED",
    )
    private val BOOTSTRAP_PREFIXES = listOf("XRK_", "XDG_", "DYLD_", "BASH_FUNC_")
    private val HOME_PROXY_NAMES = setOf("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")
    private val ENV_NAME = Regex("^\\s*(?:export\\s+)?([A-Za-z_][A-Za-z0-9_.-]*)\\s*=")

    /** A patch layer that is only comments, blank lines or `[]`. */
    fun isTrivialPatch(text: String): Boolean {
        val body = text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }.joinToString("")
        return body.isEmpty() || body == "[]"
    }

    /** Names in a `.env` that XRK refuses to start with ([home] = the `$XRK_HOME/.env`, which may set proxies). */
    fun launchOnlyNames(text: String, home: Boolean): List<String> = text.lineSequence()
        .mapNotNull { ENV_NAME.find(it)?.groupValues?.get(1) }
        .filter { name ->
            val upper = name.uppercase(Locale.ROOT)
            val bootstrap = upper in BOOTSTRAP_NAMES || BOOTSTRAP_PREFIXES.any { upper.startsWith(it) }
            bootstrap && !(home && upper in HOME_PROXY_NAMES)
        }
        .distinct()
        .toList()

    fun preflight(
        rootfs: File,
        envDetail: (List<String>) -> String = { names ->
            "设置了 ${names.joinToString("、")}，XRK 不允许在 .env 里设置这些变量，会拒绝启动。" // l10n:keep test default
        },
    ): List<Hazard> {
        val out = ArrayList<Hazard>()
        readIfFile(guestFile(rootfs, MOVABLE[0]))?.let { text ->
            val names = launchOnlyNames(text, home = true)
            if (names.isNotEmpty()) {
                out += Hazard(MOVABLE[0], "homeEnv", envDetail(names))
            }
        }
        readIfFile(guestFile(rootfs, MOVABLE[1]))?.let { text ->
            val names = launchOnlyNames(text, home = false)
            if (names.isNotEmpty()) {
                out += Hazard(MOVABLE[1], "cwdEnv", envDetail(names))
            }
        }
        return out
    }

    data class MoveAsideResult(val moved: List<Pair<String, String>>, val failure: IOException? = null)

    /** Stops at a failed rename; earlier successful moves remain available for the repair briefing. */
    fun moveAside(rootfs: File, guestPaths: List<String>, stamp: String): MoveAsideResult {
        val moved = ArrayList<Pair<String, String>>()
        for (path in guestPaths.distinct()) {
            if (path !in MOVABLE) continue
            val file = guestFile(rootfs, path)
            if (!file.isFile) continue
            var target = File(file.parentFile, "${file.name}.off-$stamp")
            var n = 1
            while (target.exists()) target = File(file.parentFile, "${file.name}.off-$stamp-${n++}")
            if (!file.renameTo(target)) {
                return MoveAsideResult(moved, IOException("could not move $path aside; ${moved.size} file(s) already moved"))
            }
            moved += path to (path.substringBeforeLast('/') + "/" + target.name)
        }
        return MoveAsideResult(moved)
    }

    // ── Guest files ─────────────────────────────────────────────────────────────────

    data class Briefing(
        /** The main profile's last failure (not a safe-mode one), if any. */
        val failure: RunFailure?,
        /** [SafePolicy.REASON_AUTO], [SafePolicy.REASON_PROBATION], [SafePolicy.REASON_MANUAL] or null. */
        val reason: String?,
        /** `from → to` guest paths moved aside before this start. */
        val moved: List<String>,
        val lkgAt: Long?,
        val lkgBundles: List<String>,
        val lkgVersions: Map<String, String>,
        /** Output around the failure, tokens already masked. */
        val failureLog: List<String>,
        val timeZone: TimeZone = TimeZone.getDefault(),
    )

    /** Writes the agent briefing, the failure data and the repair tool under [GUEST_DIR]. */
    fun prepare(rootfs: File, briefing: Briefing) {
        val dir = realDir(guestFile(rootfs, GUEST_DIR))
        val home = File(dir, "home")
        if (Files.isSymbolicLink(home.toPath()) || (home.exists() && !home.isDirectory)) {
            throw IOException("rescue home must be a real directory: ${home.path}")
        }
        realDir(home)
        val agents = realDir(File(dir, "agents"))
        val bin = realDir(File(dir, "bin"))
        // Host `--patch` is JSON only — never leave Cordis YAML overlays for argv injection.
        File(dir, "overlay.patch.yml").delete()
        writeAtomic(File(agents, "AGENTS.md"), renderBriefing(briefing))
        writeAtomic(
            File(dir, "last-failure.log"),
            // l10n:keep agent repair briefing
            if (briefing.failureLog.isEmpty()) "（没有记录到失败时的输出）\n" else briefing.failureLog.joinToString("\n", postfix = "\n"),
        )
        val f = briefing.failure
        val failureFile = File(dir, "failure.json")
        if (f == null) failureFile.delete() else writeAtomic(failureFile, json(f.toMap()) + "\n")
        val lkgFile = File(dir, "lkg.json")
        if (briefing.lkgAt == null) {
            lkgFile.delete()
        } else {
            writeAtomic(lkgFile, json(mapOf("at" to briefing.lkgAt, "bundles" to briefing.lkgBundles, "versions" to briefing.lkgVersions)) + "\n")
        }
        val tool = File(bin, "xrk-app-plugins")
        writeAtomic(tool, PLUGINS_SCRIPT)
        tool.setReadable(true, false)
        tool.setExecutable(true, false)
    }

    fun renderBriefing(b: Briefing): String = buildString {
        val f = b.failure
        // l10n:keep agent repair briefing
        appendLine("<!-- xrk-app:safe-mode — XRK App 每次进入安全模式时重写本文件，改了也会被覆盖 -->")
        // l10n:keep agent repair briefing
        appendLine("# 你现在运行在「安全模式」")
        appendLine()
        appendLine(
            // l10n:keep agent repair briefing
            "用户的正常配置（profile `web`）出了问题。App 用纯净 profile `$PROFILE` 启动了你：只有 XRK 自带组件，" +
                // l10n:keep agent repair briefing
                "没有任何第三方插件，插件管理和热加载都关掉了。原对话、登录和 API Key 保留在原目录，未复制到救援环境；救援助手可能需要重新配置模型。" +
                // l10n:keep agent repair briefing
                "你的任务是帮用户把 `web` 修好，让它能正常启动。",
        )
        appendLine()
        // l10n:keep agent repair briefing
        appendLine("## 这次出了什么事")
        if (f == null) {
            // l10n:keep agent repair briefing
            appendLine("- 用户手动进入了安全模式，App 没有记录到最近的崩溃。先问用户遇到了什么问题，再按下面的步骤查。")
        } else {
            // l10n:keep agent repair briefing
            appendLine("- 时间：${formatTime(f.at, b.timeZone)}；类型：${kindText(f)}；退出码：${f.exitCode}")
            // l10n:keep agent repair briefing
            f.summary?.let { appendLine("- 摘要：`$it`") }
            if (f.kind != FailureKind.LAUNCH_FAILED && f.requiredRows.isNotEmpty()) {
                appendLine(
                    // l10n:keep agent repair briefing
                    "- 没能启动的必需配置行：${f.requiredRows.joinToString("、") { "`$it`" }}。它们是被改坏的官方行，" +
                        // l10n:keep agent repair briefing
                        "不一定是元凶；用 `$TOOL blame` 查是谁改了它们。",
                )
            }
            // l10n:keep agent repair briefing
            val suspects = if (f.kind == FailureKind.LAUNCH_FAILED) emptyList() else f.suspects.map { "`$it`（崩溃信息里出现）" } +
                // l10n:keep agent repair briefing
                f.recent.filter { it !in f.suspects }.map { "`$it`（上次正常运行后新启用或升级过）" }
            // l10n:keep agent repair briefing
            appendLine("- 可疑插件：" + if (suspects.isEmpty()) "没能自动判断" else suspects.joinToString("、"))
            // l10n:keep agent repair briefing
            appendLine("- 失败前后的输出（token 已打码）：`$GUEST_DIR/last-failure.log`")
            // l10n:keep agent repair briefing
            appendLine("- XRK 启动诊断：" + (f.diagnostics?.let { "`$it`（里面可能有密钥，不要整段贴给用户）" } ?: "无"))
        }
        when (b.reason) {
            // l10n:keep agent repair briefing
            SafePolicy.REASON_AUTO -> appendLine("- 进入方式：主配置连续两次启动失败，App 自动进入了安全模式。")
            // l10n:keep agent repair briefing
            SafePolicy.REASON_PROBATION -> appendLine("- 进入方式：用户试过「恢复正常模式」，但正常模式 2 分钟内又崩了，App 自动回到了安全模式。")
            // l10n:keep agent repair briefing
            SafePolicy.REASON_MANUAL -> if (f != null) appendLine("- 进入方式：用户手动进入。")
        }
        if (b.moved.isNotEmpty()) {
            appendLine(
                // l10n:keep agent repair briefing
                "- App 已把这些全局文件改名移开（原配置仍需检查这些文件，工作目录 .env 也可能影响安全模式）：${b.moved.joinToString("；")}。" +
                    // l10n:keep agent repair briefing
                    "修好后和用户确认，再决定要不要改回来。",
            )
        }
        appendLine()
        // l10n:keep agent repair briefing
        appendLine("## 原数据与救援数据")
        // l10n:keep agent repair briefing
        appendLine("- 安全模式默认使用官方 PTC 预设，也可选择官方 Minimal；Standard 和 Creator 依赖已关闭的插件管理服务，在安全模式中不可用。正常模式的预设不变。")
        // l10n:keep agent repair briefing
        appendLine("- 当前救援 XRK_HOME 是 `$HOME`；原数据在 `$ORIGINAL_HOME`，修复工具和 trial 始终针对原目录。原对话不会显示在救援会话列表里。")
        // l10n:keep agent repair briefing
        appendLine("- 救援模式的 App 诊断快照在 `$HOME/diagnostics.md`；先在 App 设置里生成诊断。")
        // l10n:keep agent repair briefing
        appendLine("- 无需模型或发送消息：已有救援会话可直接打开标题详情里的终端。首次空库时，先切换到「网页模式」，让官方页面自动创建空救援会话，再通过 XRK 原生悬浮手柄「切回原生界面」保留该会话，打开标题详情里的终端。运行 `$TOOL export \"\$PWD/xrk-recovery.tar\"`，再在该对话的文件页长按归档保存到手机。必须指定尚不存在、位于原数据目录之外的输出文件。")
        // l10n:keep agent repair briefing
        appendLine("- 导出保留原始 sessions、attachments 和 workspace 元数据，包括损坏记录；不会修复数据，不是完整插件或工作区备份。符号链接只保存链接，不读取目标。归档含私人对话和图片，妥善保存；诊断包使用 App 设置里的诊断导出入口。")
        appendLine()
        // l10n:keep agent repair briefing
        appendLine("## 主配置在哪")
        // l10n:keep agent repair briefing
        appendLine("- `/root/.xrk/plugins/`：进程插件与 client 壳插件（`.xrk-plugins.json` 为清单）。")
        // l10n:keep agent repair briefing
        appendLine("- `/root/.xrk/.credentials.yaml` · `/root/.xrk/settings.yaml`：凭据与设置；`/root/.xrk/logs/`：Host 启动诊断。")
        // l10n:keep agent repair briefing
        appendLine("- 原数据根下的 `/root/.xrk/.env` 仍可能影响启动；救援数据根与原 HOME 隔离。工作目录的 `/root/.env` 仍需单独检查。")
        if (b.lkgAt == null) {
            // l10n:keep agent repair briefing
            appendLine("- App 还没有记录过正常运行时的插件配置。")
        } else {
            appendLine(
                // l10n:keep agent repair briefing
                "- 上次正常运行（${formatTime(b.lkgAt, b.timeZone)}）时启用的组合包：" +
                    b.lkgBundles.joinToString("、") { name -> "`$name`" + (b.lkgVersions[name]?.let { "@$it" } ?: "") } + "。",
            )
        }
        appendLine()
        // l10n:keep agent repair briefing
        appendLine("## 怎么查")
        // l10n:keep agent repair briefing
        appendLine("1. `$TOOL list`：已装插件清单、是否第三方、和上次正常运行时比有没有变。")
        // l10n:keep agent repair briefing
        appendLine("2. `$TOOL blame`：打印 `xrkh dump-config` 的 JSON 摘要，对照失败日志里的配置字段。")
        // l10n:keep agent repair briefing
        appendLine("3. 运行时崩溃看 `/root/.xrk/logs/` 与 `$TOOL trial`（对原 HOME 试启 `xrkh serve`）。")
        appendLine()
        // l10n:keep agent repair briefing
        appendLine("## 怎么修（先做可逆的）")
        // l10n:keep agent repair briefing
        appendLine("1. 停用可疑插件：`$TOOL disable <包名>`。只改启用清单，不删文件，不需要网络；`$TOOL enable <包名>` 可以撤销。")
        // l10n:keep agent repair briefing
        appendLine("2. 设置写坏了：备份后编辑 `/root/.xrk/settings.yaml` / `.credentials.yaml`（或移开 `/root/.xrk/.env`）。")
        // l10n:keep agent repair briefing
        appendLine("3. 用户确认不要这个插件了，再卸载：`XRK_HOME=$ORIGINAL_HOME xrkh plugin remove <包名>`。")
        appendLine(
            // l10n:keep agent repair briefing
            "4. 实在修不好，先问用户，再移开可疑插件目录或 `.xrk-plugins.json` 条目：" +
                // l10n:keep agent repair briefing
                "下次正常启动会按干净清单加载；对话历史不受影响。",
        )
        // l10n:keep agent repair briefing
        appendLine("每一步改了什么都告诉用户。")
        appendLine()
        // l10n:keep agent repair briefing
        appendLine("## 怎么验证")
        appendLine(
            // l10n:keep agent repair briefing
            "- `$TOOL trial`：在另一个端口试启动 web，看到 PASS 再说修好了。会多占几百 MB 内存、可能要一两分钟；" +
                // l10n:keep agent repair briefing
                "`free -m` 显示可用内存不到 1 GB 时，先问用户再跑。",
        )
        // l10n:keep agent repair briefing
        appendLine("- 最后请用户在 App 里点「恢复正常模式」。如果正常模式 2 分钟内又崩了，App 会自动回到安全模式，你可以接着查。")
        appendLine()
        // l10n:keep agent repair briefing
        appendLine("## 不要做")
        // l10n:keep agent repair briefing
        appendLine("- 不要往 `$PROFILE` 装插件，不要改救援工具、说明、`/opt/xrk`、`/opt/node`：它们会被重建或覆盖。救援 HOME 内的新对话保留，与原对话分开。")
        // l10n:keep agent repair briefing
        appendLine("- 不要结束 `/tmp/xrk-web.pid` 里的进程（那就是你自己），不要 `pkill node`。")
        // l10n:keep agent repair briefing
        appendLine("- 不要删 `/root/.xrk/sessions`、`/root/.xrk/storages`、`/root/.xrk/.credentials.yaml`。")
        // l10n:keep agent repair briefing
        appendLine("- 诊断文件和日志里可能有密钥，不要整段贴给用户。")
    }

    private fun kindText(f: RunFailure): String = when (f.kind) {
        // l10n:keep agent repair briefing
        FailureKind.LAUNCH_FAILED -> "本机运行环境未能执行 XRK（还未打印登录地址）"
        // l10n:keep agent repair briefing
        FailureKind.STARTUP_FAILED -> "启动失败（还没打印登录地址就退出了）"
        // l10n:keep agent repair briefing
        FailureKind.CRASHED_EARLY -> "启动后很快崩溃（打印登录地址 ${f.upSeconds ?: 0} 秒后退出）"
        // l10n:keep agent repair briefing
        FailureKind.CRASHED_LATE -> "运行中崩溃（打印登录地址 ${f.upSeconds ?: 0} 秒后退出）"
        // l10n:keep agent repair briefing
        FailureKind.KILLED -> "被系统结束（没有 XRK 的致命错误信息，可能是内存不足或省电策略）"
        // l10n:keep agent repair briefing
        FailureKind.NO_SPACE -> "存储空间不足"
    }

    fun formatTime(at: Long, zone: TimeZone = TimeZone.getDefault()): String =
        SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ROOT).apply { timeZone = zone }.format(Date(at))

    /** `yyyyMMdd-HHmmss`, for `.off-` / `.bak-` suffixes. */
    fun stamp(at: Long = System.currentTimeMillis()): String =
        SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).format(Date(at))

    // ── Small file helpers (plain java.io, so this file runs on the JVM too) ────────

    fun guestFile(rootfs: File, guestPath: String): File = File(rootfs, guestPath.removePrefix("/"))

    private fun readIfFile(file: File): String? = try {
        if (file.isFile) file.readText() else null
    } catch (_: Exception) {
        null
    }

    /** A real directory at [dir]: a symlink or file planted there is removed first (never followed). */
    private fun realDir(dir: File): File {
        if (Files.isSymbolicLink(dir.toPath()) || (dir.exists() && !dir.isDirectory)) {
            if (!dir.delete()) throw IOException("could not remove ${dir.path}")
        }
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("could not create ${dir.path}")
        return dir
    }

    /** Writes a sibling temp file and renames it over [file] (replacing, not following, a symlink). */
    fun writeAtomic(file: File, text: String) {
        val tmp = File(file.parentFile, ".${file.name}.xrk-app-${System.nanoTime()}.tmp")
        try {
            tmp.writeText(text)
            if (!tmp.renameTo(file)) throw IOException("could not replace ${file.path}")
        } finally {
            if (tmp.exists()) tmp.delete()
        }
    }

    /** Minimal JSON for the guest-side data files (strings, numbers, booleans, lists, maps). */
    fun json(value: Any?): String = when (value) {
        null -> "null"
        is String -> quote(value)
        is Boolean, is Number -> value.toString()
        is Map<*, *> -> value.entries.joinToString(",", "{", "}") { quote(it.key.toString()) + ":" + json(it.value) }
        is Iterable<*> -> value.joinToString(",", "[", "]") { json(it) }
        else -> quote(value.toString())
    }

    private fun quote(s: String): String = buildString {
        append('"')
        for (c in s) {
            when {
                c == '"' -> append("\\\"")
                c == '\\' -> append("\\\\")
                c == '\n' -> append("\\n")
                c == '\r' -> append("\\r")
                c == '\t' -> append("\\t")
                c < ' ' -> append(String.format(Locale.ROOT, "\\u%04x", c.code))
                else -> append(c)
            }
        }
        append('"')
    }

    /**
     * `bin/xrk-app-plugins`, the agent's repair tool (list / disable / enable / blame / trial).
     * Written without `$` so the raw string needs no escaping; verified on a PC XRK 0.2.1 home.
     */
    // l10n:keep agent repair briefing
    const val PLUGINS_SCRIPT = """#!/usr/bin/env node
// xrk-app safe mode helper. The XRK App rewrites this file on every safe start.
//   list                 plugins of the main profile (web): enabled, third-party, changed since the last good run
//   disable <pkg>...     drop packages from inventory / legacy bundles (files stay; enable undoes it)
//   enable <pkg>...      put installed packages back into the enable list
//   blame                print xrkh dump-config JSON (Host layered config)
//   trial                boot xrkh serve against the original HOME on a spare port
//   export <output.tar>  preserve raw original conversations outside the original HOME
'use strict'
const fs = require('fs')
const path = require('path')
const cp = require('child_process')

const HOME = process.env.XRK_APP_ORIGINAL_HOME || process.env.XRK_HOME || '/root/.xrk'
const SAFE = process.env.XRK_APP_SAFE_DIR || '/var/lib/xrk-app/safe-mode'
const CORE = ['xrk-mobile', 'xrk-mobile-host']
const PLUGINS_DIR = process.env.XRK_PLUGINS_DIR || path.join(HOME, 'plugins')
const INVENTORY = path.join(PLUGINS_DIR, '.xrk-plugins.json')
const DISABLED = path.join(PLUGINS_DIR, '.xrk-plugins-disabled.json')

function readText (file) { try { return fs.readFileSync(file, 'utf8') } catch (e) { return null } }
function readJson (file, fallback) {
  const text = readText(file)
  if (text === null) return fallback
  try { return JSON.parse(text) } catch (e) { return fallback }
}
function out (line) { process.stdout.write(line + '\n') }
function when (ms) {
  const d = new Date(ms)
  const p = function (n) { return String(n).padStart(2, '0') }
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes())
}
function die (line) { process.stderr.write(line + '\n'); process.exit(1) }
function redact (line) { return line.replace(/token=[A-Za-z0-9._~%-]+/g, 'token=***') }
function sleep (ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms) }
function alive (pid) {
  try { process.kill(pid, 0); return true } catch (e) { return e.code === 'EPERM' }
}

function inventoryEntries () {
  const raw = readJson(INVENTORY, null)
  if (Array.isArray(raw)) return raw
  if (raw && Array.isArray(raw.plugins)) return raw.plugins
  return []
}
function disabledSet () {
  const raw = readJson(DISABLED, null)
  if (Array.isArray(raw)) return new Set(raw)
  if (raw && Array.isArray(raw.ids)) return new Set(raw.ids)
  return new Set()
}
function writeDisabled (ids) {
  writeAtomic(DISABLED, JSON.stringify({ ids: ids }, null, 2) + '\n')
}
function entryName (e) {
  return (e && (e.name || e.id || e.package)) || ''
}
function entryVersion (e) {
  return (e && e.version) || ''
}

function withLock (file, fn) {
  const lock = file + '.lock'
  const deadline = Date.now() + 5000
  for (;;) {
    try {
      fs.writeFileSync(lock, process.pid + '\n', { flag: 'wx', mode: 0o600 })
      break
    } catch (e) {
      if (e.code !== 'EEXIST') throw e
      const pid = parseInt(String(readText(lock) || '').trim(), 10)
      if (pid > 0 && !alive(pid)) {
        fs.rmSync(lock, { force: true })
        continue
      }
      if (Date.now() > deadline) die('插件清单正被别的进程修改（锁文件 ' + lock + '），稍后再试')
      sleep(100)
    }
  }
  try { return fn() } finally { fs.rmSync(lock, { force: true }) }
}
function writeAtomic (file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  const tmp = file + '.' + process.pid + '.' + Date.now() + '.tmp'
  fs.writeFileSync(tmp, text)
  fs.renameSync(tmp, file)
}

function lastGood () {
  const lkg = readJson(path.join(SAFE, 'lkg.json'), null)
  return lkg && Array.isArray(lkg.bundles) ? lkg : null
}

function list () {
  const entries = inventoryEntries()
  const disabled = disabledSet()
  const lkg = lastGood()
  out('插件清单（' + INVENTORY + '）：')
  for (const e of entries) {
    const name = entryName(e)
    if (!name) continue
    const enabled = !disabled.has(name)
    const version = entryVersion(e)
    const notes = []
    if (e.kind) notes.push(String(e.kind))
    if (lkg) {
      const was = lkg.bundles.indexOf(name) >= 0
      const lkgVersion = lkg.versions && lkg.versions[name]
      if (enabled && !was) notes.push('上次正常运行后新启用')
      if (enabled && was && lkgVersion && version && lkgVersion !== version) notes.push('上次正常时是 ' + lkgVersion)
      if (!enabled && was) notes.push('上次正常时是启用的')
    }
    out((enabled ? '  [启用] ' : '  [停用] ') + name + (version ? '@' + version : '') + (notes.length ? '  — ' + notes.join('；') : ''))
  }
  if (!entries.length) out('  （空）')
  out(lkg ? '上次正常运行的配置记录于 ' + when(lkg.at) + '。' : '没有上次正常运行的配置记录。')
  out('停用清单：' + DISABLED)
}

function disable (names) {
  if (!names.length) die('用法：xrk-app-plugins disable <包名>...')
  for (const name of names) if (CORE.indexOf(name) >= 0) die(name + ' 是手机壳自带插件，不能停用')
  const installed = new Set(inventoryEntries().map(entryName).filter(Boolean))
  withLock(DISABLED, function () {
    const disabled = disabledSet()
    const newly = []
    for (const name of names) {
      if (!installed.has(name)) { out(name + ' 不在插件清单里'); continue }
      if (disabled.has(name)) { out(name + ' 本来就没有启用'); continue }
      disabled.add(name)
      newly.push(name)
    }
    writeDisabled(Array.from(disabled).sort())
    if (newly.length) out('已停用：' + newly.join('、') + '。文件没有删除，可以用 enable 撤销；重启到正常模式后生效。')
  })
}

function enable (names) {
  if (!names.length) die('用法：xrk-app-plugins enable <包名>...')
  const installed = new Set(inventoryEntries().map(entryName).filter(Boolean))
  withLock(DISABLED, function () {
    const disabled = disabledSet()
    const newly = []
    for (const name of names) {
      if (!installed.has(name)) die(name + ' 不在插件清单里，不能启用（先 xrkh plugin add）')
      if (!disabled.has(name)) { out(name + ' 本来就是启用的'); continue }
      disabled.delete(name)
      newly.push(name)
    }
    writeDisabled(Array.from(disabled).sort())
    if (newly.length) out('已启用：' + newly.join('、') + '。重启到正常模式后生效。')
  })
}

// A raw rescue copy, independent of session parsing and model credentials.
function exportOriginal (args) {
  if (args.length !== 1 || !args[0]) die('用法：xrk-app-plugins export <output.tar>')
  let output
  let fd
  try {
    const home = fs.realpathSync(HOME)
    const requested = path.resolve(args[0])
    output = path.join(fs.realpathSync(path.dirname(requested)), path.basename(requested))
    const relative = path.relative(home, output)
    if (!relative || (relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative))) {
      throw new Error('输出文件必须位于原 XRK_HOME 之外')
    }
    const sessions = fs.lstatSync(path.join(home, 'sessions'))
    if (!sessions.isDirectory()) throw new Error('原 sessions 必须是真实目录，不能是符号链接')
    const entries = ['sessions']
    function optional (name, directory) {
      let info
      try { info = fs.lstatSync(path.join(home, name)) } catch (e) {
        if (e.code === 'ENOENT') return
        throw e
      }
      if (info.isSymbolicLink()) throw new Error('不读取符号链接：' + name)
      if (directory ? !info.isDirectory() : !info.isFile()) throw new Error('不支持的文件类型：' + name)
      entries.push(name)
    }
    optional('attachments', true)
    let storage
    try { storage = fs.lstatSync(path.join(home, 'storages')) } catch (e) {
      if (e.code !== 'ENOENT') throw e
    }
    if (storage) {
      if (!storage.isDirectory()) throw new Error('原 storages 必须是真实目录，不能是符号链接')
      optional('storages/workspace.json', false)
      optional('storages/workspace', true)
    }
    fd = fs.openSync(output, 'wx', 0o600)
    const env = Object.assign({}, process.env)
    delete env.TAR_OPTIONS
    const result = cp.spawnSync('tar', ['--create', '--file', '-', '--directory', home, '--'].concat(entries), {
      env: env, stdio: ['ignore', fd, 'pipe'], encoding: 'utf8'
    })
    if (result.error) throw result.error
    if (result.status !== 0) throw new Error('tar 导出失败：' + (result.stderr || result.signal || result.status))
    fs.fsyncSync(fd)
    fs.closeSync(fd)
    fd = undefined
    out('已导出原始对话备份：' + output)
    out('包含：' + entries.join('、') + '。不含完整工作区、插件、凭据和诊断日志；符号链接不读取目标。')
  } catch (e) {
    if (fd !== undefined) {
      try { fs.closeSync(fd) } catch (_) {}
      try { fs.unlinkSync(output) } catch (_) {}
    }
    die('导出失败：' + e.message)
  }
}

function cleanEnv () {
  const env = Object.assign({}, process.env)
  delete env.XRK_AGENTS_HOME
  delete env.XRK_APP_SAFE_MODE
  delete env.XRK_APP_ORIGINAL_HOME
  env.XRK_HOME = HOME
  return env
}
function blame (ids) {
  const r = cp.spawnSync('xrkh', ['dump-config'], {
    encoding: 'utf8', env: cleanEnv(), maxBuffer: 64 * 1024 * 1024
  })
  if (r.error) die('运行 xrkh 失败：' + r.error.message)
  if (r.status !== 0) {
    out('xrkh dump-config 失败（退出码 ' + r.status + '）：')
    out(redact(String(r.stderr || r.stdout || '').split('\n').slice(-40).join('\n')))
    process.exit(1)
  }
  const text = String(r.stdout || '')
  if (ids.length) {
    for (const id of ids) {
      const hit = text.split('\n').filter(function (line) { return line.indexOf(id) >= 0 }).slice(0, 20)
      out(hit.length ? ('匹配 ' + id + '：\n' + hit.join('\n')) : (id + '：dump-config 输出里没有这一段'))
    }
    return
  }
  out('xrkh dump-config（前 80 行；完整 JSON 请直接跑 xrkh dump-config）：')
  out(text.split('\n').slice(0, 80).join('\n'))
}

function trial (args) {
  const hold = parseInt(process.env.TRIAL_HOLD || '30', 10)
  const limit = parseInt(process.env.TRIAL_LIMIT || '240', 10)
  const started = Date.now()
  const tail = []
  let upAt = 0
  let passed = false
  let finished = false
  const child = cp.spawn('xrkh', ['serve', '--host', '127.0.0.1', '--port', '0'], {
    env: cleanEnv(), stdio: ['ignore', 'pipe', 'pipe']
  })
  const seconds = function (ms) { return Math.round(ms / 1000) }
  const onData = function (chunk) {
    for (const line of String(chunk).split('\n')) {
      if (!line) continue
      tail.push(redact(line))
      if (tail.length > 60) tail.shift()
      if (!upAt && (/listening|http:\/\/127\.0\.0\.1|Host ready|serve /i.test(line) || line.indexOf('token=') >= 0)) upAt = Date.now()
    }
  }
  child.stdout.on('data', onData)
  child.stderr.on('data', onData)
  const finish = function (code, text, showTail) {
    if (finished) return
    finished = true
    clearInterval(timer)
    out(text)
    if (showTail) out(tail.slice(-40).join('\n'))
    else {
      const warnings = tail.filter(function (l) { return /warning|skipping/i.test(l) })
      if (warnings.length) out(warnings.slice(0, 20).join('\n'))
    }
    process.exit(code)
  }
  child.on('error', function (e) { finish(1, 'FAIL: 无法运行 xrkh：' + e.message, false) })
  child.on('exit', function (code, signal) {
    if (passed) return finish(0, 'PASS: xrkh serve 在 ' + seconds(upAt - started) + ' 秒内启动，并稳定运行了 ' + hold + ' 秒', false)
    finish(1, 'FAIL: xrkh serve 在 ' + seconds(Date.now() - started) + ' 秒时退出（' + (signal ? '信号 ' + signal : '退出码 ' + code) + '）' +
      (upAt ? '，它在 ' + seconds(upAt - started) + ' 秒时已经打印了就绪信息' : '，没打印就绪信息') + '。最后的输出：', true)
  })
  const stop = function () {
    child.kill('SIGTERM')
    setTimeout(function () { try { child.kill('SIGKILL') } catch (e) {} }, 5000).unref()
  }
  const timer = setInterval(function () {
    if (upAt && Date.now() - upAt >= hold * 1000 && !passed) { passed = true; stop() }
    if (!upAt && Date.now() - started >= limit * 1000 && !finished) {
      child.kill('SIGKILL')
      finish(1, 'FAIL: xrkh serve 在 ' + limit + ' 秒内没有打印就绪信息（可能卡住了）。最后的输出：', true)
    }
  }, 500)
}

const argv = process.argv.slice(2)
const command = argv[0]
const rest = argv.slice(1)
if (command === 'list') list()
else if (command === 'disable') disable(rest)
else if (command === 'enable') enable(rest)
else if (command === 'blame') blame(rest)
else if (command === 'trial') trial(rest)
else if (command === 'export') exportOriginal(rest)
else {
  out('用法：xrk-app-plugins list | disable <包名>... | enable <包名>... | blame [配置行 id...] | trial [profile] | export <output.tar>')
  process.exit(command ? 1 : 0)
}
"""
}
