package io.github.ccch1mneyyy.dsh_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.github.ccch1mneyyy.dsh_app.files.FilesPlugin
import io.github.ccch1mneyyy.dsh_app.launch.LaunchScreen
import io.github.ccch1mneyyy.dsh_app.launch.LaunchThemeSync
import io.github.ccch1mneyyy.dsh_app.links.LinksPlugin
import io.github.ccch1mneyyy.dsh_app.notify.NotifyPlugin
import io.github.ccch1mneyyy.dsh_app.phone.PhonePlugin
import io.github.ccch1mneyyy.dsh_app.runtime.LaunchStart
import io.github.ccch1mneyyy.dsh_app.runtime.RuntimePlugin
import io.github.ccch1mneyyy.dsh_app.share.SharePlugin
import java.lang.ref.WeakReference
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private var appChannel: MethodChannel? = null

    /**
     * One engine per process, outliving this activity: swiping the app away from recents keeps
     * Dart running, and with it the event subscriptions behind turn-finished / needs-you
     * notifications. Plugins are registered once, with the engine.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        return FlutterEngine(applicationContext).also { engine ->
            // Thin shell: keep runtime + phone + file/media seams; drop B-tier UI plugins.
            engine.plugins.add(RuntimePlugin())
            engine.plugins.add(PhonePlugin())
            engine.plugins.add(NotifyPlugin())
            engine.plugins.add(FilesPlugin())
            engine.plugins.add(LinksPlugin())
            engine.plugins.add(SharePlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.diagnostics.DiagnosticsPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.nativemedia.NativeMediaPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.nativefiles.NativeFilesPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.web.WebFilesPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.launch.LaunchPlugin())
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            cache.put(ENGINE_ID, engine)
        }
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    /**
     * This activity's own <meta-data> (normal theme, Flutter deep linking off), whichever launcher
     * alias opened it: Flutter reads it for getComponentName(), which is the alias — that has
     * none of it, and is disabled once the user picks another 桌面图标 (icons/).
     */
    override fun getMetaData(): Bundle? =
        packageManager.getActivityInfo(ComponentName(this, MainActivity::class.java), PackageManager.GET_META_DATA).metaData

    override fun onCreate(savedInstanceState: Bundle?) {
        // 「打开 App 时自动启动」: DSH boots while Flutter starts, not after its first frame.
        LaunchStart.onActivityCreate(this)
        // 启动画面: the first activity of a cold start hands the system's launch window to Dart's.
        LaunchScreen.onActivityCreate(this, coldDart = FlutterEngineCache.getInstance().get(ENGINE_ID) == null)
        // Recreated, or reopened from recents: the launch intent is an old notification tap or
        // link that was handled back then. Don't let the plugins route it again.
        if (savedInstanceState != null || intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) {
            intent.action = Intent.ACTION_MAIN
            intent.replaceExtras(Bundle())
        }
        super.onCreate(savedInstanceState)
        // Fully transparent system bars, no OEM scrim behind the gesture handle.
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) window.setDecorFitsSystemWindows(false)
        // targetSdk 28 + wide MuMu/pad: force the window and Flutter view to the real
        // display bounds so size-compat does not leave black side pillars.
        window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
        fillFlutterView()
        window.decorView.post { fillFlutterView() }
        current = WeakReference(this)
        // After LaunchScreen read what this launch's splash showed: the next ones show the icon
        // (and launch screen) chosen now (Android 13+).
        LaunchThemeSync.sync(this)
    }

    /** Make FlutterView MATCH_PARENT even when size-compat first measured a narrow strip. */
    private fun fillFlutterView() {
        val flutter = findViewById<View>(FLUTTER_VIEW_ID) ?: return
        val lp = flutter.layoutParams ?: return
        if (lp.width == ViewGroup.LayoutParams.MATCH_PARENT && lp.height == ViewGroup.LayoutParams.MATCH_PARENT) {
            return
        }
        lp.width = ViewGroup.LayoutParams.MATCH_PARENT
        lp.height = ViewGroup.LayoutParams.MATCH_PARENT
        flutter.layoutParams = lp
        flutter.requestLayout()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Light / dark: a custom launch screen's plain splash colour (the page's) may change with it.
        LaunchThemeSync.sync(this)
    }

    override fun onResume() {
        super.onResume()
        io.github.ccch1mneyyy.dsh_app.phone.background.BackgroundControl.get(applicationContext).restoreKeptChannel()
        inForeground = true
        // Coming back counts as activity: the first frames may not be scheduled yet.
        framesActive = true
        applyRefreshRate()
    }

    /**
     * The window's preferred display mode, from the in-app refresh-rate setting.
     *
     * `preferredDisplayModeId = 0` means "no preference": the system picks, and its own
     * refresh-rate setting and power saving still decide. Apps that never ask stay at 60 or
     * 90 Hz on some 120 Hz phones (OriginOS, HyperOS, ColorOS); once an app does ask, those
     * systems show their per-app switch as an in-app setting – hence the setting in 设置 › 性能.
     *
     * auto: fastest mode while Flutter is producing frames, released after the last one.
     * max: pinned. system: never declared.
     */
    private fun applyRefreshRate() {
        @Suppress("DEPRECATION")
        val display = windowManager.defaultDisplay
        val now = display.mode
        val fastest = display.supportedModes
            .filter { it.physicalWidth == now.physicalWidth && it.physicalHeight == now.physicalHeight }
            .maxByOrNull { it.refreshRate }
        val want = when (refreshMode) {
            "max" -> fastest
            "system" -> null
            else -> if (framesActive) fastest else null
        }
        val target = want?.modeId ?: 0
        if (window.attributes.preferredDisplayModeId == target) return
        window.attributes = window.attributes.apply { preferredDisplayModeId = target }
    }

    override fun onPause() {
        inForeground = false
        framesActive = false
        applyRefreshRate()
        super.onPause()
    }

    /** Per activity: the handler acts on this activity, so it goes with it (see [cleanUpFlutterEngine]). */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/app")
        appChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getTimeZoneId" -> result.success(TimeZone.getDefault().id)
                // A browser sign-in finished (a Custom Tab on top of this task): clearing down
                // to this activity closes the tab and shows the app again.
                // 设置 → 性能 → 刷新率: auto | max | system, and whether Flutter is drawing.
                "setRefreshRateMode" -> {
                    when (call.argument<String>("mode")) {
                        "auto", "max", "system" -> refreshMode = call.argument<String>("mode")!!
                    }
                    applyRefreshRate()
                    result.success(null)
                }
                "setFrameActive" -> {
                    framesActive = call.argument<Boolean>("active") ?: framesActive
                    applyRefreshRate()
                    result.success(null)
                }
                "bringToFront" -> {
                    startActivity(
                        Intent(this, MainActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        appChannel?.setMethodCallHandler(null)
        appChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Back on the home screen sends the app to the background instead of finishing the activity
    // (Android 12's default for launcher roots): coming back finds it as it was.
    override fun popSystemNavigator(): Boolean = moveTaskToBack(true)

    /** 设置 › 性能 › 刷新率; the Flutter side owns the stored choice. */
    private var refreshMode = "auto"

    /** Flutter produced a frame recently (see RefreshRateService): auto mode follows it. */
    private var framesActive = true

    companion object {
        private const val ENGINE_ID = "dsh-main"

        /** The app is on screen (resumed). */
        @Volatile var inForeground = false
            private set

        /** The activity now, for what needs one later (the splash theme of the next launches). */
        @Volatile var current: WeakReference<MainActivity>? = null
            private set
    }
}
