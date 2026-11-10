package com.xrkseek.harness.phone

import org.junit.Assert.assertEquals
import org.junit.Test

/** Contract lock: Flutter SharedPreferences key must match native disclosure gate. */
class PhoneDisclosureKeysTest {
    @Test
    fun flutterSharedKeyMatchesNativeConstant() {
        assertEquals("phone_disclosure_v1", PhoneDisclosure.KEY)
    }
}
