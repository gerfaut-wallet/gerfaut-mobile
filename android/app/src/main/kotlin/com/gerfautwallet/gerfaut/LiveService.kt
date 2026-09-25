package com.gerfautwallet.gerfaut

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Live watch: the foreground service that keeps the core's connection
// to the user's server open while the app is off screen.
//
// Everything Android-specific lives here and nothing else does. The
// service hosts a Flutter engine without a view, on the Dart entry point
// `liveMain`, which opens the vault the way the periodic background task
// already does and starts the watch in the core. The engine runs in the
// app's one process: the core keeps a single wallet manager per process,
// so the screens, the periodic task and this service all go through the
// same vault owner. The service must never get an android:process of
// its own; two processes would overwrite each other's vault.
//
// The service holds no wake lock while it waits. An incoming packet
// wakes the phone by itself; what does not run while the phone sleeps is
// every timer, the core's keepalive included. So an alarm the system
// honours in Doze comes by every few minutes, and each change of network
// comes by at once, and both ask the core to check its connection under
// a wake lock that is short and released by a timeout whatever happens.
class LiveService : Service() {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var tickLock: PowerManager.WakeLock? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val main = Handler(Looper.getMainLooper())

    // What the Dart side last said of the connection, and whether the
    // phone has a network at all: the second overrides the first.
    private var statusText: String = TEXT_STARTING
    private var networkUp: Boolean = true

    // Set once a stop is under way, so nothing restarts what is leaving.
    private var leaving: Boolean = false

