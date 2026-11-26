import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/result.dart' show Failure;
import '../../core/utils/money_formatter.dart';
import '../../data/datasource/app_database.dart';
import '../../domain/model/enums.dart';
import '../shared/widgets/empty_state.dart';
import '../shared/widgets/animations.dart';
import 'accept_pending_sheet.dart';
import 'providers.dart';

/// Halaman review event pending: Terima (pilih kategori + rekening lewat
/// bottom-sheet, lalu simpan) atau Abaikan.
///
/// Daftar kartunya memakai `AnimatedList`: begitu sebuah event diterima
/// atau diabaikan, kartunya MELAYANG KELUAR (geser ke kanan + memudar +
/// tingginya mengecil) alih-alih hilang mendadak saat stream drift
/// ter-refresh.
class PendingReviewPage extends ConsumerWidget {
  const PendingReviewPage({super.key});

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    NotificationEvent event,
  ) async {
    // Sheet dulu (default = perilaku lama). Batal = kartu tetap di daftar
    // — karena itu kartu di sini TIDAK dilepas optimistis untuk Terima
    // (lihat `_PendingList._card`); kartu melayang keluar lewat animasi
    // sinkronisasi stream setelah DB berubah.
    final AcceptPendingChoice? choice =
        await showAcceptPendingSheet(context, ref, event);
    if (choice == null || !context.mounted) return;
    final result =
        await ref.read(notificationRepositoryProvider).acceptPending(
              event.id,
              categoryId: choice.category.id,
              accountId: choice.account.id,
            );
    ref.invalidate(pendingReviewProvider);
    ref.invalidate(notificationEventsProvider);
    final String message = result.isSuccess
        ? 'Tersimpan ke ${choice.category.name}'
        : (result as Failure<int>).firstMessage;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _ignore(BuildContext context, WidgetRef ref, int eventId) async {
    await ref.read(notificationRepositoryProvider).ignorePending(eventId);
    ref.invalidate(pendingReviewProvider);
    ref.invalidate(notificationEventsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notifikasi diabaikan')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<NotificationEvent>> state =
        ref.watch(pendingReviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Menunggu Review')),
      body: state.when(
        // Daftar LAMA tetap tampil selama pemuatan ulang setelah
        // Terima/Abaikan: kartu yang sedang melayang keluar tidak boleh
        // terpotong spinner (spinner hanya untuk pemuatan pertama).
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Gagal memuat',
          message: '$e',
        ),
        data: (List<NotificationEvent> events) => _PendingList(
          events: events,
          onAccept: (NotificationEvent event) =>
              _accept(context, ref, event),
          onIgnore: (NotificationEvent event) =>
              _ignore(context, ref, event.id),
        ),
      ),
    );
  }
}

/// Daftar kartu pending dengan animasi keluar/masuk (`AnimatedList`).
///
/// Sumber data tetap stream drift ([pendingReviewProvider]); widget ini
/// menyimpan SALINAN lokal `_items` supaya kartu bisa melayang keluar
/// lebih dulu (optimistis, animasi tidak menunggu DB) lalu menyinkronkan
/// diri saat data baru tiba — termasuk menyisipkan kembali kartu bila aksi
/// Terima/Abaikan ternyata GAGAL (event tetap pending di DB).
class _PendingList extends StatefulWidget {
  const _PendingList({
    required this.events,
    required this.onAccept,
    required this.onIgnore,
  });

  final List<NotificationEvent> events;
  final void Function(NotificationEvent event) onAccept;
  final void Function(NotificationEvent event) onIgnore;

  @override
  State<_PendingList> createState() => _PendingListState();
}

class _PendingListState extends State<_PendingList> {
  /// Durasi satu kartu melayang keluar / masuk.
  static const Duration _itemAnimation = Duration(milliseconds: 280);

  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  /// Salinan lokal daftar — isinya dimutasi di tempat (tambah/buang),
  /// bukan diganti objeknya.
  late final List<NotificationEvent> _items =
      List<NotificationEvent>.of(widget.events);

  @override
  void didUpdateWidget(_PendingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromSource();
  }

