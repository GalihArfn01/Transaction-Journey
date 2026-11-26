package com.personalfinance.transaction_journey

import android.content.Context
import org.json.JSONArray

/**
 * Cache SharedPreferences berisi daftar packageName yang SEDANG diaktifkan
 * pengguna di halaman "Sumber Notifikasi" (lihat toggle di
 * `notification_sources_page.dart`). Disinkronkan dari Dart lewat method
 * channel `updateNotificationSources` (lihat `notification_bridge.dart` /
 * `MainActivity.kt`) setiap kali daftar sumber berubah.
 *
 * Dipakai `NotificationCaptureService` untuk membuang notifikasi dari
 * paket yang TIDAK dipantau SEBELUM membangunkan/menghubungi Dart sama
 * sekali — filter final & parsing tetap sepenuhnya di
 * `NotificationRepository.ingest` (Dart), ini cuma optimisasi murah di
 * sisi native supaya tidak setiap notifikasi (WhatsApp, game, dsb) ikut
 * memicu engine headless.
 */
object NotificationSourcePrefs {
    private const val PREFS_NAME = "notification_prefs"
    private const val KEY_PACKAGES = "watched_packages"

    fun save(context: Context, packages: List<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PACKAGES, JSONArray(packages).toString())
            .apply()
    }

    fun isWatched(context: Context, packageName: String): Boolean {
        return getWatchedPackages(context).contains(packageName)
    }

    /**
     * Daftar paket yang TERAKHIR disinkronkan dari Dart (lihat
     * `updateNotificationSources`). Dibaca halaman diagnostik
     * "Kalau otomatis tidak jalan" lewat method `getWatchedPackages`
     * untuk membandingkan "yang diaktifkan pengguna" vs "yang diketahui
     * sistem" — selisihnya berarti sync gagal/tertinggal dan perlu
     * "Sinkron ulang". Gagal baca (prefs korup) = list kosong, bukan crash.
     */
    fun getWatchedPackages(context: Context): List<String> {
        val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_PACKAGES, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            List(arr.length()) { i -> arr.getString(i) }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
