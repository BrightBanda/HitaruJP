package com.hitarujp.app

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Hosts the app and lets the video player shrink into a picture-in-picture
/// window, so a video keeps playing when the learner leaves the screen.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /// Set by Flutter while a video is playing: leaving the app then enters
    /// picture-in-picture instead of pausing the video behind the home screen.
    private var autoEnter = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
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
    }

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
    }
}
