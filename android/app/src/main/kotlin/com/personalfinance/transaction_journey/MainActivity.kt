package com.personalfinance.transaction_journey

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import com.personalfinance.transaction_journey.widget.WidgetHeadlessExecutor
import com.personalfinance.transaction_journey.widget.WidgetPrefs
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val widgetChannelName = "com.personalfinance.transaction_journey/widget"
    private val notificationChannelName = "com.personalfinance.transaction_journey/notification"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put(CACHED_ENGINE_ID, flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidgetData" -> {
                        val json = call.arguments as String
                        WidgetPrefs.savePayload(applicationContext, json)
                        WidgetHeadlessExecutor.refreshAllWidgets(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Channel yang sama dipakai DUA arah:
        // - native -> Dart: "notificationPosted", dikirim `NotificationCaptureService`
        //   saat app sedang foreground (lihat `notification_bridge.dart`).
        // - Dart -> native: cek/minta buka izin sistem "Notification access"
        //   (TIDAK BISA diminta lewat dialog runtime biasa seperti izin lain),
        //   sinkronisasi daftar paket yang sedang dipantau, dan membaca
        //   kembali daftar tersinkron untuk halaman diagnostik.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNotificationAccessEnabled" -> {
                        result.success(isNotificationAccessGranted())
                    }
                    "openNotificationAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "updateNotificationSources" -> {
                        @Suppress("UNCHECKED_CAST")
                        val packages = (call.arguments as? List<String>) ?: emptyList()
                        NotificationSourcePrefs.save(applicationContext, packages)
                        result.success(null)
                    }
                    "getWatchedPackages" -> {
                        result.success(
                            NotificationSourcePrefs.getWatchedPackages(applicationContext)
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Baca `Settings.Secure.enabled_notification_listeners` — satu-satunya
     * cara resmi mengecek apakah izin "Notification access" sudah
     * diberikan untuk aplikasi ini (tidak ada API `checkSelfPermission`
     * biasa untuk izin ini).
     */
    private fun isNotificationAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(
            applicationContext.contentResolver,
            "enabled_notification_listeners",
        )
        if (flat.isNullOrEmpty()) return false
        return flat.split(":").any { entry ->
            ComponentName.unflattenFromString(entry)?.packageName == applicationContext.packageName
        }
    }

    override fun onDestroy() {
        FlutterEngineCache.getInstance().remove(CACHED_ENGINE_ID)
        super.onDestroy()
    }

    companion object {
        const val CACHED_ENGINE_ID = "main_engine"
    }
}
