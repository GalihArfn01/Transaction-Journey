package com.personalfinance.transaction_journey

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * `NotificationListenerService` — komponen native yang SEBELUMNYA TIDAK
 * ADA sama sekali di proyek ini. Inilah sebabnya fitur "baca notifikasi
 * otomatis" terasa diam tanpa error: pipeline Dart-nya
 * (`NotificationRepository.ingest`, parser, halaman "Sumber Notifikasi")
 * sudah lengkap, tapi tidak ada apa pun yang benar-benar menangkap
 * notifikasi sistem dan memanggilnya.
 *
 * Didaftarkan di `AndroidManifest.xml` dengan
 * `BIND_NOTIFICATION_LISTENER_SERVICE`. Android HANYA menjalankan service
 * ini kalau pengguna sudah memberi izin manual lewat
 * Settings > Notification access (tidak bisa diminta lewat dialog runtime
 * biasa) — lihat `NotificationBridge.isAccessEnabled`/`openAccessSettings`
 * di sisi Dart dan tombol terkait di `notification_sources_page.dart`.
 *
 * Alur tiap notifikasi masuk:
 * 1. Buang kalau dari paket aplikasi ini sendiri, atau paket yang tidak
 *    ada di [NotificationSourcePrefs] (belum tentu dipantau/diaktifkan).
 * 2. Kalau ada Flutter engine foreground yang hidup (app sedang dibuka —
 *    lihat `FlutterEngineCache`/`MainActivity.kt`), kirim langsung lewat
 *    channel foreground (`notification_bridge.dart`).
 * 3. Kalau tidak, jalankan `NotificationHeadlessExecutor` (engine headless
 *    terpisah, sama pola dengan widget).
 *
 * CATATAN [onListenerConnected]: `onNotificationPosted` SAJA hanya
 * menangkap notifikasi yang masuk SETELAH service ini aktif — Android
 * TIDAK PERNAH mengirim ulang notifikasi yang sudah ada sebelumnya ke
 * listener manapun (keterbatasan platform, bukan bug di sini). Tapi kalau
 * ada notifikasi bank yang MASIH nampang di tray (belum di-swipe/dihapus
 * pengguna) saat service ini baru tersambung — misalnya baru saja
 * mengaktifkan izin "Notification access", atau proses app baru
 * dijalankan ulang oleh sistem — itu SEBELUMNYA hilang begitu saja karena
 * tidak ada apa pun yang menariknya. [onListenerConnected] menutup celah
 * itu dengan memanggil `getActiveNotifications()` (API resmi
 * `NotificationListenerService` untuk notifikasi yang MASIH AKTIF/belum
 * dibersihkan sistem) dan memprosesnya lewat jalur yang sama persis
 * dengan notifikasi baru. Notifikasi yang SUDAH di-swipe/dihapus SEBELUM
 * service tersambung tetap tidak bisa diambil lagi oleh siapa pun — itu
 * memang tidak lagi ada di sistem untuk diambil.
 *
 * Ini bisa berjalan berkali-kali (tiap kali service reconnect, bukan cuma
 * sekali seumur hidup install) sehingga notifikasi aktif yang sama bisa
 * "diproses ulang" lebih dari sekali — ini AMAN dan disengaja: dedup
 * final tetap di `NotificationRepository.ingest` (Dart) lewat
 * `notificationFingerprint` (package+nominal+jenis+tanggal+merchant), jadi
 * notifikasi yang sudah pernah masuk tidak akan tercatat dobel.
 */
class NotificationCaptureService : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        val active = try {
            activeNotifications
        } catch (_: Exception) {
            null
        } ?: return
        for (sbn in active) {
            processNotification(sbn)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        processNotification(sbn)
    }

    private fun processNotification(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        if (pkg == applicationContext.packageName) return
        if (!NotificationSourcePrefs.isWatched(applicationContext, pkg)) return

        val extras = sbn.notification.extras
        val title = extras.getCharSequence("android.title")?.toString()
        val text = (extras.getCharSequence("android.text")
            ?: extras.getCharSequence("android.bigText"))?.toString()

        val args = mapOf(
            "packageName" to pkg,
            "title" to title,
            "text" to text,
            "postedAtMillis" to sbn.postTime,
        )

        val cachedEngine = FlutterEngineCache.getInstance().get(MainActivity.CACHED_ENGINE_ID)
        if (cachedEngine != null) {
            MethodChannel(cachedEngine.dartExecutor.binaryMessenger, CHANNEL_FOREGROUND)
                .invokeMethod("notificationPosted", args)
            return
        }

        NotificationHeadlessExecutor.run(applicationContext, args)
    }

    companion object {
        private const val CHANNEL_FOREGROUND = "com.personalfinance.transaction_journey/notification"
    }
}
