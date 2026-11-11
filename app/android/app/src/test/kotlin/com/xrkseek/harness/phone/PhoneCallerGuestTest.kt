package com.xrkseek.harness.phone

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class PhoneCallerGuestTest {
    @Test fun onlyInstalledCallerPatchEnablesManagedStdioOptIn() {
        val root = Files.createTempDirectory("phone-caller-guest").toFile()
        try {
            val info = File(root, "etc/xrk-app/runtime.json")
            assertEquals(PhoneGuest.PATCH_YAML, PhoneGuest.patchYaml(root))
            info.parentFile.mkdirs()
            for (text in listOf("not json", "{}", "{\"enginePatches\":[\"unrelated.diff\"]}")) {
                info.writeText(text)
                assertEquals(PhoneGuest.PATCH_YAML, PhoneGuest.patchYaml(root))
            }
            info.writeText(Json.write(mapOf("enginePatches" to listOf(PhoneGuest.CALLER_PATCH))))
            PhoneGuest.writeFiles(root)
            val overlay = PhoneGuest.guestFile(root, PhoneGuest.PATCH).readText()
            assertEquals(PhoneGuest.PATCH_YAML + "        xrkGoPhoneCaller: true\n", overlay)
            assertEquals(PhoneGuest.RELAY_JS, PhoneGuest.guestFile(root, PhoneGuest.RELAY).readText())
        } finally {
            root.deleteRecursively()
        }
    }
}