  /// Samakan daftar lokal dengan sumber data: buang yang hilang (dengan
  /// animasi), perbarui data yang masih ada, sisipkan yang baru.
  void _syncFromSource() {
    final List<NotificationEvent> source = widget.events;
    final Map<int, NotificationEvent> byId = <int, NotificationEvent>{
      for (final NotificationEvent event in source) event.id: event,
    };

    for (int i = _items.length - 1; i >= 0; i--) {
      if (!byId.containsKey(_items[i].id)) _removeAt(i);
    }
    for (int i = 0; i < _items.length; i++) {
      final NotificationEvent? latest = byId[_items[i].id];
      if (latest != null) _items[i] = latest;
    }

    final Set<int> known = <int>{
      for (final NotificationEvent event in _items) event.id,
    };
    for (int i = 0; i < source.length; i++) {
      if (known.contains(source[i].id)) continue;
      final int at = i <= _items.length ? i : _items.length;
      _items.insert(at, source[i]);
      _listKey.currentState?.insertItem(at, duration: _itemAnimation);
    }
  }

  void _removeAt(int index) {
    final NotificationEvent removed = _items.removeAt(index);
    // removedItemBuilder dipanggil dengan data yang DIINGAT di sini:
    // kartunya sudah tidak ada lagi di `_items`.
    _listKey.currentState?.removeItem(
      index,
      (BuildContext context, Animation<double> animation) =>
          _buildLeaving(removed, animation),
      duration: _itemAnimation,
    );
  }

  /// Terima/Abaikan: kartu langsung melayang keluar, aksi DB berjalan di
  /// belakang. Bila aksinya gagal, stream tetap memuat event ini sehingga
  /// kartunya tersisip kembali oleh [_syncFromSource].
  void _handle(int id, void Function(NotificationEvent event) action) {
    final int index = _items.indexWhere((NotificationEvent e) => e.id == id);
    if (index < 0) return;
    final NotificationEvent event = _items[index];
    setState(() => _removeAt(index));
    action(event);
  }

  Widget _card(NotificationEvent event) => _PendingCard(
        // Terima TIDAK lewat `_handle` (lepas optimistis): sheet bisa
        // dibatalkan, dan pembatalan harus membiarkan kartu tetap di
        // tempat. Setelah konfirmasi + DB berubah, kartu keluar lewat
        // animasi `_syncFromSource` seperti biasa.
        event: event,
        onAccept: () => widget.onAccept(event),
        onIgnore: () => _handle(event.id, widget.onIgnore),
      );

  /// Kartu yang sedang keluar: geser ke kanan + memudar + tinggi
  /// mengecil. Animation bawaan AnimatedList bernilai 1 -> 0 saat keluar,
  /// jadi pasangan Tween-nya sengaja dibalik (mulai dari kanan).
  Widget _buildLeaving(NotificationEvent event, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.2, 0),
            end: Offset.zero,
          ).animate(animation),
          child: _card(event),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Empty state diletakkan di BELAKANG daftar (Stack): saat kartu
    // TERAKHIR melayang keluar, AnimatedList masih di pohon sehingga
    // animasinya utuh, dan pesan "tidak ada yang perlu direview" sudah
    // siap muncul di bawahnya.
    return Stack(
      children: <Widget>[
        if (_items.isEmpty)
          const EmptyState(
            icon: Icons.task_alt,
            title: 'Tidak ada yang perlu direview',
            message: 'Deteksi ber-keyakinan sedang akan tampil di sini.',
          ),
        AnimatedList(
          key: _listKey,
          initialItemCount: _items.length,
          padding: const EdgeInsets.only(bottom: 24),
          itemBuilder: (
            BuildContext context,
            int index,
            Animation<double> animation,
          ) {
            return SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: FadeTransition(
                opacity: animation,
                child: AnimatedEntrance(
                  // Efek bertahap saat daftar pertama tampil; kartu baru
                  // yang disisipkan tetap memakai animasi AnimatedList.
                  delay: Duration(milliseconds: 50 * (index < 8 ? index : 8)),
                  child: _card(_items[index]),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.event,
    required this.onAccept,
    required this.onIgnore,
  });

  final NotificationEvent event;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final String amountText = event.amountMinor == null
        ? '-'
        : MoneyFormatter.format(event.amountMinor!);

    return Card(
      key: Key('pending_card_${event.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    event.merchant ?? event.detectedType.label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  DateFormat('dd/MM/yy HH:mm').format(event.postedAt),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              amountText,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  // Bar keyakinan parser tumbuh dari 0 — sekaligus
                  // menyorot seberapa tinggi confidence notifikasi ini.
                  child: AnimatedProgressBar(
                    value: event.confidence.clamp(0.0, 1.0),
                    minHeight: 6,
                    borderRadius: 3,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'keyakinan ${(event.confidence * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('pending_ignore_${event.id}'),
                    onPressed: onIgnore,
                    icon: const Icon(Icons.block_outlined),
                    label: const Text('Abaikan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: Key('pending_accept_${event.id}'),
                    onPressed: onAccept,
                    icon: const Icon(Icons.check),
                    label: const Text('Terima'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
