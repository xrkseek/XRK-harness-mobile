package io.github.ccch1mneyyy.dsh_app.phone

import android.content.Context
import io.github.ccch1mneyyy.dsh_app.phone.a11y.OverlayPrefs
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

/**
 * Loopback HTTP the guest `xrk-mobile` plugins call (`XRK_MOBILE_API` + token).
 * Tools: `POST /v1/phone/<tool>`. Settings (Host UI): `/v1/phone-settings/...`.
 * Never binds a public address.
 *
 * Body length is Content-Length **bytes** (UTF-8). Reading that many *chars*
 * via BufferedReader hangs on CJK payloads until soTimeout — Chinese
 * `phone_open` / `phone_apps` looked like “timeout”, ASCII worked.
 */
class MobileApi private constructor(private val app: Context) {
    @Volatile var token: String = ""
        private set
    @Volatile var port: Int = 0
        private set

    private val server = AtomicReference<ServerSocket?>(null)
    private val steerInbox = PhoneSteerInbox()

    fun guestEnv(): Map<String, String> {
        val p = port
        val t = token
        if (p <= 0 || t.isEmpty()) return emptyMap()
        return mapOf(
            "XRK_MOBILE_API" to "http://127.0.0.1:$p",
            "XRK_MOBILE_TOKEN" to t,
        )
    }

    /** Overlay 插话 → Host steer; drained by the guest host plugin / client. */
    fun enqueueSteer(text: String) = steerInbox.enqueue(text)

    fun drainSteers(limit: Int = 8): List<String> = steerInbox.drain(limit)

    @Synchronized
    fun ensureStarted() {
        val live = server.get()
        if (live != null && !live.isClosed) return
        token = hex(24)
        val sock = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        port = sock.localPort
        server.set(sock)
        thread(name = "xrk-mobile-api", isDaemon = true) { acceptLoop(sock) }
    }

    fun stop() {
        runCatching { server.getAndSet(null)?.close() }
        port = 0
        token = ""
        steerInbox.clear()
    }

    private fun acceptLoop(sock: ServerSocket) {
        while (!sock.isClosed) {
            val client = try {
                sock.accept()
            } catch (_: Exception) {
                break
            }
            thread(name = "xrk-mobile-api-req", isDaemon = true) { handle(client) }
        }
    }

    private fun handle(client: Socket) {
        client.soTimeout = 30_000
        try {
            val raw = client.getInputStream()
            val headBytes = readHttpHeaders(raw) ?: return reply(client, 400, "empty")
            val headText = String(headBytes, Charsets.UTF_8)
            val lines = headText.split("\r\n", "\n")
            if (lines.isEmpty()) return reply(client, 400, "empty")
            val request = lines[0]
            val parts = request.split(' ')
            if (parts.size < 2) return reply(client, 400, "bad request")
            val method = parts[0]
            val path = parts[1].substringBefore('?')
            var contentLength = 0
            var auth = ""
            var phoneCallerHeader = ""
            for (i in 1 until lines.size) {
                val line = lines[i]
                if (line.isEmpty()) break
                val idx = line.indexOf(':')
                if (idx <= 0) continue
                val key = line.substring(0, idx).trim().lowercase()
                val value = line.substring(idx + 1).trim()
                when (key) {
                    "content-length" -> contentLength = value.toIntOrNull()?.coerceIn(0, MAX_BODY) ?: 0
                    "authorization" -> auth = value
                    "x-xrk-phone-caller" -> phoneCallerHeader = value
                }
            }
            val body = if (contentLength > 0) {
                val buf = ByteArray(contentLength)
                var n = 0
                while (n < contentLength) {
                    val r = raw.read(buf, n, contentLength - n)
                    if (r < 0) break
                    n += r
                }
                String(buf, 0, n, Charsets.UTF_8)
            } else {
                ""
            }
            val (code, text, json) = dispatch(method, path, auth, body, phoneCallerHeader)
            reply(client, code, text, json)
        } catch (e: Exception) {
            runCatching { reply(client, 500, e.message ?: "error") }
        } finally {
            runCatching { client.close() }
        }
    }

    /** Read until CRLFCRLF (or LFLF). Returns header bytes excluding the blank line terminator. */
    private fun readHttpHeaders(raw: java.io.InputStream): ByteArray? {
        val out = ByteArrayOutputStream(512)
        var state = 0 // 0 none, 1 \r, 2 \r\n, 3 \r\n\r, or LF variants 10/20
        while (true) {
            val b = raw.read()
            if (b < 0) return if (out.size() == 0) null else out.toByteArray()
            out.write(b)
            if (out.size() > 64 * 1024) return out.toByteArray()
            when (state) {
                0 -> state = when (b) {
                    '\r'.code -> 1
                    '\n'.code -> 10
                    else -> 0
                }
                1 -> state = if (b == '\n'.code) 2 else if (b == '\r'.code) 1 else 0
                2 -> state = if (b == '\r'.code) 3 else if (b == '\n'.code) {
                    // \n\n
                    return out.toByteArray().copyOf(out.size() - 2)
                } else 0
                3 -> if (b == '\n'.code) {
                    return out.toByteArray().copyOf(out.size() - 4)
                } else {
                    state = if (b == '\r'.code) 1 else 0
                }
                10 -> if (b == '\n'.code) {
                    return out.toByteArray().copyOf(out.size() - 2)
                } else {
                    state = if (b == '\r'.code) 1 else 0
                }
            }
        }
    }

