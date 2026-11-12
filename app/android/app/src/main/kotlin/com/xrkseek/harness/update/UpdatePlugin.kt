package com.xrkseek.harness.update

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executors

/** Flutter bridge for in-app updates: MethodChannel `xrk/update` (see lib/update/installer.dart). */
class UpdatePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private lateinit var installer: ApkInstaller
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        installer = ApkInstaller(appContext)
        channel = MethodChannel(binding.binaryMessenger, "xrk/update").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_INSTALL_PERMISSION) return false
        // Tell Dart the Settings page closed. Pass the live AppOps value so a
        // lagging lifecycle onResume isn't the only path that can continue.
        main.post {
            channel.invokeMethod("installPermissionClosed", installer.canRequestInstalls())
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "info" -> result.success(installer.info())
            "canRequestInstalls" -> result.success(installer.canRequestInstalls())
            "openInstallPermission" -> result.success(openInstallPermissionForResult())
            "inspect" -> {
                val apk = apkArgument(call, result) ?: return
                worker.execute {
                    val info = runCatching { installer.inspect(apk) }.getOrElse { mapOf("valid" to false) }
                    main.post { result.success(info) }
                }
            }
            "install" -> {
                val apk = apkArgument(call, result) ?: return
                var replied = false
                worker.execute {
                    installer.install(
                        apk,
                        confirm = ::showConfirm,
                        onResult = { outcome ->
                            main.post {
                                if (!replied) {
                                    replied = true
                                    result.success(outcome)
                                }
                            }
                        },
                    )
                }
            }
            "openWithSystem" -> {
                val apk = apkArgument(call, result) ?: return
                result.success(openWithSystem(apk))
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Opens the per-app "install unknown apps" page with [startActivityForResult]
     * so [onActivityResult] fires when the person returns — lifecycle alone is
     * not enough on some OEMs (toggle on, sheet still says 「去开启」 until kill).
     */
    private fun openInstallPermissionForResult(): Boolean {
        val host = activity
        val intents = listOf(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${appContext.packageName}")),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${appContext.packageName}")),
        )
        for (intent in intents) {
            val started = runCatching {
                if (host != null) {
                    @Suppress("DEPRECATION")
                    host.startActivityForResult(intent, REQUEST_INSTALL_PERMISSION)
                } else {
                    appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    // No Activity Result without a host — Dart still has onResume polling.
                }
            }.isSuccess
            if (started) return true
        }
        return false
    }

    /**
     * The package in the system's own installer: some OEM builds stop the session install before
     * the person is asked (it reads as cancelled), while opening the file goes through.
     */
    private fun openWithSystem(apk: File): Boolean = runCatching {
        val uri = FileProvider.getUriForFile(appContext, "${appContext.packageName}.files", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val host = activity
        if (host != null) host.startActivity(intent) else appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }.isSuccess

    private fun apkArgument(call: MethodCall, result: MethodChannel.Result): File? {
        val path = call.argument<String>("path")
        val file = path?.let(::File)
        if (file == null || !file.isFile) {
            result.error("no_file", "APK not found: $path", null)
            return null
        }
        return file
    }

    /** The system's "install this update?" dialog, over our activity when we have one. */
    private fun showConfirm(intent: Intent): Boolean {
        val host = activity
        return runCatching {
            if (host != null) host.startActivity(intent) else appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }.isSuccess
    }

    companion object {
        private const val REQUEST_INSTALL_PERMISSION = 0x58B1
    }
}
