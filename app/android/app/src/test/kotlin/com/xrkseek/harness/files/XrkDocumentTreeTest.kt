package com.xrkseek.harness.files

import java.io.File
import java.io.FileNotFoundException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class XrkDocumentTreeTest {
    @get:Rule val temp = TemporaryFolder()

    private fun tree(withPhone: Boolean = true): Triple<XrkDocumentTree, File, File?> {
        val guest = temp.newFolder("root")
        val xrk = File(guest, ".xrk").apply { mkdirs() }
        File(xrk, "inbox").mkdirs()
        File(xrk, "sessions").mkdirs()
        File(guest, "workspace").mkdirs()
        File(guest, ".cache").mkdirs()
        val phone = if (withPhone) {
            temp.newFolder("phone").also { File(it, "Download").mkdirs() }
        } else null
        return Triple(XrkDocumentTree(guest, xrk, phone), guest, phone)
    }

    @Test
    fun `guest root resolves and lists product dots plus workspace`() {
        val (t, guest, _) = tree()
        assertEquals(guest.canonicalFile, t.resolve("guest").canonicalFile)
        val names = t.listChildren(guest).map { it.name }.toSet()
        assertTrue(names.contains(".xrk"))
        assertTrue(names.contains("workspace"))
        assertFalse(names.contains(".cache"))
    }

    @Test
    fun `legacy home and inbox ids stay under xrk`() {
        val (t, guest, _) = tree()
        val xrk = File(guest, ".xrk")
        assertEquals(xrk.canonicalFile, t.resolve("home").canonicalFile)
        assertEquals(File(xrk, "inbox").canonicalFile, t.resolve("inbox").canonicalFile)
        assertEquals(File(xrk, "sessions").canonicalFile, t.resolve("home/sessions").canonicalFile)
        assertEquals("home", t.docIdFor(xrk))
        assertEquals("home/sessions", t.docIdFor(File(xrk, "sessions")))
        assertEquals("inbox", t.docIdFor(File(xrk, "inbox")))
    }

    @Test
    fun `path escape via dot-dot is rejected`() {
        val (t, _, _) = tree()
        try {
            t.resolve("home/../workspace")
            fail("expected escape")
        } catch (e: FileNotFoundException) {
            assertTrue(e.message!!.contains("outside"))
        }
    }

    @Test
    fun `phone tree mirrors sdcard when present`() {
        val (t, _, phone) = tree(withPhone = true)
        assertEquals(phone!!.canonicalFile, t.resolve("phone").canonicalFile)
        val download = File(phone, "Download")
        assertEquals("phone/Download", t.docIdFor(download))
        assertEquals(download.canonicalFile, t.resolve("phone/Download").canonicalFile)
        assertTrue(t.isChildDocument("phone", "phone/Download"))
    }

    @Test
    fun `phone ids fail closed when phone root absent`() {
        val (t, _, _) = tree(withPhone = false)
        try {
            t.resolve("phone")
            fail("expected missing phone")
        } catch (e: FileNotFoundException) {
            assertTrue(e.message!!.contains("phone"))
        }
    }

    @Test
    fun `guest treats home aliases as children`() {
        val (t, _, _) = tree()
        assertTrue(t.isChildDocument("guest", "home"))
        assertTrue(t.isChildDocument("guest", "home/sessions"))
        assertTrue(t.isChildDocument("guest", "inbox"))
        assertTrue(t.isProtectedRoot("guest"))
        assertTrue(t.isProtectedRoot("home"))
        assertTrue(t.isProtectedRoot("phone"))
        assertFalse(t.isProtectedRoot("home/sessions"))
    }
}