    private data class Outcome(val code: Int, val text: String, val json: Boolean = false)

    private fun dispatch(
        method: String,
        path: String,
        auth: String,
        body: String,
        phoneCallerHeader: String = "",
    ): Outcome {
        if (auth != "Bearer $token") return Outcome(401, "unauthorized")
        if (method == "GET" && path == "/v1/health") return Outcome(200, "ok")
        if (method == "POST" && path == "/v1/open") {
            val map = runCatching { Json.parse(body) as? Map<*, *> }.getOrNull()
            val guest = map?.get("path") as? String ?: return Outcome(400, "path required")
            return if (PhoneControl.get(app).openGuestFile(guest)) Outcome(200, "opened")
            else Outcome(404, "not found")
        }
        if (path.startsWith("/v1/phone-settings")) {
            return dispatchSettings(method, path, body)
        }
        if (method == "POST" && path.startsWith("/v1/phone/")) {
            val name = path.removePrefix("/v1/phone/")
            if (name !in PhoneToolCatalog.names) return Outcome(404, "unknown tool $name")
            // Host header only — never trust caller fields forged into tool args.
            val caller = when {
                phoneCallerHeader.isBlank() -> null
                else -> parsePhoneCallerHeader(phoneCallerHeader)
                    ?: return Outcome(400, "invalid phone caller header")
            }
            val raw = runCatching { Json.parse(if (body.isBlank()) "{}" else body) }.getOrNull()
            val args = (raw as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value } ?: emptyMap()
            val out = PhoneControl.get(app).invokeTool(name, args, caller)
            return Outcome(if (out.isError) 409 else 200, out.text)
        }
        return Outcome(404, "not found")
    }

    /** Host-only attribution; blank → legacy null admit (compat with old guest plugins). */
    private fun parsePhoneCallerHeader(raw: String): PhoneCaller? {
        if (raw.isBlank()) return null
        val parsed = runCatching { Json.parse(raw) }.getOrNull() ?: return null
        return PhoneCaller.parse(parsed)
    }

