package com.xrkseek.harness.runtime

import org.junit.Assert.assertEquals
import org.junit.Test

class PhoneStoragePrefsTest {
    @Test
    fun `coercePrefsBoolean accepts common SharedPreferences shapes`() {
        assertEquals(true, PhoneStorage.coercePrefsBoolean(true, false))
        assertEquals(false, PhoneStorage.coercePrefsBoolean(false, true))
        assertEquals(true, PhoneStorage.coercePrefsBoolean(1, false))
        assertEquals(false, PhoneStorage.coercePrefsBoolean(0, true))
        assertEquals(true, PhoneStorage.coercePrefsBoolean("true", false))
        assertEquals(false, PhoneStorage.coercePrefsBoolean("0", true))
        assertEquals(true, PhoneStorage.coercePrefsBoolean(null, true))
        assertEquals(false, PhoneStorage.coercePrefsBoolean("maybe", false))
    }
}
