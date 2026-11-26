package com.personalfinance.transaction_journey.widget

// Lihat catatan lokasi berkas di WidgetPrefs.kt.

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.personalfinance.transaction_journey.MainActivity
import com.personalfinance.transaction_journey.R
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Widget layar utama **Ringkasan Harian** — pemasukan vs pengeluaran hari
 * berjalan + proporsinya. Murni baca-cepat (tanpa CRUD), cermin native
 * dari kartu "Hari Ini" di `Home Screen Widgets.dc.html`.
 *
 * Ikon refresh memicu re-hitung snapshot lewat engine headless (fungsional
 * penuh, bukan dekorasi) — berguna karena widget ini TIDAK auto-poll
 * (`updatePeriodMillis = 0`, lihat `widget_ringkasan_info.xml`): ia hanya
 * diperbarui saat data benar-benar berubah (didorong dari `WidgetBridge`)
 * atau saat pengguna menekan refresh secara eksplisit.
 */
class RingkasanWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateAll(context, appWidgetManager, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_REFRESH) return

        // Sama seperti `SaldoWidgetProvider.ACTION_ADJUST` — pakai engine
        // foreground yang sudah hidup dulu kalau ada (lihat dokumentasi
        // panjang di `MainActivity.kt`), headless cuma fallback.
        val cachedEngine =
            FlutterEngineCache.getInstance().get(MainActivity.CACHED_ENGINE_ID)
        if (cachedEngine != null) {
            MethodChannel(cachedEngine.dartExecutor.binaryMessenger, CHANNEL_FOREGROUND)
                .invokeMethod("refreshSnapshot", null)
            return
        }

        val pending = goAsync()
        WidgetHeadlessExecutor.run(context, "refreshSnapshot", emptyMap()) {
            pending.finish()
        }
    }

    companion object {
        const val ACTION_REFRESH =
            "com.personalfinance.transaction_journey.widget.ACTION_REFRESH_RINGKASAN"

        // HARUS identik dengan `kWidgetChannelName` di
        // `lib/core/platform/widget_bridge.dart`.
        private const val CHANNEL_FOREGROUND =
            "com.personalfinance.transaction_journey/widget"

        fun updateAll(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val payload = WidgetPrefs.readPayload(context)
            for (id in ids) {
                mgr.updateAppWidget(id, buildViews(context, payload))
            }
        }

        private fun refreshPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, RingkasanWidgetProvider::class.java)
                .setAction(ACTION_REFRESH)
            return PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun buildViews(context: Context, payload: WidgetPayload?): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_ringkasan)

            val income = payload?.todayIncomeMinor ?: 0L
            val expense = payload?.todayExpenseMinor ?: 0L
            val net = payload?.netTodayMinor ?: 0L
            val share = payload?.incomeSharePercent ?: 50

            views.setTextViewText(R.id.tv_income_amount, formatRupiah(income, forceSign = true))
            views.setTextViewText(R.id.tv_expense_amount, formatRupiah(-expense))
            views.setTextViewText(R.id.tv_net_amount, formatRupiah(net, forceSign = true))
            views.setProgressBar(R.id.pb_income_share, 100, share, false)
            views.setOnClickPendingIntent(R.id.btn_refresh, refreshPendingIntent(context))

            return views
        }
    }
}
