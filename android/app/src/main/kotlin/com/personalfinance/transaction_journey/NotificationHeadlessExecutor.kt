package com.personalfinance.transaction_journey

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Menjalankan SATU notifikasi masuk lewat `FlutterEngine` headless
 * terpisah — dipakai saat proses aplikasi utama TIDAK berjalan (belum ada
 * `MainActivity`/engine foreground yang bisa dipakai), sehingga tidak ada
 * jalur lain untuk memanggil `NotificationRepository.ingest` (Dart+Drift).
 *
 * Pola identik dengan `WidgetHeadlessExecutor.kt`: start engine -> jalankan
 * entry point `notificationBackgroundMain`
 * (`notificationBackgroundMain` di lib/main.dart — WAJIB di sana, lihat
 * catatan di main.dart soal resolve entry point) -> tunggu Dart memanggil
 * "ready" -> kirim SATU notifikasi -> tunggu balasan "done" -> destroy
 * engine.
 */
object NotificationHeadlessExecutor {
    private const val CHANNEL_BG = "com.personalfinance.transaction_journey/notification_bg"
    private const val ENTRYPOINT = "notificationBackgroundMain"

    fun run(context: Context, args: Map<String, Any?>) {
        val appContext = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        val mainHandler = Handler(Looper.getMainLooper())

        fun start() {
            val engine = FlutterEngine(appContext)
            // WAJIB: engine headless buatan sendiri TIDAK mewarisi
            // registrasi plugin dari MainActivity. Tanpa baris ini,
            // MethodChannel plugin (path_provider dkk) melempar
            // MissingPluginException di isolate headless: database tidak
            // bisa dibuka DAN CrashLogger ikut bisu (ia juga memakai
            // path_provider), sementara 'done' tetap terkirim — kegagalan
            // tidak terlihat di mana pun. Kasus nyata Okt 2026: engine
            // headless start bersih di logcat tapi tidak ada event yang
            // tercatat.
            io.flutter.plugins.GeneratedPluginRegistrant.registerWith(engine)
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                ENTRYPOINT,
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint)

            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_BG)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        channel.invokeMethod("notificationPosted", args)
                        result.success(null)
                    }
                    "done" -> {
                        result.success(null)
                        mainHandler.post { engine.destroy() }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        if (loader.initialized()) {
            start()
        } else {
            loader.startInitialization(appContext)
            loader.ensureInitializationCompleteAsync(appContext, null, mainHandler) { start() }
        }
    }
}
