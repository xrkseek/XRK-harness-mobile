package com.xrkseek.harness.phone

import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class PhoneCallerGuestTest {
    @Test fun writeFilesDropsLegacyPatchYamlAndKeepsRelay() {
        val root = Files.createTempDirectory("phone-caller-guest").toFile()
        try {
            val legacy = PhoneGuest.guestFile(root, "${PhoneGuest.GUEST_DIR}/phone.patch.yml")
            legacy.parentFile.mkdirs()
            legacy.writeText("xrkGoPhoneCaller: true\n")
            PhoneGuest.writeFiles(root)
            assertFalse(legacy.exists())
            assertEquals(PhoneGuest.RELAY_JS, PhoneGuest.guestFile(root, PhoneGuest.RELAY).readText())
        } finally {
            root.deleteRecursively()
        }
    }
}
