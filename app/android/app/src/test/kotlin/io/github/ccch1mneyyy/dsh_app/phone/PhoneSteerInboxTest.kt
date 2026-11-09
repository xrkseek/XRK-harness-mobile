package io.github.ccch1mneyyy.dsh_app.phone

import org.junit.Assert.*
import org.junit.Test

class PhoneSteerInboxTest {
    @Test fun dropsBlankAndTrims() {
        val inbox = PhoneSteerInbox()
        inbox.enqueue("  ")
        inbox.enqueue("\n")
        inbox.enqueue("  hello  ")
        assertEquals(listOf("hello"), inbox.drain())
    }

    @Test fun capsQueueAndDrainsFifo() {
        val inbox = PhoneSteerInbox(max = 3)
        inbox.enqueue("a")
        inbox.enqueue("b")
        inbox.enqueue("c")
        inbox.enqueue("d")
        assertEquals(3, inbox.size())
        assertEquals(listOf("b", "c", "d"), inbox.drain(limit = 8))
        assertEquals(0, inbox.size())
        assertEquals(emptyList<String>(), inbox.drain())
    }

    @Test fun drainRespectsLimit() {
        val inbox = PhoneSteerInbox()
        inbox.enqueue("1")
        inbox.enqueue("2")
        inbox.enqueue("3")
        assertEquals(listOf("1", "2"), inbox.drain(limit = 2))
        assertEquals(listOf("3"), inbox.drain())
    }
}
