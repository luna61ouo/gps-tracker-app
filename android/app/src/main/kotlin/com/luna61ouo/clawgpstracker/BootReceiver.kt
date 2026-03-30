package com.luna61ouo.clawgpstracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Starts the GPS background service when the device boots.
 *
 * flutter_background_service's autoStart flag handles crash-restarts,
 * but not power-on boot. This receiver bridges that gap.
 *
 * The service itself checks kTrackingEnabledKey on startup and exits
 * immediately if the user never enabled tracking — so no spurious
 * foreground notification on first boot before setup.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            val serviceIntent = Intent(
                context,
                id.flutter.flutter_background_service.BackgroundService::class.java
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }
    }
}
