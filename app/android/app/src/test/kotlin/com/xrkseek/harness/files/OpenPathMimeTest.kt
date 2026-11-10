package com.xrkseek.harness.files

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OpenPathMimeTest {
    @Test
    fun officeOpenXmlExtensionsResolve() {
        assertEquals(
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            OpenPathMime.fromExtension("pptx"),
        )
        assertEquals(
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            OpenPathMime.fromExtension("DOCX"),
        )
        assertEquals(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            OpenPathMime.fromExtension(".xlsx"),
        )
        assertEquals("application/pdf", OpenPathMime.fromExtension("pdf"))
    }

    @Test
    fun unknownExtensionIsNullFromTable() {
        assertNull(OpenPathMime.fromExtension("weirdbin"))
    }
}
