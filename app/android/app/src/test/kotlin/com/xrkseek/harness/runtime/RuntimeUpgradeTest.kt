package com.xrkseek.harness.runtime

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RuntimeUpgradeTest {
    private fun snap(
        installed: String? = "r17",
        bundled: String = "r17",
        bundledSha: String? = "aaa",
        stampedApp: Long = 16,
        currentApp: Long = 17,
        stampedSha: String? = "aaa",
        carry: Boolean = false,
        staging: Boolean = false,
        retired: Boolean = false,
        essentials: Boolean = true,
        home: Boolean = true,
    ) = RuntimeUpgrade.Snapshot(
        installedVersion = installed,
        bundledVersion = bundled,
        bundledSha = bundledSha,
        stampedAppCode = stampedApp,
        currentAppCode = currentApp,
        stampedSha = stampedSha,
        carryExists = carry,
        stagingExists = staging,
        retiredExists = retired,
        essentialsOk = essentials,
        homeExists = home,
    )

    @Test
    fun `16 to 17 same runtime soft-heals and keeps home`() {
        val p = RuntimeUpgrade.plan(snap())
        assertFalse(p.needInstall)
        assertTrue(p.softHeal)
        assertTrue(p.clearHostFailureCard)
        assertTrue(p.stampAppCode)
        assertFalse(p.prepareCarry)
        assertFalse(p.clearVersionMarker)
    }

    @Test
    fun `17 to 17 same stamp is ready`() {
        val p = RuntimeUpgrade.plan(snap(stampedApp = 17, currentApp = 17))
        assertFalse(p.needInstall)
        assertFalse(p.softHeal)
        assertFalse(p.clearHostFailureCard)
        assertFalse(p.stampAppCode)
    }

    @Test
    fun `interrupted carry forces reinstall`() {
        val p = RuntimeUpgrade.plan(snap(carry = true, stampedApp = 17, currentApp = 17))
        assertTrue(p.needInstall)
        assertTrue(p.clearVersionMarker)
        assertTrue(p.clearHostFailureCard)
    }

    @Test
    fun `runtime version change needs install`() {
        val p = RuntimeUpgrade.plan(snap(installed = "r15", bundled = "r17", stampedApp = 16, currentApp = 17))
        assertTrue(p.needInstall)
        assertFalse(p.softHeal)
    }

    @Test
    fun `essentials missing forces reinstall with carry`() {
        val p = RuntimeUpgrade.plan(snap(essentials = false))
        assertTrue(p.needInstall)
        assertTrue(p.prepareCarry)
        assertTrue(p.clearVersionMarker)
    }

    @Test
    fun `sha drift forces reinstall with carry`() {
        val p = RuntimeUpgrade.plan(snap(stampedSha = "bbb", bundledSha = "aaa"))
        assertTrue(p.needInstall)
        assertTrue(p.prepareCarry)
    }

    @Test
    fun `softHealGuest keeps xrk home`() {
        val root = Files.createTempDirectory("soft-heal").toFile()
        try {
            File(root, "tmp").mkdirs()
            File(root, "tmp/xrk-web.pid").writeText("1")
            File(root, "root/.xrk").mkdirs()
            File(root, "root/.xrk/settings.yaml").writeText("keep")
            File(root, "opt/dsh-app/auth").mkdirs()
            File(root, "opt/dsh-app/auth/auth.patch.yml").writeText("x")
            val notes = RuntimeUpgrade.softHealGuest(root)
            assertTrue(notes.any { it.contains("xrk-web.pid") })
            assertFalse(File(root, "tmp/xrk-web.pid").exists())
            assertFalse(File(root, "opt/dsh-app/auth/auth.patch.yml").exists())
            assertEquals("keep", File(root, "root/.xrk/settings.yaml").readText())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `prepareCarry moves home`() {
        val base = Files.createTempDirectory("carry").toFile()
        try {
            File(base, "rootfs/root/.xrk").mkdirs()
            File(base, "rootfs/root/.xrk/a").writeText("1")
            assertTrue(RuntimeUpgrade.prepareCarry(base))
            assertTrue(File(base, "home.carry/.xrk/a").isFile)
            assertFalse(File(base, "rootfs/root").exists())
        } finally {
            base.deleteRecursively()
        }
    }

    @Test
    fun `softHealGuest moves bootstrap env aside`() {
        val root = Files.createTempDirectory("soft-heal-env").toFile()
        try {
            File(root, "root/.xrk").mkdirs()
            File(root, "root/.xrk/.env").writeText("PATH=/bad\nHTTPS_PROXY=http://127.0.0.1:1\n")
            File(root, "root/.xrk/settings.yaml").writeText("keep")
            val notes = RuntimeUpgrade.softHealGuest(root)
            assertFalse(File(root, "root/.xrk/.env").exists())
            assertTrue(notes.any { it.startsWith("moved /root/.xrk/.env") })
            assertEquals("keep", File(root, "root/.xrk/settings.yaml").readText())
        } finally {
            root.deleteRecursively()
        }
    }
}