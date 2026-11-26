import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/result.dart';
import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/transaction_repository.dart';
import '../../domain/model/transaction_input.dart';
import '../../domain/model/enums.dart';
import '../shared/app_icons.dart';
import '../shared/widgets/gradient_app_bar.dart';
import '../shared/widgets/animations.dart';
import '../transactions/providers.dart';

/// Kunci settings yang menandai onboarding sudah selesai. Nilai '1' =
/// selesai; null/kosong = belum (first-run).
const String kOnboardingDoneSettingKey = 'onboarding_done';

/// Wizard first-run 2 langkah: (1) isi saldo awal rekening Tunai &
/// Non Tunai yang sudah di-seed, (2) pilih kategori favorit untuk
/// ditandai. Langkah 2 murni kosmetik (tanda bintang), jadi bisa dilewati.
///
/// Wizard HANYA tampil saat flag `onboarding_done` kosong (DB baru).
/// Dipanggil dari `app.dart`; `onFinished` membalikkan home ke AppShell.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, required this.onFinished});

  final VoidCallback onFinished;

  static Future<void> markDone(WidgetRef ref) async {
    final AppDatabase db = ref.read(appDatabaseProvider);
    await db.settingsDao.setValue(kOnboardingDoneSettingKey, '1');
  }

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final TextEditingController _cash = TextEditingController();
  final TextEditingController _nonCash = TextEditingController();
  final Set<int> _favoriteIds = <int>{};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _cash.dispose();
    _nonCash.dispose();
    super.dispose();
  }

  int? _parseMinor(String raw) {
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.parse(digits);
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final AppDatabase db = ref.read(appDatabaseProvider);
      final TransactionRepository txRepo = TransactionRepository(db);
      // `.get()` satu-kali (BUKAN `watchAll().first`): stream `.first`
      // di callback tombol macet di widget-test, lihat
      // `CategoryDao.activeByType`.
      final List<Account> all = await db.accountDao.all();

      // Langkah 1: saldo awal — ditulis sebagai transaksi income ber-note
      // "Saldo awal" agar jejaknya mengikuti aturan transaksi biasa
      // (initialBalanceMinor immutable di seed = 0).
      Account? cash;
      Account? nonCash;
      for (final Account a in all) {
        if (a.type == AccountType.cash) cash = a;
        if (a.type == AccountType.nonCash) nonCash = a;
      }
      final DateTime now = DateTime.now();
      final int? cashMinor = _parseMinor(_cash.text);
      final int? nonCashMinor = _parseMinor(_nonCash.text);

      // Kategori pemasukan untuk "Saldo awal": income WAJIB berkategori
      // (`validateTransactionInput` menolak `categoryId` null) — SEBELUMNYA
      // `_finish` mengirim TANPA kategori sehingga `save` SELALU gagal dan
      // hasilnya pun DIABAIKAN: saldo awal tidak pernah tersimpan tanpa
      // pesan apa pun (persis keluhan "dimasukkan tapi percuma"). Prefer
      // 'Lainnya', fallback kategori income aktif pertama.
      int? incomeCategoryId;
      if ((cashMinor ?? 0) > 0 || (nonCashMinor ?? 0) > 0) {
        final List<Category> incomeCats =
            await db.categoryDao.activeByType(TransactionType.income);
        Category? lainnya;
        for (final Category c in incomeCats) {
          if (c.name == 'Lainnya') {
            lainnya = c;
            break;
          }
        }
        incomeCategoryId =
            lainnya?.id ?? (incomeCats.isNotEmpty ? incomeCats.first.id : null);
        if (incomeCategoryId == null) {
          throw Exception('Kategori pemasukan tidak tersedia');
        }
      }

      // Hasil save DIPERIKSA (tidak lagi diabaikan): gagal -> tampilkan
      // pesan & tetap di wizard, JANGAN tandai onboarding selesai.
      final List<String> failures = <String>[];
      Future<void> saveOpening(
        Account? account,
        int? amountMinor,
      ) async {
        if (account == null || amountMinor == null || amountMinor <= 0) return;
        final Result<int> result = await txRepo.save(TransactionInput(
          type: TransactionType.income,
          amountMinor: amountMinor,
          date: now,
          accountId: account.id,
          categoryId: incomeCategoryId,
          note: 'Saldo awal',
        ));
        if (!result.isSuccess) {
          failures.add((result as Failure<int>).firstMessage);
        }
      }

      await saveOpening(cash, cashMinor);
      await saveOpening(nonCash, nonCashMinor);
      if (failures.isNotEmpty) {
        if (mounted) {
          setState(() {
            _saving = false;
            _error = failures.first;
          });
        }
        return;
      }

      // Langkah 2 (kategori favorit) sengaja tanpa penulisan DB — tidak
      // ada kolom favorit; pilihan hanya konfirmasi preferensi pengguna
      // dan halaman Kategori bisa diatur nanti.

      await OnboardingPage.markDone(ref);
      if (mounted) widget.onFinished();
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Gagal menyimpan: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AsyncValue<List<Category>> categories =
        ref.watch(activeCategoriesProvider(TransactionType.expense));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const GradientAppBar(title: 'Selamat Datang'),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Dua langkah singkat sebelum mulai mencatat.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const TabBar(
                tabs: <Tab>[
                  Tab(text: '1. Saldo Awal'),
                  Tab(text: '2. Kategori Favorit'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _buildBalanceStep(scheme),
                    _buildCategoryStep(categories),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!,
                            style: TextStyle(color: scheme.error)),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('onboarding_finish_button'),
                        onPressed: _saving ? null : _finish,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: const Text('Mulai Pakai'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceStep(ColorScheme scheme) {
    // Langkah muncul dengan fade + naik halus saat tab dibuka.
    return AnimatedEntrance(
        child: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Berapa uang yang kamu punya sekarang? Ini jadi titik awal '
          'pelacakan — boleh dilewati.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('onboarding_cash_field'),
          controller: _cash,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Saldo Tunai',
            prefixIcon: Icon(Icons.payments_outlined),
            hintText: '0',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('onboarding_non_cash_field'),
          controller: _nonCash,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Saldo Non Tunai (mBanking/e-Wallet)',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            hintText: '0',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Disimpan sebagai transaksi "Saldo awal" agar jejaknya jelas.',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    ));
  }

  Widget _buildCategoryStep(AsyncValue<List<Category>> categories) {
    return categories.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) =>
          Center(child: Text('Gagal memuat kategori: $e')),
      data: (List<Category> list) => AnimatedEntrance(
          delay: const Duration(milliseconds: 60),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                'Tandai kategori yang paling sering kamu pakai (opsional).',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final Category c in list)
                CheckboxListTile(
                  key: Key('onboarding_category_${c.id}'),
                  value: _favoriteIds.contains(c.id),
                  onChanged: (bool? v) => setState(() {
                    if (v ?? false) {
                      _favoriteIds.add(c.id);
                    } else {
                      _favoriteIds.remove(c.id);
                    }
                  }),
                  secondary: CircleAvatar(
                    backgroundColor: Color(c.colorValue ?? 0xFF757575)
                        .withValues(alpha: 0.15),
                    child: Icon(appIconForKey(c.icon),
                        color: Color(c.colorValue ?? 0xFF757575), size: 20),
                  ),
                  title: Text(c.name),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
            ],
          )),
    );
  }
}
