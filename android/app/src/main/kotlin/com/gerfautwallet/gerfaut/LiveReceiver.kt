package com.gerfautwallet.gerfaut

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.UserManager

// The three moments Live watch has to be brought back, or nudged,
// without the app being open: the phone has started, the app was
// updated (which kills its process), and the heartbeat alarm.
//
// Not exported. The system delivers its own broadcasts to a receiver
// that is not, and the heartbeat is an explicit intent of this app; no
// other app can reach it. The actions are still checked one by one, and
// nothing an intent carries is read.
class LiveReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != LiveService.ACTION_TICK
        ) {
            return
        }
        val app = context.applicationContext
        // Live is off, or the app is disguised: nothing starts, and the
        // heartbeat is not armed again.
        if (!LiveService.isWanted(app)) return
        // Before the first unlock the key that opens the vault cannot be
        // read. BOOT_COMPLETED only comes after it, but nothing is lost
        // by checking.
        val users = app.getSystemService(Context.USER_SERVICE) as UserManager
        if (!users.isUserUnlocked) return

        // Armed before anything else, so a failure below still leaves
        // the next attempt scheduled.
        LiveService.armHeartbeat(app)
        val running = LiveService.instance
        if (running != null) {
            if (action == LiveService.ACTION_TICK) running.tick()
            return
        }
        // Not running: killed, or never started since boot. Android 12
        // and later only allow this from the background after a boot, an
        // update, or for an app exempt from battery optimisation; a
        // refusal is caught in there, and the periodic check goes on.
        LiveService.start(app)
    }
}