    private fun dispatchSettings(method: String, path: String, body: String): Outcome {
        val control = PhoneControl.get(app)
        fun json(value: Any?): Outcome = Outcome(200, Json.write(value), json = true)
        fun parseBody(): Map<*, *>? =
            runCatching { Json.parse(if (body.isBlank()) "{}" else body) as? Map<*, *> }.getOrNull()

        when {
            method == "GET" && path == "/v1/phone-settings" -> {
                val status = control.status()
                val policies = control.policiesMap()
                val overlay = OverlayPrefs.read(app).toMap()
                return json(
                    linkedMapOf(
                        "ok" to true,
                        "status" to status,
                        "policies" to policies,
                        "overlay" to overlay,
                    ),
                )
            }
            method == "GET" && path == "/v1/phone-settings/steer-pending" -> {
                return json(linkedMapOf("ok" to true, "items" to drainSteers()))
            }
            method == "POST" && path == "/v1/phone-settings/steer" -> {
                val map = parseBody()
                val text = (map?.get("text") as? String)?.trim().orEmpty()
                if (text.isEmpty()) return Outcome(400, "text required")
                enqueueSteer(text)
                // Keep tool-drain compatibility for in-flight phone_* calls.
                runCatching {
                    PhoneControl.get(app).shownControls()?.interject(text)
                }
                return json(linkedMapOf("ok" to true))
            }
            // Exact host turn/end (XRK sessionId + turnId). Same semantics as MCP phone-run-end.
            method == "POST" && path == "/v1/phone-settings/run-end" -> {
                val map = parseBody()
                val sessionId = PhoneCaller.identifier(map?.get("sessionId"))
                    ?: return Outcome(400, "sessionId required")
                val runId = PhoneCaller.identifier(map?.get("runId"))
                    ?: return Outcome(400, "runId required")
                val completion = (map?.get("completion") as? String)?.takeIf {
                    it in setOf("completed", "other", "unknown")
                } ?: "unknown"
                val ok = control.endRun(sessionId, runId, completion)
                return if (ok) json(linkedMapOf("ok" to true))
                else Outcome(409, Json.write(linkedMapOf("ok" to false, "error" to "capacity")), json = true)
            }
            method == "POST" && path == "/v1/phone-settings/enabled" -> {
                val map = parseBody()
                val enabled = map?.get("enabled") as? Boolean
                    ?: return Outcome(400, "enabled required")
                if (map["disclosureAccepted"] == true) control.acceptDisclosure()
                if (enabled && !control.isDisclosureAccepted()) {
                    return Outcome(
                        403,
                        Json.write(
                            linkedMapOf(
                                "ok" to false,
                                "error" to "disclosure_required",
                                "disclosureRequired" to true,
                                "disclosureAccepted" to false,
                                "enabled" to control.isEnabled(),
                            ),
                        ),
                        json = true,
                    )
                }
                val out = control.applyEnabledFromHost(enabled)
                if (!out.ok && out.error == "safe_mode") {
                    return Outcome(
                        409,
                        Json.write(
                            linkedMapOf(
                                "ok" to false,
                                "error" to "safe_mode",
                                "enabled" to out.enabled,
                                "needsRestart" to false,
                                "disclosureAccepted" to out.disclosureAccepted,
                            ),
                        ),
                        json = true,
                    )
                }
                if (!out.ok && out.error == "disclosure_required") {
                    return Outcome(
                        403,
                        Json.write(
                            linkedMapOf(
                                "ok" to false,
                                "error" to "disclosure_required",
                                "disclosureRequired" to true,
                                "disclosureAccepted" to false,
                                "enabled" to out.enabled,
                                "needsRestart" to false,
                            ),
                        ),
                        json = true,
                    )
                }
                val bodyMap = linkedMapOf<String, Any?>(
                    "ok" to out.ok,
                    "enabled" to out.enabled,
                    "needsRestart" to out.needsRestart,
                    "disclosureAccepted" to out.disclosureAccepted,
                )
                if (out.error != null) bodyMap["error"] = out.error
                return json(bodyMap)
            }
            method == "POST" && path == "/v1/phone-settings/policies" -> {
                val map = parseBody()
                val ok = control.setPolicies(map)
                return if (ok) json(linkedMapOf("ok" to true, "policies" to control.policiesMap()))
                else Outcome(409, "busy or invalid policies")
            }
            method == "POST" && path == "/v1/phone-settings/overlay" -> {
                val prefs = OverlayPrefs.write(app, parseBody())
                return json(linkedMapOf("ok" to true, "overlay" to prefs.toMap()))
            }
            method == "POST" && path == "/v1/phone-settings/open-accessibility" -> {
                return try {
                    app.startActivity(control.accessibilitySettingsIntent())
                    json(linkedMapOf("ok" to true))
                } catch (e: Exception) {
                    Outcome(500, e.message ?: "could not open accessibility settings")
                }
            }
            method == "POST" && path == "/v1/phone-settings/open-app-details" -> {
                return try {
                    app.startActivity(control.appDetailsIntent())
                    json(linkedMapOf("ok" to true))
                } catch (e: Exception) {
                    Outcome(500, e.message ?: "could not open app details")
                }
            }
            // Person's own on-device screen check (never sent to a model).
            method == "POST" && path == "/v1/phone-settings/test-screen" -> {
                return json(control.testScreen())
            }
            // One-tap WRITE_SECURE_SETTINGS for a11y auto-restore (Shizuku / self-ADB).
            method == "POST" && path == "/v1/phone-settings/grant-secure-settings" -> {
                return json(control.grantSecureSettings { true })
            }
            method == "POST" && path == "/v1/phone-settings/skill-prompt" -> {
                val map = parseBody()
                val enabled = map?.get("enabled") as? Boolean
                    ?: return Outcome(400, "enabled required")
                control.setSkillSavePrompt(enabled)
                return json(linkedMapOf("ok" to true, "skills" to control.status()["skills"]))
            }
            method == "POST" && path == "/v1/phone-settings/ack-interruption" -> {
                val map = parseBody()
                val token = (map?.get("batchToken") as? String)?.trim().orEmpty()
                val ok = if (token.isEmpty()) control.retryTaskInterruptionStorage()
                else control.acknowledgeTaskInterruption(token)
                return if (ok) json(linkedMapOf("ok" to true, "status" to control.status()))
                else Outcome(409, Json.write(linkedMapOf("ok" to false, "error" to "busy")), json = true)
            }
            else -> return Outcome(404, "not found")
        }
    }

    private fun reply(client: Socket, code: Int, text: String, json: Boolean = false) {
        val bytes = text.toByteArray(Charsets.UTF_8)
        val status = when (code) {
            200 -> "OK"
            400 -> "Bad Request"
            401 -> "Unauthorized"
            403 -> "Forbidden"
            404 -> "Not Found"
            409 -> "Conflict"
            else -> "Error"
        }
        val type = if (json) "application/json; charset=utf-8" else "text/plain; charset=utf-8"
        val out = client.getOutputStream()
        val head =
            "HTTP/1.1 $code $status\r\n" +
                "Content-Type: $type\r\n" +
                "Content-Length: ${bytes.size}\r\n" +
                "Connection: close\r\n\r\n"
        out.write(head.toByteArray(Charsets.UTF_8))
        out.write(bytes)
        out.flush()
    }

    companion object {
        private const val MAX_BODY = 1_000_000
        @Volatile private var instance: MobileApi? = null

        fun get(app: Context): MobileApi {
            instance?.let { return it }
            return synchronized(this) {
                instance ?: MobileApi(app.applicationContext).also { instance = it }
            }
        }

        private fun hex(n: Int): String {
            val bytes = ByteArray(n)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }
}
