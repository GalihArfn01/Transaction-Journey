import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money_formatter.dart';
import '../../data/datasource/app_database.dart';
import '../../domain/model/enums.dart';
import '../transactions/providers.dart';

/// Pilihan pengguna di bottom-sheet "Terima" — kategori & rekening TUJUAN
/// transaksi yang disimpan dari event pending. Dikembalikan null bila
/// pengguna membatalkan (kartu pending harus tetap di tempat).
class AcceptPendingChoice {
  const AcceptPendingChoice({required this.category, required this.account});

  final Category category;
  final Account account;
}

/// Bottom-sheet "Terima": sebelum event pending disimpan sebagai transaksi,
/// pengguna memilih KATEGORI (sesuai jenis: expense/income hasil
/// normalisasi `resolvedTransactionType`) dan REKENING. Default = perilaku
/// lama (kategori 'Lainnya' + rekening aktif pertama), jadi satu ketukan
/// Konfirmasi tanpa mengubah apa pun hasilnya identik dengan sebelum fitur
/// ini ada — tidak ada lagi alasan transaksi otomatis "nyasar".
Future<AcceptPendingChoice?> showAcceptPendingSheet(
  BuildContext context,
  WidgetRef ref,
  NotificationEvent event,
) {
  return showModalBottomSheet<AcceptPendingChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AcceptPendingSheet(event: event),
  );
}

class _AcceptPendingSheet extends ConsumerStatefulWidget {
  const _AcceptPendingSheet({required this.event});

  final NotificationEvent event;

  @override
  ConsumerState<_AcceptPendingSheet> createState() =>
      _AcceptPendingSheetState();
}

class _AcceptPendingSheetState extends ConsumerState<_AcceptPendingSheet> {
  int? _categoryId;
  int? _accountId;
  bool _initialized = false;

  void _initDefaults(List<Category> categories, List<Account> accounts) {
    if (_initialized) return;
    _initialized = true;
    // Default = perilaku lama: 'Lainnya' + rekening pertama.
    Category? lainnya;
    for (final Category c in categories) {
      if (c.name == 'Lainnya') {
        lainnya = c;
        break;
      }
    }
    _categoryId = (lainnya ?? (categories.isNotEmpty ? categories.first : null))
        ?.id;
    _accountId = accounts.isNotEmpty ? accounts.first.id : null;
  }

  @override
  Widget build(BuildContext context) {
    final NotificationEvent event = widget.event;
    final TransactionType type = event.detectedType.resolvedTransactionType;
    final AsyncValue<List<Category>> categories =
        ref.watch(activeCategoriesProvider(type));
    final AsyncValue<List<Account>> accounts =
        ref.watch(activeAccountsProvider);

    final String amountText = event.amountMinor == null
        ? '-'
        : MoneyFormatter.format(event.amountMinor!);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        // Scroll defensif untuk layar kecil: tombol Simpan/Batal selalu
        // bisa di-scroll ke viewport (juga dipakai `ensureVisible` di test).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Simpan sebagai ${type.label.toLowerCase()}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${event.merchant ?? event.detectedType.label} · $amountText',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
            categories.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (Object e, StackTrace _) =>
                  Text('Gagal memuat kategori: $e'),
              data: (List<Category> cats) {
                return accounts.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (Object e, StackTrace _) =>
                      Text('Gagal memuat rekening: $e'),
                  data: (List<Account> accs) {
                    if (cats.isEmpty || accs.isEmpty) {
                      return const Text(
                        'Kategori atau rekening aktif belum tersedia — '
                        'lengkapi dulu di Pengaturan.',
                      );
                    }
                    _initDefaults(cats, accs);
                    Category? selectedCat;
                    for (final Category c in cats) {
                      if (c.id == _categoryId) {
                        selectedCat = c;
                        break;
                      }
                    }
                    selectedCat ??= cats.first;
                    Account? selectedAcc;
                    for (final Account a in accs) {
                      if (a.id == _accountId) {
                        selectedAcc = a;
                        break;
                      }
                    }
                    selectedAcc ??= accs.first;
                    final Category resolvedCat = selectedCat;
                    final Account resolvedAcc = selectedAcc;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        DropdownButtonFormField<int>(
                          key: const Key('accept_sheet_category'),
                          value: resolvedCat.id,
                          decoration: const InputDecoration(
                            labelText: 'Kategori',
                            border: OutlineInputBorder(),
                          ),
                          items: <DropdownMenuItem<int>>[
                            for (final Category c in cats)
                              DropdownMenuItem<int>(
                                value: c.id,
                                child: Text(c.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (int? v) =>
                              setState(() => _categoryId = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          key: const Key('accept_sheet_account'),
                          value: resolvedAcc.id,
                          decoration: const InputDecoration(
                            labelText: 'Rekening',
                            border: OutlineInputBorder(),
                          ),
                          items: <DropdownMenuItem<int>>[
                            for (final Account a in accs)
                              DropdownMenuItem<int>(
                                value: a.id,
                                child: Text(a.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (int? v) =>
                              setState(() => _accountId = v),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                key: const Key('accept_sheet_cancel'),
                                onPressed: () =>
                                    Navigator.of(context).pop(),
                                child: const Text('Batal'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                key: const Key('accept_sheet_confirm'),
                                onPressed: () =>
                                    Navigator.of(context).pop(
                                  AcceptPendingChoice(
                                    category: resolvedCat,
                                    account: resolvedAcc,
                                  ),
                                ),
                                icon: const Icon(Icons.check),
                                label: const Text('Simpan'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            ],
          ),
        ),
      ),
    );
  }
}
