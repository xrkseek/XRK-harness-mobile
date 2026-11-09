package io.github.ccch1mneyyy.dsh_app.phone

import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Overlay 插话 texts waiting for the Host client to drain via
 * `GET /v1/phone-settings/steer-pending` → `sessions.prompt(mode: steer)`.
 */
internal class PhoneSteerInbox(private val max: Int = 16) {
    private val queue = ConcurrentLinkedQueue<String>()

    fun enqueue(text: String) {
        val t = text.trim()
        if (t.isEmpty()) return
        queue.offer(t)
        while (queue.size > max) queue.poll()
    }

    fun drain(limit: Int = 8): List<String> {
        val out = ArrayList<String>(limit.coerceAtMost(max))
        while (out.size < limit) {
            val next = queue.poll() ?: break
            out += next
        }
        return out
    }

    fun clear() {
        queue.clear()
    }

    fun size(): Int = queue.size
}
