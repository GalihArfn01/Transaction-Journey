package com.personalfinance.transaction_journey.widget

// Lihat catatan lokasi berkas di WidgetPrefs.kt.

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import com.personalfinance.transaction_journey.MainActivity
import com.personalfinance.transaction_journey.R
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Widget layar utama **Saldo** — total kekayaan + CRUD cepat (+/-) per
 * rekening. Cermin native dari kartu "Saldo" di
 * `Home Screen Widgets.dc.html`.
 *
 * Keterbatasan yang disengaja dibanding mockup (RemoteViews Android tidak
 * mendukung ini):
 * - Maksimum 2 baris rekening (sesuai `hint-placeholder-count="2"` di
 *   desain) — bukan daftar scroll.
 * - Tombol "+" (tambah rekening) dan pensil (kelola) membuka aplikasi
 *   (halaman Rekening) alih-alih dialog inline.
 * - Tap +/- menyesuaikan saldo dengan nominal LANGKAH yang sedang aktif
 *   (chip "Langkah tap +/-" di bawah saldo total) — bukan input bebas,
 *   melainkan siklus 6 nominal tetap: [WidgetPrefs.STEP_VALUES_MINOR].
 *   RemoteViews tidak mendukung keyboard/input teks di homescreen widget,
 *   jadi ini kompromi paling dekat dengan "Sesuaikan Tunai" di mockup.
 * - Chip "Kategori" di samping chip nominal: siklus "Tanpa kategori" ->
 *   kategori aktif (dari payload). Kategori terpilih dipakai transaksi
 *   hasil tap +/- BILA tipenya cocok arah transaksi (+ = income,
 *   - = expense); validasi tipe terjadi di Dart (`adjustBalance`).
 */
class SaldoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateAll(context, appWidgetManager, appWidgetIds)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        appWidgetIds.forEach {
            WidgetPrefs.clearStep(context, it)
            WidgetPrefs.clearCategory(context, it)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        when (intent.action) {
            ACTION_CYCLE_STEP -> {
                val widgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID,
                )
                if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
                WidgetPrefs.cycleStepIndex(context, widgetId)
                // Perubahan langkah murni state lokal (tanpa DB) — cukup
                // gambar ulang instance ini saja, tidak perlu engine headless.
                AppWidgetManager.getInstance(context).updateAppWidget(
                    widgetId,
                    buildViews(context, WidgetPrefs.readPayload(context), widgetId),
                )
            }
            ACTION_CYCLE_CATEGORY -> {
                val widgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID,
                )
                if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
                // Modulo memakai jumlah opsi TERBARU agar index tidak
                // nyangkut di luar range bila kategori berubah di aplikasi.
                val count = (WidgetPrefs.readPayload(context)?.categories?.size ?: 0) + 1
                WidgetPrefs.cycleCategoryIndex(context, widgetId, count)
                AppWidgetManager.getInstance(context).updateAppWidget(
                    widgetId,
                    buildViews(context, WidgetPrefs.readPayload(context), widgetId),
                )
            }
            ACTION_ADJUST -> {
                val accountId = intent.getIntExtra(EXTRA_ACCOUNT_ID, -1)
                val delta = intent.getLongExtra(EXTRA_DELTA_MINOR, 0L)
                val categoryId = intent.getIntExtra(EXTRA_CATEGORY_ID, -1)
                if (accountId < 0 || delta == 0L) return
                val args = mutableMapOf<String, Any?>(
                    "accountId" to accountId,
                    "deltaMinor" to delta,
                )
                if (categoryId >= 0) args["categoryId"] = categoryId

                // PENTING: cek dulu apakah aplikasi (engine foreground)
                // masih hidup — lihat dokumentasi panjang di
                // `MainActivity.kt` soal bug "app tidak menanggapi".
                // Kalau ADA, pakai channel yang sama (didengarkan
                // `WidgetBridge` di Dart) lewat engine yang SUDAH
                // berjalan — TIDAK membuka koneksi database kedua sama
                // sekali, jadi tidak ada risiko kontensi/ANR, dan hasilnya
                // instan (tidak perlu start-up engine baru). Headless
                // HANYA dipakai sebagai fallback saat aplikasi benar-benar
                // tidak berjalan.
                val cachedEngine =
                    FlutterEngineCache.getInstance().get(MainActivity.CACHED_ENGINE_ID)
                if (cachedEngine != null) {
                    MethodChannel(cachedEngine.dartExecutor.binaryMessenger, CHANNEL_FOREGROUND)
                        .invokeMethod("adjustBalance", args)
                    return
                }

                val pending = goAsync()
                WidgetHeadlessExecutor.run(
                    context,
                    "adjustBalance",
                    args,
                ) {
                    pending.finish()
                }
            }
        }
    }

    companion object {
        private const val PKG = "com.personalfinance.transaction_journey"
        const val ACTION_ADJUST = "$PKG.widget.ACTION_ADJUST_BALANCE"
        const val ACTION_CYCLE_STEP = "$PKG.widget.ACTION_CYCLE_STEP"
        const val ACTION_CYCLE_CATEGORY = "$PKG.widget.ACTION_CYCLE_CATEGORY"
        const val EXTRA_ACCOUNT_ID = "$PKG.widget.EXTRA_ACCOUNT_ID"
        const val EXTRA_DELTA_MINOR = "$PKG.widget.EXTRA_DELTA_MINOR"
        const val EXTRA_CATEGORY_ID = "$PKG.widget.EXTRA_CATEGORY_ID"

        // HARUS identik dengan `kWidgetChannelName` di
        // `lib/core/platform/widget_bridge.dart` — itu channel yang
        // didengarkan `WidgetBridge._handleNativeCall` selama aplikasi
        // foreground berjalan.
        private const val CHANNEL_FOREGROUND = "$PKG/widget"

        fun updateAll(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val payload = WidgetPrefs.readPayload(context)
            for (id in ids) {
                mgr.updateAppWidget(id, buildViews(context, payload, id))
            }
        }

        private fun openAppPendingIntent(context: Context, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun adjustPendingIntent(
            context: Context,
            accountId: Int,
            deltaMinor: Long,
            categoryIndex: Int,
            categoryId: Int?,
        ): PendingIntent {
            val intent = Intent(context, SaldoWidgetProvider::class.java)
                .setAction(ACTION_ADJUST)
                .putExtra(EXTRA_ACCOUNT_ID, accountId)
                .putExtra(EXTRA_DELTA_MINOR, deltaMinor)
            if (categoryId != null) intent.putExtra(EXTRA_CATEGORY_ID, categoryId)
            // Request code unik per rekening+kategori+arah agar PendingIntent
            // tidak saling menimpa (extras TIDAK ikut dicocokkan sistem).
            // Memakai categoryIndex (kecil, 0..~12), bukan categoryId asli.
            val requestCode = accountId * 1000 + categoryIndex * 10 +
                if (deltaMinor > 0) 1 else 0
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun cyclePendingIntent(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, SaldoWidgetProvider::class.java)
                .setAction(ACTION_CYCLE_STEP)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            // Offset besar agar request code tidak pernah bentrok dengan
            // adjustPendingIntent (accountId*1000+catIdx*10+arah) atau
            // openAppPendingIntent (widgetId*10+n).
            return PendingIntent.getBroadcast(
                context,
                1_000_000 + widgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun cycleCategoryPendingIntent(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, SaldoWidgetProvider::class.java)
                .setAction(ACTION_CYCLE_CATEGORY)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            return PendingIntent.getBroadcast(
                context,
                2_000_000 + widgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun iconRes(key: String): Int = when (key) {
            "bank" -> R.drawable.ic_widget_bank
            "ewallet" -> R.drawable.ic_widget_ewallet
            "other" -> R.drawable.ic_widget_other
            else -> R.drawable.ic_widget_wallet
        }

        private fun bindRow(
            views: RemoteViews,
            rowId: Int,
            iconId: Int,
            nameId: Int,
            balanceId: Int,
            minusId: Int,
            plusId: Int,
            context: Context,
            account: WidgetAccount?,
            hideBalance: Boolean,
            stepMinor: Long,
            categoryIndex: Int,
            categoryId: Int?,
        ) {
            if (account == null) {
                views.setViewVisibility(rowId, View.GONE)
                return
            }
            views.setViewVisibility(rowId, View.VISIBLE)
            views.setImageViewResource(iconId, iconRes(account.icon))
            views.setTextViewText(nameId, account.name)
            views.setTextViewText(
                balanceId,
                if (hideBalance) HIDDEN_BALANCE_TEXT else formatRupiah(account.balanceMinor),
            )
            views.setOnClickPendingIntent(
                minusId,
                adjustPendingIntent(context, account.id, -stepMinor, categoryIndex, categoryId),
            )
            views.setOnClickPendingIntent(
                plusId,
                adjustPendingIntent(context, account.id, stepMinor, categoryIndex, categoryId),
            )
        }

        private fun buildViews(context: Context, payload: WidgetPayload?, widgetId: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_saldo)

            views.setTextViewText(
                R.id.tv_saldo_balance,
                if (payload?.hideBalance == true) HIDDEN_BALANCE_TEXT
                else formatRupiah(payload?.balanceMinor ?: 0L),
            )
            views.setOnClickPendingIntent(
                R.id.btn_saldo_add,
                openAppPendingIntent(context, widgetId * 10 + 2),
            )
            views.setOnClickPendingIntent(
                R.id.btn_saldo_edit,
                openAppPendingIntent(context, widgetId * 10 + 3),
            )

            val stepIndex = WidgetPrefs.getStepIndex(context, widgetId)
            val stepMinor = WidgetPrefs.STEP_VALUES_MINOR[stepIndex]
            views.setTextViewText(R.id.tv_step_chip, formatRupiah(stepMinor))
            views.setOnClickPendingIntent(R.id.tv_step_chip, cyclePendingIntent(context, widgetId))

            // Chip kategori: index 0 = "Tanpa kategori", sisanya nama
            // kategori dari payload. Index dijepit ke range TERBARU agar
            // tidak out-of-bounds bila kategori berkurang sejak dipilih.
            val categories = payload?.categories.orEmpty()
            val categoryCount = categories.size + 1
            val categoryIndex = WidgetPrefs.getCategoryIndex(context, widgetId)
                .let { if (it >= categoryCount) 0 else it }
            val selectedCategory: WidgetCategory? =
                if (categoryIndex == 0) null else categories.getOrNull(categoryIndex - 1)
            views.setTextViewText(
                R.id.tv_category_chip,
                selectedCategory?.name ?: "Tanpa kategori",
            )
            views.setOnClickPendingIntent(
                R.id.tv_category_chip,
                cycleCategoryPendingIntent(context, widgetId),
            )

            val accounts = payload?.accounts.orEmpty()
            bindRow(
                views, R.id.row_account_1, R.id.iv_account_1_icon, R.id.tv_account_1_name,
                R.id.tv_account_1_balance, R.id.btn_account_1_minus, R.id.btn_account_1_plus,
                context, accounts.getOrNull(0), payload?.hideBalance == true, stepMinor, categoryIndex,
                selectedCategory?.id,
            )
            bindRow(
                views, R.id.row_account_2, R.id.iv_account_2_icon, R.id.tv_account_2_name,
                R.id.tv_account_2_balance, R.id.btn_account_2_minus, R.id.btn_account_2_plus,
                context, accounts.getOrNull(1), payload?.hideBalance == true, stepMinor, categoryIndex,
                selectedCategory?.id,
            )

            return views
        }
    }
}