    // A start came while the stop was under way: once this service is
    // gone, another one starts.
    private var restartWhenGone: Boolean = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // First, always, and before any early return: a service started
        // with startForegroundService has a few seconds to do this.
        if (!enterForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!isWanted(this)) {
            shutdown()
            return START_NOT_STICKY
        }
        if (leaving) {
            // Turned back on while the last stop is still saying what
            // its watch held: that stop ends this service in a moment,
            // and a fresh one starts once it is gone. Shutting down here
            // instead would leave Live wanted and running nowhere.
            restartWhenGone = true
            return START_NOT_STICKY
        }
        instance = this
        when (intent?.action) {
            ACTION_STOP -> {
                userStop()
                return START_NOT_STICKY
            }
            // A null intent is the system recreating a sticky service:
            // it starts over from the stored flag, like any other start.
            else -> {
                ensureEngine()
                watchNetwork()
                armHeartbeat(this, HEARTBEAT_MS)
                if (intent?.action == ACTION_TICK) tick()
            }
        }
        return START_STICKY
    }

    // Swiped from the recents: the service goes on (stopWithTask is
    // false). Some phones kill the whole process here anyway; an early
    // alarm gives the restart its chance.
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (isWanted(this) && !leaving) armHeartbeat(this, RESTART_MS)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        // A start still waiting for an engine to retire starts nothing
        // now: this service is gone.
        main.removeCallbacksAndMessages(null)
        releaseTickLock()
        unwatchNetwork()
        val live = channel
        val hosted = engine
        channel = null
        engine = null
        if (live != null && hosted != null) retire(live, hosted)
        // Destroyed without having been asked to leave: the system took
        // the service. The heartbeat stays armed and tries to bring it
        // back.
        if (isWanted(this) && !leaving) armHeartbeat(this, RESTART_MS)
        // Asked for again during the stop: started now that it is over,
        // from the app on screen that asked, which is what lets a
        // foreground service start at all.
        if (restartWhenGone && isWanted(this)) {
            val app = applicationContext
            Handler(Looper.getMainLooper()).post { start(app) }
        }
        super.onDestroy()
    }

    // --- foreground -----------------------------------------------------

    private fun enterForeground(): Boolean {
        return try {
            createChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (_: Exception) {
            // Android 12 and later refuse a start from the background
            // to an app that is not exempt from battery optimisation.
            // The periodic check is still scheduled: nothing is lost
            // but the immediacy.
            false
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Live watch",
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = "Shown while Gerfaut keeps its connection open."
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        manager.createNotificationChannel(channel)
    }

    // Says that something runs and how the connection fares, and never
    // anything of what is watched: no wallet name, no amount, no host.
    private fun buildNotification(): Notification {
        val immutable = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Watching for transactions")
            .setContentText(if (networkUp) statusText else TEXT_NO_NETWORK)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        // The launcher entry in force: an explicit intent to this app.
        packageManager.getLaunchIntentForPackage(packageName)?.let { open ->
            open.setPackage(packageName)
            builder.setContentIntent(PendingIntent.getActivity(this, 0, open, immutable))
        }
        val stop = Intent(this, LiveService::class.java).setAction(ACTION_STOP)
        builder.addAction(0, "Stop", PendingIntent.getService(this, 1, stop, immutable))
        return builder.build()
    }

    private fun refreshNotification() {
        if (leaving) return
        try {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {
            // A notification that cannot be redrawn keeps its old text.
        }
    }

    // --- the engine -----------------------------------------------------

    private fun ensureEngine() {
        if (engine != null || leaving) return
        // The engine of a service that just went is still saying what
        // its watch held: two of them would say it twice.
        if (retiring > 0) {
            main.postDelayed({ ensureEngine() }, RETIRE_POLL_MS)
            return
        }
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val created = FlutterEngine(this)
        val live = MethodChannel(created.dartExecutor.binaryMessenger, SERVICE_CHANNEL)
        live.setMethodCallHandler { call, result ->
            when (call.method) {
                // How the connection fares, in the notification's words.
                "status" -> {
                    (call.arguments as? String)?.let {
                        statusText = it.take(STATUS_MAX)
                        refreshNotification()
                    }
                    result.success(null)
                }
                // The Dart side read the settings and Live is not what
                // they ask for: turned off elsewhere, or disguised.
                "standDown" -> {
                    result.success(null)
                    setWanted(this, false)
                    shutdown()
                }
                else -> result.notImplemented()
            }
        }
        engine = created
        channel = live
        created.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), DART_ENTRY_POINT),
        )
    }

    // --- heartbeat and network ------------------------------------------

    // Asks the core to check its connection now, under a wake lock that
    // ends with the answer or after TICK_LOCK_MS, whichever comes first.
    internal fun tick() {
        val live = channel ?: return
        if (leaving) return
        val lock = acquireTickLock()
        live.invokeMethod(
            "tick",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) = release(lock)
                override fun error(code: String, message: String?, details: Any?) = release(lock)
                override fun notImplemented() = release(lock)
            },
        )
    }

    private fun acquireTickLock(): PowerManager.WakeLock {
        val existing = tickLock
        if (existing != null) {
            // Not counted: a second tick extends the one lock.
            existing.acquire(TICK_LOCK_MS)
            return existing
        }
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val lock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "gerfaut:live-tick")
        lock.setReferenceCounted(false)
        lock.acquire(TICK_LOCK_MS)
        tickLock = lock
        return lock
    }

    private fun release(lock: PowerManager.WakeLock) {
        try {
            if (lock.isHeld) lock.release()
        } catch (_: RuntimeException) {
            // Already let go by its timeout.
        }
    }

    private fun releaseTickLock() {
        tickLock?.let { release(it) }
        tickLock = null
    }

    // A change of network closes the sockets of the network that went,
    // but the core's retry timer sleeps with the phone: it is told now.
    private fun watchNetwork() {
        if (networkCallback != null) return
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                main.post {
                    networkUp = true
                    refreshNotification()
                    tick()
                }
            }

            override fun onLost(network: Network) {
                main.post {
                    networkUp = manager.activeNetwork != null
                    refreshNotification()
                }
            }
        }
        try {
            manager.registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (_: Exception) {
            // Without the callback the heartbeat still finds a dead
            // connection, a few minutes later.
        }
    }

    private fun unwatchNetwork() {
        val callback = networkCallback ?: return
        networkCallback = null
        try {
            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                .unregisterNetworkCallback(callback)
        } catch (_: Exception) {
            // Never registered, or already gone.
        }
    }

    // --- leaving ----------------------------------------------------------

    // "Stop" on the notification: Live goes off, and the setting goes
    // back to a check every fifteen minutes. The Dart side writes that
    // in the vault; should it not answer, the flag cleared here is what
    // the app reads at its next start to do the same.
    private fun userStop() {
        setWanted(this, false)
        quit(revert = true)
    }

    private fun quit(revert: Boolean) {
        if (leaving) return
        leaving = true
        cancelHeartbeat(this)
        val live = channel
        if (live == null) {
            shutdown()
            return
        }
        var done = false
        val finish = Runnable {
            if (!done) {
                done = true
                shutdown()
            }
        }
        main.postDelayed(finish, STOP_TIMEOUT_MS)
        live.invokeMethod(
            "stop",
            revert,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    main.post(finish)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    main.post(finish)
                }

                override fun notImplemented() {
                    main.post(finish)
                }
            },
        )
    }

    // The watch lives in the process, not in this service. A service the
    // system destroyed would leave it running with nobody to say what it
    // finds, and what the core hands out is never handed out again. So
    // the watch is stopped first; the engine goes once the Dart side has
    // said everything it held, or after STOP_TIMEOUT_MS. The next start
    // begins a watch of its own, which catches up on the gap.
    private fun retire(live: MethodChannel, hosted: FlutterEngine) {
        retiring++
        var done = false
        val finish = Runnable {
            if (!done) {
                done = true
                live.setMethodCallHandler(null)
                hosted.destroy()
                retiring--
            }
        }
        main.postDelayed(finish, STOP_TIMEOUT_MS)
        live.invokeMethod(
            "stop",
            false,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    main.post(finish)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    main.post(finish)
                }

                override fun notImplemented() {
                    main.post(finish)
                }
            },
        )
    }

    private fun shutdown() {
        leaving = true
        cancelHeartbeat(this)
        main.removeCallbacksAndMessages(null)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        const val ACTION_START = "com.gerfautwallet.gerfaut.live.START"
        const val ACTION_STOP = "com.gerfautwallet.gerfaut.live.STOP"
        const val ACTION_TICK = "com.gerfautwallet.gerfaut.live.TICK"

        private const val SERVICE_CHANNEL = "gerfaut/live_service"
        private const val DART_ENTRY_POINT = "liveMain"
        private const val CHANNEL_ID = "live"
        private const val NOTIFICATION_ID = 0x4C495645
        private const val PREFS = "gerfaut.live"
        private const val PREF_WANTED = "wanted"
        private const val DISGUISE_MARKER = "disguised"
        private const val STATUS_MAX = 80
        private const val TEXT_STARTING = "Starting"
        private const val TEXT_NO_NETWORK = "Waiting for network"

        // Under the ten minutes after which an Electrum server may drop
        // a silent client, and under the five after which the shortest
        // carrier NATs forget a connection. In Doze the system stretches
        // it to about nine minutes by itself.
        private const val HEARTBEAT_MS = 270_000L
        private const val RESTART_MS = 2_000L
        private const val TICK_LOCK_MS = 30_000L
        private const val STOP_TIMEOUT_MS = 8_000L
        private const val RETIRE_POLL_MS = 250L

        // Engines of destroyed services still finishing. Main thread only.
        private var retiring = 0

        // The running service, for the heartbeat receiver of this same
        // process. Main thread only.
        @Volatile
        internal var instance: LiveService? = null

        val isRunning: Boolean
            get() = instance != null

        // Whether the user asked for Live on this phone. Kept outside
        // the vault on purpose: the boot receiver reads it before any
        // Dart code runs, and a vault restored on another phone must
        // not start a service nobody agreed to there.
        fun isWanted(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(PREF_WANTED, false) && !isDisguised(context)

        fun setWanted(context: Context, wanted: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putBoolean(PREF_WANTED, wanted).apply()
        }

        // The marker the activity keeps while the launcher shows the
        // calculator. Disguised, nothing of Gerfaut may run in sight.
        private fun isDisguised(context: Context): Boolean =
            File(context.filesDir, DISGUISE_MARKER).exists()

        // Starts the service, or answers false where Android will not
        // let a background app do so.
        fun start(context: Context, action: String = ACTION_START): Boolean {
            if (!isWanted(context)) return false
            val intent = Intent(context, LiveService::class.java).setAction(action)
            return try {
                ContextCompat.startForegroundService(context, intent)
                true
            } catch (_: Exception) {
                false
            }
        }

        // Turned off from the app: the flag first, then the service if
        // there is one to tell.
        fun stop(context: Context) {
            setWanted(context, false)
            cancelHeartbeat(context)
            val running = instance ?: return
            running.quit(revert = false)
        }

        private fun heartbeatIntent(context: Context): PendingIntent {
            val intent = Intent(context, LiveReceiver::class.java).setAction(ACTION_TICK)
            return PendingIntent.getBroadcast(
                context,
                2,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        // Inexact on purpose: exact alarms need a permission this app
        // has no claim to, and a few seconds either way change nothing.
        fun armHeartbeat(context: Context, delayMs: Long = HEARTBEAT_MS) {
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            try {
                alarms.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + delayMs,
                    heartbeatIntent(context),
                )
            } catch (_: Exception) {
                // No alarm: the periodic check remains.
            }
        }

        fun cancelHeartbeat(context: Context) {
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarms.cancel(heartbeatIntent(context))
        }
    }
}
