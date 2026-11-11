package com.xrkseek.harness.runtime

import org.junit.Assert.*
import org.junit.Test

class LkgPlanTest {
    @Test fun restoresAvailableSameVersionBundlesWithoutDowngrading() {
        val good = ProfileSnapshot(
            listOf("core", "same", "upgraded", "removed"),
            setOf("same", "upgraded", "removed"),
            mapOf("same" to "1", "upgraded" to "1", "removed" to "1"),
            null,
        )
        val now = ProfileSnapshot(
            listOf("core", "upgraded", "new"),
            setOf("same", "upgraded", "new"),
            mapOf("same" to "1", "upgraded" to "2", "new" to "1"),
            null,
        )
        val plan = LkgPlan.of(good, now)
        assertEquals(listOf("core", "same"), plan.target)
        assertEquals(listOf("upgraded", "new"), plan.disable)
        assertEquals(listOf("same"), plan.enable)
        assertEquals(listOf("upgraded"), plan.changed)
        assertFalse(plan.patchChanged)
        assertFalse(plan.isEmpty)
        assertTrue(LkgPlan.of(good, good).isEmpty)
    }
}
