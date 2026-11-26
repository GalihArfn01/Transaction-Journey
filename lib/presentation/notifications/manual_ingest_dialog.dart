import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/notification_bridge.dart';
import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../domain/model/enums.dart';
import 'providers.dart';

/// Dialog TRIGGER MANUAL ingest notifikasi — fallback antisipasi bila jalur
/// otomatis (`NotificationCaptureService` native) tidak berjalan di perangkat
/// pengguna (izin sistem belum diberikan, service dimatikan vendor HP,
/// paket tidak cocok, dsb).
///
/// Memakai pipeline yang SAMA PERSIS dengan jalur otomatis
/// (`NotificationRepository.ingest`), jadi hasil uji di sini valid untuk
/// diagnosis: kalau uji manual tercatat tapi notifikasi asli tidak pernah
/// masuk, masalahnya di sisi native/izin — bukan di parser/repository.
/// Kalau uji manual pun gagal/ignored, masalahnya di sumber/parser/threshold.
///
/// Dipakai dari halaman Sumber Notifikasi DAN halaman Notifikasi.
Future<void> showManualIngestDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final AppDatabase db = ref.read(appDatabaseProvider);
  final List<NotificationSource> sources =
      await db.notificationSourceDao.watchAll().first;
  if (!context.mounted) return;
  if (sources.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Belum ada sumber notifikasi terdaftar')),
    );
    return;
  }

  NotificationSource selected = sources.firstWhere(
    (NotificationSource s) => s.enabled,
    orElse: () => sources.first,
  );
  final TextEditingController titleCtrl =
      TextEditingController(text: 'Transaksi ${selected.appName}');
  final TextEditingController bodyCtrl = TextEditingController(
    text: 'Pembayaran QRIS Rp50.000 di KOPI QA berhasil',
  );

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          return AlertDialog(
            title: const Text('Uji manual baca notifikasi'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Mensimulasikan satu notifikasi masuk lewat pipeline '
                    'yang sama dengan jalur otomatis.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<NotificationSource>(
                    key: const Key('manual_ingest_source'),
                    value: selected,
                    items: <DropdownMenuItem<NotificationSource>>[
                      for (final NotificationSource s in sources)
                        DropdownMenuItem<NotificationSource>(
                          value: s,
                          child: Text(
                            '${s.appName}${s.enabled ? '' : ' (nonaktif)'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (NotificationSource? v) {
                      if (v != null) setState(() => selected = v);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Sumber (paket pengirim)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('manual_ingest_title'),
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Judul notifikasi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('manual_ingest_body'),
                    controller: bodyCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Isi notifikasi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                key: const Key('manual_ingest_send'),
                onPressed: () async {
                  final String title = titleCtrl.text;
                  final String body = bodyCtrl.text;
                  Navigator.of(ctx).pop();
                  try {
                    final result = await ref
                        .read(notificationRepositoryProvider)
                        .ingest(
                          packageName: selected.packageName,
                          title: title.isEmpty ? null : title,
                          body: body.isEmpty ? null : body,
                          postedAt: DateTime.now(),
                        );
                    // Sinkron ulang juga supaya native tahu paket yang
                    // baru diuji (best-effort, abaikan gagal).
                    try {
                      await NotificationBridge.instance.syncSourcesNow();
                    } catch (_) {}
                    if (!context.mounted) return;
                    ref.invalidate(notificationEventsProvider);
                    ref.invalidate(pendingReviewProvider);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Hasil uji: ${result.status.label}'
                          '${result.errorText == null ? '' : ' — ${result.errorText}'}',
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Uji manual gagal: $e')),
                    );
                  }
                },
                child: const Text('Kirim uji'),
              ),
            ],
          );
        },
      );
    },
  );

  titleCtrl.dispose();
  bodyCtrl.dispose();
}
