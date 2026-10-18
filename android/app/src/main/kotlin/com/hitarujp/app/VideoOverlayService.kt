package com.hitarujp.app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Outline
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ProgressBar
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/// Plays a YouTube video in a small window drawn over other apps, like the
/// floating players of video apps, so the learner can keep listening while
/// using something else.
///
/// The window has its own WebView and YouTube iframe player, started where the
/// in-app player stopped. Drag it to move it, pinch (or double-tap) to resize,
/// tap for controls. Closing or expanding it reports the position back to
/// Flutter, so the in-app player carries on from there.
///
/// A foreground service, so Android does not stop it while the app is in the
/// background; the notification also brings the video back into the app.
class VideoOverlayService : Service() {
    companion object {
        const val ACTION_SHOW = "com.hitarujp.app.overlay.SHOW"
        const val ACTION_CLOSE = "com.hitarujp.app.overlay.CLOSE"

        /// On an intent to MainActivity: return the floating video to the app.
        const val EXTRA_EXPAND = "com.hitarujp.app.overlay.EXPAND"

        private const val EXTRA_VIDEO_ID = "videoId"
        private const val EXTRA_POSITION = "position"
        private const val EXTRA_TITLE = "title"
        private const val CHANNEL_ID = "video_overlay"
        private const val NOTIFICATION_ID = 4107
        private const val CONTROLS_VISIBLE_MS = 3000L
        private val VIDEO_ID = Regex("^[A-Za-z0-9_-]{11}$")

        /// The running window, for MainActivity to expand or close it.
        var current: VideoOverlayService? = null
            private set

        /// Receives "overlayProgress" and "overlayClosed" with the video id,
        /// position (seconds) and whether it plays. Set by MainActivity while
        /// its Flutter engine runs; always called on the main thread.
        var listener: ((String, Map<String, Any?>) -> Unit)? = null

        fun show(context: Context, videoId: String, positionSeconds: Double, title: String?) {
            val intent = Intent(context, VideoOverlayService::class.java)
                .setAction(ACTION_SHOW)
                .putExtra(EXTRA_VIDEO_ID, videoId)
                .putExtra(EXTRA_POSITION, positionSeconds)
                .putExtra(EXTRA_TITLE, title)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private lateinit var windowManager: WindowManager
    private lateinit var params: WindowManager.LayoutParams

    private var root: FrameLayout? = null
    private var webView: WebView? = null
    private var controls: View? = null
    private var playPause: ImageButton? = null
    private var progress: ProgressBar? = null

    private var videoId = ""
    private var title: String? = null
    private var positionSeconds = 0.0
    private var durationSeconds = 0.0
    private var playing = false
    private var lastProgressSentAt = 0L

    private val hideControls = Runnable { controls?.visibility = View.GONE }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        current = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val id = intent.getStringExtra(EXTRA_VIDEO_ID)
                if (id == null || !VIDEO_ID.matches(id)) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                title = intent.getStringExtra(EXTRA_TITLE)
                startInForeground()
                load(id, intent.getDoubleExtra(EXTRA_POSITION, 0.0))
            }
            ACTION_CLOSE -> finish(expanded = false)
            else -> stopSelf()
        }
        // Not restarted after the process dies: the position would be lost.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        root?.let { runCatching { windowManager.removeView(it) } }
        webView?.destroy()
        root = null
        webView = null
        if (current === this) current = null
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // The screen turned: keep the window on it.
        if (root != null) {
            resize(params.width)
        }
    }

    /// Closes the window and reports where the video got to. [expanded]
    /// returns the video to the app; [openApp] also brings the app forward
    /// (false when the app is what asked).
    fun finish(expanded: Boolean, openApp: Boolean = expanded) {
        listener?.invoke(
            "overlayClosed",
            mapOf(
                "videoId" to videoId,
                "position" to positionSeconds,
                "playing" to playing,
                "expanded" to expanded,
            ),
        )
        if (openApp) {
            // Allowed from the background: the app may draw over other apps.
            startActivity(
                Intent(this, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                ),
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    // ---- The window ----

    private fun load(id: String, startSeconds: Double) {
        videoId = id
        positionSeconds = startSeconds
        playing = true
        if (root == null) createWindow()
        webView?.loadDataWithBaseURL(
            // The same origin the in-app player uses; YouTube refuses to play
            // embeds that come from nowhere.
            "https://www.youtube-nocookie.com",
            playerHtml(id, startSeconds),
            "text/html",
            "utf-8",
            null,
        )
        updatePlayPause()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()

    private fun screenWidth() = resources.displayMetrics.widthPixels

    private fun screenHeight() = resources.displayMetrics.heightPixels

    private fun minWidth() = dp(160)

    private fun maxWidth() = screenWidth()

    private fun heightFor(width: Int) = width * 9 / 16

    @SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
    private fun createWindow() {
        val width = (min(screenWidth(), screenHeight()) * 0.62).roundToInt()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        params = WindowManager.LayoutParams(
            width,
            heightFor(width),
            type,
            // Never takes the keyboard, and touches outside it reach the app
            // underneath.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // Bottom-right, clear of the navigation bar.
            x = screenWidth() - width - dp(12)
            y = screenHeight() - heightFor(width) - dp(120)
        }

        val frame = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, dp(10).toFloat())
                }
            }
            clipToOutline = true
            elevation = dp(8).toFloat()
        }

        val web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            setBackgroundColor(Color.BLACK)
            webChromeClient = WebChromeClient()
            addJavascriptInterface(Bridge(), "HitaruOverlay")
        }
        frame.addView(web, matchParent())

        // Above the video and below the controls: every touch that is not on
        // a button lands here, so the player itself is never touched.
        val touchLayer = View(this)
        touchLayer.setOnTouchListener(DragAndPinch())
        frame.addView(touchLayer, matchParent())

        val controlsView = buildControls()
        frame.addView(controlsView, matchParent())

        windowManager.addView(frame, params)
        root = frame
        webView = web
        controls = controlsView
        showControls()
    }

    private fun matchParent() = FrameLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT,
    )

    private fun buildControls(): View {
        // Not clickable itself, so touches between the buttons fall through to
        // the drag layer beneath.
        val layer = FrameLayout(this).apply { setBackgroundColor(0x66000000) }

        layer.addView(
            iconButton(R.drawable.ic_overlay_open, "Back to HitaruJP") { finish(expanded = true) },
            FrameLayout.LayoutParams(dp(36), dp(36), Gravity.TOP or Gravity.START),
        )
        layer.addView(
            iconButton(R.drawable.ic_overlay_close, "Close") { finish(expanded = false) },
            FrameLayout.LayoutParams(dp(36), dp(36), Gravity.TOP or Gravity.END),
        )

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        row.addView(
            iconButton(R.drawable.ic_overlay_rewind, "Back 10 seconds") { seekBy(-10.0) },
            LinearLayout.LayoutParams(dp(40), dp(40)),
        )
        val toggle = iconButton(R.drawable.ic_overlay_pause, "Pause") { togglePlayback() }
        row.addView(toggle, LinearLayout.LayoutParams(dp(48), dp(48)).apply {
            marginStart = dp(8)
            marginEnd = dp(8)
        })
        row.addView(
            iconButton(R.drawable.ic_overlay_forward, "Forward 10 seconds") { seekBy(10.0) },
            LinearLayout.LayoutParams(dp(40), dp(40)),
        )
        layer.addView(
            row,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )

        val bar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000
            progressTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
        }
        layer.addView(
            bar,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(4), Gravity.BOTTOM),
        )

        playPause = toggle
        progress = bar
        return layer
    }

    private fun iconButton(icon: Int, label: String, onClick: () -> Unit) =
        ImageButton(this).apply {
            setImageResource(icon)
            contentDescription = label
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            setPadding(dp(6), dp(6), dp(6), dp(6))
            setOnClickListener {
                onClick()
                showControls()
            }
        }

    private fun showControls() {
        controls?.visibility = View.VISIBLE
        main.removeCallbacks(hideControls)
        main.postDelayed(hideControls, CONTROLS_VISIBLE_MS)
    }

    private fun toggleControls() {
        if (controls?.visibility == View.VISIBLE) {
            main.removeCallbacks(hideControls)
            controls?.visibility = View.GONE
        } else {
            showControls()
        }
    }

    private fun updatePlayPause() {
        playPause?.setImageResource(
            if (playing) R.drawable.ic_overlay_pause else R.drawable.ic_overlay_play,
        )
        playPause?.contentDescription = if (playing) "Pause" else "Play"
    }

    /// Sets the window's width (the height follows at 16:9), keeping it on
    /// screen.
    private fun resize(width: Int) {
        val w = width.coerceIn(minWidth(), max(minWidth(), maxWidth()))
        params.width = w
        params.height = heightFor(w)
        moveTo(params.x, params.y)
    }

    private fun moveTo(x: Int, y: Int) {
        params.x = x.coerceIn(0, max(0, screenWidth() - params.width))
        params.y = y.coerceIn(0, max(0, screenHeight() - params.height))
        root?.let { windowManager.updateViewLayout(it, params) }
    }

    /// Drag to move, pinch to resize, tap for controls, double-tap to switch
    /// between small and large.
    private inner class DragAndPinch : View.OnTouchListener {
        private val slop = ViewConfiguration.get(this@VideoOverlayService).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false

        /// Set once a second finger lands, until all fingers lift, so the
        /// finger left after a pinch does not jerk the window.
        private var pinched = false

        private val taps = GestureDetector(
            this@VideoOverlayService,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                    toggleControls()
                    return true
                }

                override fun onDoubleTap(e: MotionEvent): Boolean {
                    val small = (min(screenWidth(), screenHeight()) * 0.62).roundToInt()
                    val centerX = params.x + params.width / 2
                    val centerY = params.y + params.height / 2
                    resize(if (params.width > small + dp(8)) small else maxWidth())
                    moveTo(centerX - params.width / 2, centerY - params.height / 2)
                    return true
                }
            },
        )

        private val pinch = ScaleGestureDetector(
            this@VideoOverlayService,
            object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                override fun onScale(detector: ScaleGestureDetector): Boolean {
                    val centerX = params.x + params.width / 2
                    val centerY = params.y + params.height / 2
                    resize((params.width * detector.scaleFactor).roundToInt())
                    moveTo(centerX - params.width / 2, centerY - params.height / 2)
                    return true
                }
            },
        )

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouch(view: View, event: MotionEvent): Boolean {
            pinch.onTouchEvent(event)
            if (event.pointerCount > 1) pinched = true
            if (!pinched) taps.onTouchEvent(event)

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    dragging = false
                    pinched = false
                }
                MotionEvent.ACTION_MOVE -> if (!pinched) {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && hypot(dx, dy) > slop) dragging = true
                    if (dragging) moveTo(startX + dx.roundToInt(), startY + dy.roundToInt())
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    dragging = false
                }
            }
            return true
        }
    }

    // ---- The player ----

    private fun js(script: String) {
        webView?.evaluateJavascript(script, null)
    }

    private fun togglePlayback() {
        js(if (playing) "player && player.pauseVideo()" else "player && player.playVideo()")
        playing = !playing
        updatePlayPause()
    }

    private fun seekBy(seconds: Double) {
        var target = max(0.0, positionSeconds + seconds)
        if (durationSeconds > 0) target = min(target, durationSeconds)
        positionSeconds = target
        js("player && player.seekTo($target, true)")
    }

    /// What the page reports, posted to the main thread (the bridge calls
    /// come on a WebView thread).
    private inner class Bridge {
        @JavascriptInterface
        fun onState(state: Int) = main.post {
            // 1 playing, 2 paused, 0 ended; buffering and the rest keep the
            // last answer.
            when (state) {
                1 -> playing = true
                0, 2 -> playing = false
                else -> return@post
            }
            updatePlayPause()
            sendProgress(force = true)
        }

        @JavascriptInterface
        fun onTime(position: Double, duration: Double) = main.post {
            positionSeconds = position
            durationSeconds = duration
            if (duration > 0) progress?.progress = (position / duration * 1000).roundToInt()
            sendProgress(force = false)
        }
    }

    /// Keeps Flutter's transcript position and immersion timer moving while
    /// the video plays out here.
    private fun sendProgress(force: Boolean) {
        val now = System.currentTimeMillis()
        if (!force && now - lastProgressSentAt < 1000) return
        lastProgressSentAt = now
        listener?.invoke(
            "overlayProgress",
            mapOf("videoId" to videoId, "position" to positionSeconds, "playing" to playing),
        )
    }

    private fun playerHtml(id: String, startSeconds: Double): String = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
          #player { position: absolute; inset: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player;
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              videoId: '$id',
              host: 'https://www.youtube-nocookie.com',
              playerVars: {
                autoplay: 1, controls: 0, playsinline: 1, rel: 0, fs: 0,
                disablekb: 1, iv_load_policy: 3, modestbranding: 1,
                start: ${startSeconds.toInt()},
                origin: 'https://www.youtube-nocookie.com',
                widget_referrer: 'https://www.youtube-nocookie.com'
              },
              events: {
                onReady: function (e) {
                  e.target.seekTo($startSeconds, true);
                  e.target.playVideo();
                  setInterval(function () {
                    if (player && player.getCurrentTime) {
                      HitaruOverlay.onTime(player.getCurrentTime(), player.getDuration() || 0);
                    }
                  }, 500);
                },
                onStateChange: function (e) { HitaruOverlay.onState(e.data); }
              }
            });
          }
        </script>
        </body>
        </html>
    """.trimIndent()

    // ---- Foreground notification ----

    private fun startInForeground() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Floating video", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .putExtra(EXTRA_EXPAND, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val close = PendingIntent.getService(
            this,
            1,
            Intent(this, VideoOverlayService::class.java).setAction(ACTION_CLOSE),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        @Suppress("DEPRECATION")
        val notification = builder
            .setSmallIcon(R.drawable.ic_overlay_play)
            .setContentTitle(title ?: "Floating video")
            .setContentText("Playing over other apps. Tap to return to HitaruJP.")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(R.drawable.ic_overlay_close, "Close", close).build())
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
