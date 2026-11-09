package io.github.ccch1mneyyy.dsh_app.phone

import android.content.Context

/**
 * Shared disclosure gate for 「手机操控」: Flutter Settings and Host Settings
 * must agree before [PhoneControl.setEnabled](true) is allowed via MobileApi.
 *
 * Flutter writes `FlutterSharedPreferences` / `flutter.phone_disclosure_v1`.
 * Native also mirrors into `dsh_phone` so either path can accept once.
 */
internal object PhoneDisclosure {
    const val KEY = "phone_disclosure_v1"

    private const val NATIVE_PREFS = "dsh_phone"
    private const val NATIVE_KEY = "disclosureAccepted"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val FLUTTER_KEY = "flutter.$KEY"

    fun isAccepted(app: Context): Boolean {
        val native = app.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(NATIVE_KEY, false)
        if (native) return true
        return app.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getBoolean(FLUTTER_KEY, false)
    }

    fun accept(app: Context) {
        app.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(NATIVE_KEY, true)
            .apply()
        app.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(FLUTTER_KEY, true)
            .apply()
    }
}
