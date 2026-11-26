import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/result.dart' show Failure;
import '../../core/utils/money_formatter.dart';
import '../../data/datasource/app_database.dart';
import '../../domain/model/enums.dart';
import '../../core/platform/platform_caps.dart';
import '../shared/widgets/empty_state.dart';
import '../shared/widgets/colorful_3d_chip.dart';
import 'accept_pending_sheet.dart';
import 'manual_ingest_dialog.dart';
import 'notification_troubleshoot_page.dart';
import 'providers.dart';
import '../shared/widgets/gradient_app_bar.dart';

/// Halaman Notifikasi: daftar deteksi + filter status.
///
/// SEBELUMNYA halaman ini murni baca-saja (`_EventTile` cuma `ListTile`
/// tanpa aksi apa pun) — aksi "Terima"/"Abaikan" untuk event berstatus
/// `pending` ternyata SUDAH dibuat di `PendingReviewPage`
/// (`pending_review_page.dart`), tapi halaman itu tidak pernah dihubungkan
/// ke navigasi manapun (tidak ada `Navigator.push` ke situ di seluruh
/// proyek) — jadi dari sudut pandang pengguna tombolnya "hilang" padahal
/// sudah ada di kode, cuma tidak terjangkau. Daripada menambah satu lagi
/// halaman terpisah yang harus diingat-ingat, aksi Terima/Abaikan
/// (memakai repository method yang sama:
/// `notificationRepositoryProvider.acceptPending`/`ignorePending`)
/// dipindah langsung ke sini, muncul hanya untuk event berstatus
/// `pending` — supaya pengguna cukup satu halaman Notifikasi untuk lihat
/// SEKALIGUS bertindak.
///
/// Tombol Terima MEMBUKA bottom-sheet (`accept_pending_sheet.dart`) untuk
/// memilih kategori + rekening sebelum menyimpan — bukan lagi hardcoded
/// kategori 'Lainnya' + rekening pertama.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Housekeeping sekali per buka halaman: buang notifikasi yang sudah
    // selesai (disetujui/diabaikan) yang lebih tua dari retensi supaya
    // daftar tidak menumpuk. Stream drift memperbarui tampilan sendiri
    // setelah delete, jadi tidak perlu invalidate manual.
    unawaited(_purgeResolved());
  }

  Future<void> _purgeResolved() async {
    try {
      await ref
          .read(notificationRepositoryProvider)
          .purgeResolvedNotifications();
    } catch (_) {
      // Housekeeping best-effort: kegagalan (mis. DB terkunci) tidak boleh
      // mengganggu tampilan daftar.
    }
  }

  Future<void> _accept(
    BuildContext context,
    NotificationEvent event,
  ) async {
    // Pilih kategori + rekening dulu (default = perilaku lama: 'Lainnya' +
    // rekening pertama). Batal = tidak terjadi apa-apa, kartu tetap pending.
    final AcceptPendingChoice? choice =
        await showAcceptPendingSheet(context, ref, event);
    if (choice == null || !context.mounted) return;
    final result = await ref.read(notificationRepositoryProvider).acceptPending(
          event.id,
          categoryId: choice.category.id,
          accountId: choice.account.id,
        );
    ref.invalidate(notificationEventsProvider);
    ref.invalidate(pendingReviewProvider);
    final String message = result.isSuccess
        ? 'Tersimpan ke ${choice.category.name}'
        : (result as Failure<int>).firstMessage;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _ignore(
    BuildContext context,
    int eventId,
  ) async {
    await ref.read(notificationRepositoryProvider).ignorePending(eventId);
    ref.invalidate(notificationEventsProvider);
    ref.invalidate(pendingReviewProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notifikasi diabaikan')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<NotificationEvent>> state =
        ref.watch(notificationEventsProvider);
    final NotificationEventStatus? filter =
        ref.watch(notificationFilterProvider);

    return Scaffold(
      // Aksi "Uji manual": trigger manual ingest (fallback bila jalur
      // otomatis tidak berjalan) — dialog dipakai bersama dengan halaman
      // Sumber Notifikasi, lihat `manual_ingest_dialog.dart`.
      appBar: GradientAppBar(
        title: 'Notifikasi',
        actions: <Widget>[
          IconButton(
            key: const Key('notif_troubleshoot_action'),
            tooltip: 'Kenapa otomatis tidak jalan?',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationTroubleshootPage(),
              ),
            ),
          ),
          IconButton(
            key: const Key('notif_manual_test_action'),
            tooltip: 'Uji manual',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => showManualIngestDialog(context, ref),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: <Widget>[
                _filterChip(
                  context,
                  label: 'Semua',
                  value: null,
                  selected: filter == null,
                ),
                for (final NotificationEventStatus s
                    in NotificationEventStatus.values)
                  _filterChip(
                    context,
                    label: s.label,
                    value: s,
                    selected: filter == s,
                  ),
              ],
            ),
          ),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Gagal memuat',
                message: '$e',
              ),
              data: (List<NotificationEvent> events) {
                if (events.isEmpty) {
                  // iOS/dll: deteksi otomatis memang tidak ada — arahkan ke
                  // jalur yang berfungsi (ikon Uji manual di kanan atas).
                  return EmptyState(
                    icon: Icons.notifications_none,
                    title: 'Belum ada notifikasi',
                    message: supportsNotificationAutoRead
                        ? 'Deteksi transaksi dari notifikasi aplikasi bank '
                            'akan tampil di sini.'
                        : 'Deteksi otomatis tidak tersedia '
                            '$platformLabel. Ketuk ikon Uji manual di kanan '
                            'atas untuk mencatat dari notifikasi bank.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: events.length,
                  itemBuilder: (BuildContext _, int index) {
                    final NotificationEvent event = events[index];
                    final bool isPending =
                        event.status == NotificationEventStatus.pending;
                    return _EventTile(
                      event,
                      onAccept:
                          isPending ? () => _accept(context, event) : null,
                      onIgnore:
                          isPending ? () => _ignore(context, event.id) : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Filter status versi 3D senada tema (lihat `Colorful3DChip`) — ikon
  /// mengikuti arti status, warna mengikuti primary tema. Key & perilaku
  /// dipertahankan untuk test.
  static const Map<NotificationEventStatus, IconData> _statusIcons =
      <NotificationEventStatus, IconData>{
    NotificationEventStatus.recorded: Icons.check_circle_outline,
    NotificationEventStatus.pending: Icons.hourglass_top,
    NotificationEventStatus.ignored: Icons.block_outlined,
    NotificationEventStatus.duplicate: Icons.copy_all_outlined,
    NotificationEventStatus.failed: Icons.error_outline,
  };

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required NotificationEventStatus? value,
    required bool selected,
  }) {
    final String keyName = value?.name ?? 'all';
    return Padding(
      padding: const EdgeInsets.only(right: 10, bottom: 6),
      child: Colorful3DChip(
        key: Key('notif_filter_$keyName'),
        label: label,
        icon: value == null
            ? Icons.select_all_outlined
            : _statusIcons[value],
        selected: selected,
        onTap: () =>
            ref.read(notificationFilterProvider.notifier).select(value),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.event, {this.onAccept, this.onIgnore});

  final NotificationEvent event;

  /// Non-null hanya dikirim untuk event berstatus `pending` — lihat
  /// pemanggil di `_NotificationsPageState.build`.
  final VoidCallback? onAccept;
  final VoidCallback? onIgnore;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (event.status) {
      NotificationEventStatus.recorded => (
          Icons.check_circle_outline,
          Colors.green
        ),
      NotificationEventStatus.pending => (Icons.hourglass_top, Colors.orange),
      NotificationEventStatus.ignored => (
          Icons.block_outlined,
          scheme.onSurfaceVariant
        ),
      NotificationEventStatus.duplicate => (
          Icons.copy_all_outlined,
          scheme.secondary
        ),
      NotificationEventStatus.failed => (Icons.error_outline, scheme.error),
    };

    final String amountText = event.amountMinor == null
        ? '-'
        : MoneyFormatter.format(event.amountMinor!);

    return Card(
      key: Key('notif_tile_${event.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            leading: Icon(icon, color: color),
            title: Text(
              event.merchant ?? event.detectedType.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            // Satu baris ringkas: nominal · status · waktu. Detail parser
            // (keyakinan dll) tidak ditampilkan lagi di kartu — errorText
            // tetap tampil untuk event failed/ignored yang beralasan.
            subtitle: Text(
              '$amountText · ${event.status.label} · '
              '${DateFormat('dd/MM/yy HH:mm').format(event.postedAt)}'
              '${event.errorText == null ? '' : '\n${event.errorText}'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onAccept != null && onIgnore != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('notif_ignore_${event.id}'),
                      onPressed: onIgnore,
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('Abaikan'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: Key('notif_accept_${event.id}'),
                      onPressed: onAccept,
                      icon: const Icon(Icons.check),
                      label: const Text('Terima'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
