package com.hitarujp.app

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Rational
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Hosts the app and lets the video player shrink into a picture-in-picture
/// window, so a video keeps playing when the learner leaves the screen. It
/// also starts the window that floats a video over other apps
/// ([VideoOverlayService]).
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var overlayChannel: MethodChannel? = null

    /// Set by Flutter while a video is playing: leaving the app then enters
    /// picture-in-picture instead of pausing the video behind the home screen.
    private var autoEnter = false

    /// A float request waiting for the learner to grant "display over other
    /// apps" in Settings.
    private var pendingFloat: (() -> Unit)? = null
    private var pendingFloatResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        channel = MethodChannel(messenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "setAutoEnter" -> {
                    autoEnter = call.arguments as? Boolean ?: false
                    updateAutoEnter()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        overlayChannel = MethodChannel(messenger, OVERLAY_CHANNEL)
        overlayChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val videoId = call.argument<String>("videoId")
                    if (videoId == null) {
                        result.error("bad_args", "videoId is required", null)
                        return@setMethodCallHandler
                    }
                    val position = call.argument<Double>("position") ?: 0.0
                    val title = call.argument<String>("title")
                    floatVideo(result) { startFloating(videoId, position, title) }
                }
                "hide" -> {
                    VideoOverlayService.current?.finish(expanded = false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        VideoOverlayService.listener = { method, args ->
            overlayChannel?.invokeMethod(method, args)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        VideoOverlayService.listener = null
        overlayChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleExpand(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleExpand(intent)
    }

    /// The floating video's notification was tapped: bring it back in here.
    private fun handleExpand(intent: Intent?) {
        if (intent?.getBooleanExtra(VideoOverlayService.EXTRA_EXPAND, false) != true) return
        intent.removeExtra(VideoOverlayService.EXTRA_EXPAND)
        VideoOverlayService.current?.finish(expanded = true, openApp = false)
    }

    // ---- Floating over other apps ----

    /// Runs [start] once the app may draw over other apps, asking in Settings
    /// first when needed. Replies true when the video floats.
    private fun floatVideo(result: MethodChannel.Result, start: () -> Unit) {
        if (Settings.canDrawOverlays(this)) {
            start()
            result.success(true)
            return
        }
        pendingFloatResult?.success(false)
        pendingFloat = start
        pendingFloatResult = result
        Toast.makeText(
            this,
            "Allow HitaruJP to display over other apps to float videos.",
            Toast.LENGTH_LONG,
        ).show()
        @Suppress("DEPRECATION")
        startActivityForResult(
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            ),
            OVERLAY_PERMISSION_REQUEST,
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != OVERLAY_PERMISSION_REQUEST) return
        // Some phones report the new setting a moment late.
        Handler(Looper.getMainLooper()).postDelayed({
            val start = pendingFloat
            val result = pendingFloatResult
            pendingFloat = null
            pendingFloatResult = null
            if (Settings.canDrawOverlays(this) && start != null) {
                start()
                result?.success(true)
            } else {
                result?.success(false)
            }
        }, 300)
    }

    private fun startFloating(videoId: String, position: Double, title: String?) {
        // The floating window replaces picture-in-picture while it is up.
        autoEnter = false
        updateAutoEnter()
        VideoOverlayService.show(this, videoId, position, title)
        // Off to the home screen, leaving the video floating.
        moveTaskToBack(true)
    }

    // ---- Picture-in-picture ----

    private fun params(): PictureInPictureParams.Builder =
        PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))

    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun enterPip() {
        if (!isPipSupported()) return
        try {
            enterPictureInPictureMode(params().build())
        } catch (e: IllegalStateException) {
            // The switch for this app is off: nothing to do.
        }
    }

    private fun updateAutoEnter() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && isPipSupported()) {
            setPictureInPictureParams(params().setAutoEnterEnabled(autoEnter).build())
        }
    }

    // Before Android 12 there is no auto-enter flag: leaving is the signal.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoEnter && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    companion object {
        private const val CHANNEL = "hitarujp/pip"
        private const val OVERLAY_CHANNEL = "hitarujp/overlay"
        private const val OVERLAY_PERMISSION_REQUEST = 4108
    }
}
