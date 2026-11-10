package com.xrkseek.harness.runtime

/**
 * User-visible runtime / installer log prefix.
 * Legacy lines may still say `[dsh-app]`; the Flutter LogView highlights both.
 */
object AppLog {
    const val PREFIX = "[xrkh-app]"

    fun line(message: String): String = "$PREFIX $message"
}
