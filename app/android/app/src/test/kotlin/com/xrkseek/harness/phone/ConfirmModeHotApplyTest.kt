package com.xrkseek.harness.phone

import org.junit.Assert.*
import org.junit.Test

/**
 * 确认方式 tightened mid-task must revoke session grants so ASK / TASK apply
 * on the next action (prefs are already live via policies()).
 */
class ConfirmModeHotApplyTest {
    private fun target(label: String = "打开") =
        TargetInfo("s1", 1, "按钮", label, "example.app", "Example", false, false, false)

    @Test fun stricterThanRanksAlwaysTaskAsk() {
        assertTrue(ConfirmMode.ASK.stricterThan(ConfirmMode.TASK))
        assertTrue(ConfirmMode.ASK.stricterThan(ConfirmMode.ALWAYS))
        assertTrue(ConfirmMode.TASK.stricterThan(ConfirmMode.ALWAYS))
        assertFalse(ConfirmMode.ALWAYS.stricterThan(ConfirmMode.ASK))
        assertFalse(ConfirmMode.TASK.stricterThan(ConfirmMode.ASK))
        assertFalse(ConfirmMode.ASK.stricterThan(ConfirmMode.ASK))
    }

    @Test fun alwaysToAskRevokesApprovalsSoFirstInAppAsksAgain() {
        val tasks = PhoneTasks().apply {
            begin()
            approve("example.app")
            waive()
        }
        var mode = ConfirmMode.ALWAYS
        val gate = SafetyGate({ PhonePolicies(confirmMode = mode) }, tasks, { null })
        assertSame(SafetyGate.Verdict.Allow, gate.checkWrite(WriteKind.TAP, target(), "example.app", null))

        mode = ConfirmMode.ASK
        tasks.revokeSessionGrants(clearWaiver = true, clearApprovals = true)
        assertFalse(tasks.isWaived)
        assertFalse(tasks.isApproved("example.app"))
        val again = gate.checkWrite(WriteKind.TAP, target(), "example.app", null) as SafetyGate.Verdict.Confirm
        assertEquals("first-in-app", again.reason)
    }

    @Test fun taskToAskDropsWaiverWithoutLeavingAlwaysPath() {
        val tasks = PhoneTasks().apply {
            begin()
            waive()
        }
        var mode = ConfirmMode.TASK
        val gate = SafetyGate({ PhonePolicies(confirmMode = mode) }, tasks, { null })
        assertTrue(gate.waived())
        assertSame(SafetyGate.Verdict.Allow, gate.checkWrite(WriteKind.TAP, target(), "example.app", null))

        mode = ConfirmMode.ASK
        tasks.revokeSessionGrants(clearWaiver = true, clearApprovals = true)
        assertFalse(gate.waived())
        assertTrue(gate.checkWrite(WriteKind.TAP, target(), "example.app", null) is SafetyGate.Verdict.Confirm)
    }

    @Test fun looseningConfirmModeDoesNotNeedRevoke() {
        val tasks = PhoneTasks().apply {
            begin()
            approve("example.app")
        }
        assertFalse(ConfirmMode.ALWAYS.stricterThan(ConfirmMode.ASK))
        // Approvals stay; ALWAYS skips asks via waived() without needing revoke.
        val gate = SafetyGate({ PhonePolicies(confirmMode = ConfirmMode.ALWAYS) }, tasks, { null })
        assertSame(SafetyGate.Verdict.Allow, gate.checkWrite(WriteKind.TAP, target(), "example.app", null))
        assertTrue(tasks.isApproved("example.app"))
    }
}
