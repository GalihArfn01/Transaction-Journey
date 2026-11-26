package com.personalfinance.transaction_journey.widget

// Lihat catatan lokasi berkas di WidgetPrefs.kt.

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Menjalankan SATU perintah widget (`adjustBalance` / `refreshSnapshot`)
 * lewat `FlutterEngine` headless terpisah — dipakai saat proses aplikasi
 * utama TIDAK berjalan, sehingga tidak ada `MainActivity`/engine foreground
 * yang bisa dipakai untuk menjalankan query Dart+Drift.
 *
 * Alur: start engine -> jalankan entry point `widgetBackgroundMain`
 * (`widgetBackgroundMain` di lib/main.dart — WAJIB di sana, lihat catatan
 * di main.dart soal resolve entry point) -> tunggu Dart memanggil
 * "ready" -> kirim satu perintah -> tunggu balasan "updateWidgetData"
 * (payload JSON terbaru) -> simpan ke [WidgetPrefs] -> refresh semua
 * instance widget -> destroy engine.
 *
 * Engine baru dibuat setiap panggilan (bukan disimpan di cache) karena
 * frekuensi tap widget sangat rendah — kesederhanaan & isolasi lebih
 * penting daripada latensi ~200-400ms start-up engine di sini.
 */
object WidgetHeadlessExecutor {
    private const val CHANNEL_BG = "com.personalfinance.transaction_journey/widget_bg"
    private const val ENTRYPOINT = "widgetBackgroundMain"

    fun run(context: Context, method: String, args: Map<String, Any?>, onFinished: () -> Unit) {
        val appContext = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        val mainHandler = Handler(Looper.getMainLooper())

        fun start() {
            val engine = FlutterEngine(appContext)
            // WAJIB: lihat catatan yang sama di
            // `NotificationHeadlessExecutor.kt` — tanpa registrasi plugin,
            // isolate headless tidak bisa membuka database (path_provider
            // MissingPluginException) dan gagal TANPA JEJAK.
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
                        channel.invokeMethod(method, args)
                        result.success(null)
                    }
                    "updateWidgetData" -> {
                        val json = call.arguments as String
                        WidgetPrefs.savePayload(appContext, json)
                        refreshAllWidgets(appContext)
                        result.success(null)
                        mainHandler.post {
                            engine.destroy()
                            onFinished()
                        }
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

    /** Broadcast update ke semua instance kedua widget sekaligus. */
    fun refreshAllWidgets(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val saldoIds = mgr.getAppWidgetIds(ComponentName(context, SaldoWidgetProvider::class.java))
        if (saldoIds.isNotEmpty()) {
            SaldoWidgetProvider.updateAll(context, mgr, saldoIds)
        }
        val ringkasanIds =
            mgr.getAppWidgetIds(ComponentName(context, RingkasanWidgetProvider::class.java))
        if (ringkasanIds.isNotEmpty()) {
            RingkasanWidgetProvider.updateAll(context, mgr, ringkasanIds)
        }
    }
}
