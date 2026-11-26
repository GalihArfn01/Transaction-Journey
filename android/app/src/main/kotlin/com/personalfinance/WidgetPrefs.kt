package com.personalfinance.transaction_journey.widget

// NOTE lokasi file: idealnya berada di
// android/app/src/main/kotlin/com/personalfinance/transaction_journey/widget/
// tapi ditaruh satu tingkat di atas (langsung di package com/personalfinance/)
// karena keterbatasan kedalaman folder pada tautan perangkat yang dipakai
// untuk membuat berkas ini. Kotlin tidak mewajibkan struktur direktori
// sama persis dengan deklarasi package (hanya konvensi IDE) — proyek tetap
// build dengan benar. Pindahkan berkas widget/*.kt ke subfolder
// `widget/` di bawah `transaction_journey/` kapan saja bila ingin rapi.

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Penyimpanan payload widget — SharedPreferences murni, TANPA package
 * home_widget (keputusan A di `widget_data_repository.dart`). File
 * "widget_prefs" terpisah dari SharedPreferences default Flutter agar
 * tidak bentrok dengan plugin `shared_preferences` bila suatu saat dipakai.
 */
object WidgetPrefs {
    private const val PREFS_NAME = "widget_prefs"
    private const val KEY_PAYLOAD = "payload_json"
    private const val KEY_STEP_PREFIX = "step_index_"
    private const val KEY_CATEGORY_PREFIX = "category_index_"

    /** Pilihan nominal langkah +/- widget Saldo, dari permintaan pengguna. */
    val STEP_VALUES_MINOR = longArrayOf(500, 1_000, 2_000, 3_000, 5_000, 10_000)

    /** Index awal (Rp 1.000) saat widget baru dipasang / belum pernah diubah. */
    private const val DEFAULT_STEP_INDEX = 1

    fun savePayload(context: Context, json: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PAYLOAD, json)
            .apply()
    }

    fun readPayload(context: Context): WidgetPayload? {
        val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_PAYLOAD, null) ?: return null
        return try {
            WidgetPayload.parse(raw)
        } catch (_: Exception) {
            null
        }
    }

    /** Index nilai langkah +/- yang sedang aktif untuk SATU instance widget
     * (per [widgetId] — tiap widget Saldo yang dipasang bisa punya langkah
     * berbeda-beda, tidak saling memengaruhi). */
    fun getStepIndex(context: Context, widgetId: Int): Int {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_STEP_PREFIX + widgetId, DEFAULT_STEP_INDEX)
    }

    /** Geser ke nilai berikutnya dalam siklus (kembali ke awal setelah nilai
     * terakhir) dan simpan. Mengembalikan index baru. */
    fun cycleStepIndex(context: Context, widgetId: Int): Int {
        val next = (getStepIndex(context, widgetId) + 1) % STEP_VALUES_MINOR.size
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_STEP_PREFIX + widgetId, next)
            .apply()
        return next
    }

    /** Bersihkan state langkah saat instance widget dilepas dari home screen. */
    fun clearStep(context: Context, widgetId: Int) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_STEP_PREFIX + widgetId)
            .apply()
    }

    /** Index kategori chip "Kategori" widget Saldo untuk SATU instance
     * (0 = "Tanpa kategori", 1..n = kategori ke-(index-1) di payload). */
    fun getCategoryIndex(context: Context, widgetId: Int): Int {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_CATEGORY_PREFIX + widgetId, 0)
    }

    /** Geser ke kategori berikutnya dalam siklus 0..count-1 dan simpan.
     * [count] = jumlah opsi TERBARU (ukuran list kategori payload + 1) —
     * dipakai sebagai modulo sehingga index tak pernah nyangkut di luar
     * range bila kategori dihapus/diubah di aplikasi. */
    fun cycleCategoryIndex(context: Context, widgetId: Int, count: Int): Int {
        val next = if (count <= 1) 0 else (getCategoryIndex(context, widgetId) + 1) % count
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_CATEGORY_PREFIX + widgetId, next)
            .apply()
        return next
    }

    /** Bersihkan state kategori saat instance widget dilepas. */
    fun clearCategory(context: Context, widgetId: Int) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_CATEGORY_PREFIX + widgetId)
            .apply()
    }
}

/** Satu kategori untuk chip "Kategori" — cermin `WidgetCategorySnapshot`
 * di sisi Dart (id + nama saja; tipe divalidasi ulang di Dart saat insert). */
data class WidgetCategory(
    val id: Int,
    val name: String,
)

/** Satu baris rekening — cermin `WidgetAccountSnapshot` di sisi Dart. */
data class WidgetAccount(
    val id: Int,
    val name: String,
    val balanceMinor: Long,
    val icon: String,
)

/** Cermin `HomeWidgetPayload` (widget_payload.dart) — sisi native, read-only. */
data class WidgetPayload(
    val balanceMinor: Long,
    val todayIncomeMinor: Long,
    val todayExpenseMinor: Long,
    val accounts: List<WidgetAccount>,
    val categories: List<WidgetCategory>,
    val hideBalance: Boolean = false,
) {
    val netTodayMinor: Long get() = todayIncomeMinor - todayExpenseMinor

    val incomeSharePercent: Int
        get() {
            val total = todayIncomeMinor + todayExpenseMinor
            if (total <= 0) return 50
            return ((todayIncomeMinor * 100.0) / total).let { it.toInt() }.coerceIn(0, 100)
        }

    companion object {
        fun parse(raw: String): WidgetPayload {
            val obj = JSONObject(raw)
            val accountsJson: JSONArray = obj.optJSONArray("accounts") ?: JSONArray()
            val accounts = mutableListOf<WidgetAccount>()
            for (i in 0 until accountsJson.length()) {
                val a = accountsJson.getJSONObject(i)
                accounts.add(
                    WidgetAccount(
                        id = a.getInt("id"),
                        name = a.getString("name"),
                        balanceMinor = a.getLong("balanceMinor"),
                        icon = a.optString("icon", "wallet"),
                    ),
                )
            }
            val categoriesJson: JSONArray = obj.optJSONArray("categories") ?: JSONArray()
            val categories = mutableListOf<WidgetCategory>()
            for (i in 0 until categoriesJson.length()) {
                val c = categoriesJson.getJSONObject(i)
                categories.add(
                    WidgetCategory(
                        id = c.getInt("id"),
                        name = c.getString("name"),
                    ),
                )
            }
            return WidgetPayload(
                balanceMinor = obj.getLong("balanceMinor"),
                todayIncomeMinor = obj.optLong("todayIncomeMinor", 0L),
                todayExpenseMinor = obj.getLong("todayExpenseMinor"),
                accounts = accounts,
                categories = categories,
                hideBalance = obj.optBoolean("hideBalance", false),
            )
        }
    }
}

/** Teks pengganti saldo saat disembunyikan — identik dgn `kHiddenBalanceText` (Dart). */
const val HIDDEN_BALANCE_TEXT = "Rp ••••••"

/** Format "Rp 124.500.000" / "-Rp 128.000" — cermin sederhana money_formatter.dart. */
fun formatRupiah(minor: Long, forceSign: Boolean = false): String {
    val sign = when {
        minor < 0 -> "-"
        forceSign && minor > 0 -> "+"
        else -> ""
    }
    val absStr = kotlin.math.abs(minor).toString()
    val grouped = StringBuilder()
    var count = 0
    for (i in absStr.length - 1 downTo 0) {
        grouped.append(absStr[i])
        count++
        if (count % 3 == 0 && i != 0) grouped.append('.')
    }
    return "${sign}Rp ${grouped.reverse()}"
}
