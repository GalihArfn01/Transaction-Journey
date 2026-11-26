import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart'
    show AppRadii, AppShadows, AppSurfaceTints, FinanceColors;
import '../../core/errors/result.dart';
import '../../core/notifications/health_reminder_service.dart';
import '../../core/utils/input_formatters.dart';
import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/transaction_repository.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/transaction_input.dart';
import '../shared/app_icons.dart';
import '../shared/widgets/animations.dart';
import '../shared/widgets/app_dropdown_field.dart';
import '../shared/widgets/form_pop_guard.dart';
import '../shared/widgets/gradient_app_bar.dart';
import 'providers.dart';

/// Arah transfer — SATU-SATUNYA bentuk transfer yang masuk akal sejak
/// rekening disederhanakan jadi cuma Tunai & Non Tunai (lihat dokumentasi
/// `AccountType`): tidak ada lagi dropdown "pilih rekening tujuan" bebas
/// (dulu perlu karena rekening bisa banyak), karena tujuannya sudah
/// pasti "rekening yang satunya lagi". [accountId]/[toAccountId] tetap
/// diturunkan dari sini secara otomatis di `build()`.
enum _TransferDirection { withdraw, deposit }

extension on _TransferDirection {
  String get label => switch (this) {
        _TransferDirection.withdraw => 'Tarik Tunai (Non Tunai → Tunai)',
        _TransferDirection.deposit => 'Setor Tunai (Tunai → Non Tunai)',
      };
}

/// Warna aksen per tipe transaksi — dari mockup desain "Tambah Transaksi":
/// tiap tipe (Pemasukan/Pengeluaran/Transfer) punya warna sendiri yang
/// mewarnai segmented switch aktif, chip label & nominal di hero card,
/// dan tombol Simpan — bukan satu warna primary yang sama untuk semua
/// tipe seperti sebelumnya.
class _TypeAccent {
  const _TypeAccent({
    required this.color,
    required this.tint,
    required this.label,
  });

  final Color color;
  final Color tint;
  final String label;
}

const Map<TransactionType, _TypeAccent> _kTypeAccents =
    <TransactionType, _TypeAccent>{
  TransactionType.income: _TypeAccent(
    color: FinanceColors.income,
    tint: Color(0xFFE6F4EE),
    label: 'Pemasukan',
  ),
  TransactionType.expense: _TypeAccent(
    color: FinanceColors.expense,
    tint: AppSurfaceTints.iconContainerRed,
    label: 'Pengeluaran',
  ),
  TransactionType.transfer: _TypeAccent(
    color: FinanceColors.transfer,
    tint: Color(0xFFE7EEFC),
    label: 'Transfer',
  ),
};

/// Halaman tambah/edit transaksi — mengikuti mockup desain
/// "Tambah Transaksi (Standalone).html": segmented switch putih dengan
/// aksen warna per tipe, hero nominal card dengan chip label & nominal
/// berwarna aksen, date/time card, kartu rekening/kategori dengan ikon
/// bulat bertint, kartu catatan/tag bergaya kotak abu, dan tombol Simpan
/// yang MENEMPEL di bawah layar (bukan ikut scroll) berwarna aksen tipe
/// yang sedang aktif.
///
/// [transactionId] NULL = mode tambah.
///
/// KONTRAK TEST (tidak boleh berubah): Key('tx_amount_field'),
/// Key('tx_save_button'), labelText 'Nominal'/'Rekening / Dompet'/
/// 'Kategori', teks segmen Pemasukan/Pengeluaran/Transfer, teks
/// 'Simpan Transaksi'/'Total Nominal'. Dropdown TETAP memakai dropdown
/// Material asli lewat [AppDropdownField] (bukan picker kustom) supaya
/// alur `tester.tap` + pilih item di overlay pada test yang ada tetap jalan.
class AddEditTransactionPage extends ConsumerStatefulWidget {
  const AddEditTransactionPage({super.key, this.transactionId});

  final int? transactionId;

  @override
  ConsumerState<AddEditTransactionPage> createState() =>
      _AddEditTransactionPageState();
}

class _AddEditTransactionPageState
    extends ConsumerState<AddEditTransactionPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  bool get _isEditing => widget.transactionId != null;

  TransactionType _type = TransactionType.expense;
  int? _categoryId;
  int? _accountId;
  int? _toAccountId;
  int? _paymentMethodId;

  /// Hanya relevan untuk transfer — lihat dokumentasi `_TransferDirection`.
  /// NULL = belum dipilih (transaksi baru) ATAU belum berhasil ditebak
  /// dari `_accountId`/`_toAccountId` hasil load (lihat `build()`).
  _TransferDirection? _direction;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();

  bool get _isTransfer => _type == TransactionType.transfer;

  /// Mode edit menunggu data dimuat; mode tambah langsung siap.
  /// (Assignment di initState legal karena terjadi sebelum build pertama.)
  bool _loadingExisting = true;
  bool _saving = false;

  /// True bila ada isian berubah -> back minta konfirmasi ([FormPopGuard]).
  bool _dirty = false;
  late final void Function() _disposeDirtyWatch;
  bool _submitAttempted = false;
  Map<ValidationField, String> _fieldErrors = const <ValidationField, String>{};

  /// Penanda goyangan per field (lihat [ShakeWidget]): nilainya naik HANYA
  /// untuk field yang benar-benar ditolak validasi, jadi input yang sudah
  /// valid tidak ikut bergoyang.
  Map<ValidationField, int> _shakeTicks = const <ValidationField, int>{};

  static final DateFormat _dateFormat = DateFormat('EEEE, d MMM y', 'id_ID');
  static final DateFormat _timeFormat = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    // Listener dirty HARUS terpasang di initState (bukan field initializer
    // late final yang lazy) — kalau tidak, isian sebelum akses pertama
    // tidak terdeteksi dan back langsung pop tanpa dialog.
    _disposeDirtyWatch = watchFormDirty(
      <TextEditingController>[
        _amountController,
        _noteController,
        _tagsController
      ],
      () => mounted ? setState(() => _dirty = true) : (),
    );
    if (_isEditing) {
      _loadExisting();
    } else {
      _loadingExisting = false;
    }
  }

  Future<void> _loadExisting() async {
    if (!_isEditing) {
      setState(() => _loadingExisting = false);
      return;
    }
    final TransactionRepository repo = ref.read(transactionRepositoryProvider);
    final detail = await repo.detailById(widget.transactionId!);
    if (detail == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaksi tidak ditemukan')),
        );
        Navigator.of(context).pop();
      }
      return;
    }
    final List<Tag> tags = await repo.tagsOf(widget.transactionId!);
    if (!mounted) return;
    setState(() {
      _type = detail.transaction.type;
      _amountController.text =
          ThousandsSeparatorFormatter.formatInt(detail.transaction.amountMinor);
      _noteController.text = detail.transaction.note ?? '';
      _categoryId = detail.transaction.categoryId;
      _accountId = detail.transaction.accountId;
      _toAccountId = detail.transaction.toAccountId;
      _paymentMethodId = detail.transaction.paymentMethodId;
      _date = detail.transaction.date;
      _time = TimeOfDay.fromDateTime(detail.transaction.date);
      _tagsController.text = tags.map((Tag t) => t.name).join(', ');
      _loadingExisting = false;
    });
  }

  @override
  void dispose() {
    _disposeDirtyWatch();
    _amountController.dispose();
    _noteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  DateTime get _combinedDateTime => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  Future<void> _save() async {
    setState(() {
      _submitAttempted = true;
      _fieldErrors = const <ValidationField, String>{};
    });

    final bool transfer = _isTransfer;
    final TransactionInput input = TransactionInput(
      id: widget.transactionId,
      type: _type,
      amountMinor: ThousandsSeparatorFormatter.parse(_amountController.text),
      date: _combinedDateTime,
      // Transfer tidak punya kategori/metode — kirim NULL agar validasi
      // domain (validateTransactionInput) yang menjadi satu-satunya
      // sumber aturan toAccount wajib & berbeda.
      categoryId: transfer ? null : _categoryId,
      accountId: _accountId ?? 0,
      toAccountId: transfer ? _toAccountId : null,
      paymentMethodId: transfer ? null : _paymentMethodId,
      note: _noteController.text,
      tags: _tagsController.text.split(','),
    );

    // Validasi lokal cepat untuk feedback instan tanpa menyentuh DB.
    final List<FieldError> localErrors = validateTransactionInput(input);
    if (localErrors.isNotEmpty) {
      setState(() {
        _fieldErrors = <ValidationField, String>{
          for (final FieldError e in localErrors) e.field: e.message,
        };
        _shakeTicks = _nextShakeTicks(localErrors);
      });
      return;
    }

    setState(() => _saving = true);
    final Result<int> result =
        await ref.read(transactionRepositoryProvider).save(input);
    if (!mounted) return;

    switch (result) {
      case final Success<int> success:
        // Pengingat Skor Kesehatan Finansial — HANYA untuk transaksi BARU
        // (bukan edit) bertipe income/expense (transfer tidak memengaruhi
        // income/expense sama sekali, lihat `_totalsQuery`). Dipicu di
        // sini (bukan lewat background service) karena app memang sedang
        // aktif di foreground saat pengguna menambah transaksi — lihat
        // dokumentasi lengkap di `HealthReminderService`. Fire-and-forget:
        // TIDAK PERNAH menunda `pop()` di bawah maupun melempar ke sini
        // (seluruh isinya sudah dibungkus try/catch + `CrashLogger`).
        if (!_isEditing && !_isTransfer) {
          unawaited(
            HealthReminderService.instance
                .checkAfterTransaction(ref.read(appDatabaseProvider)),
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Transaksi diperbarui'
                  : _isTransfer
                      ? 'Transfer tersimpan'
                      : 'Transaksi tersimpan',
            ),
          ),
        );
        Navigator.of(context).pop(success.value);
      case final Failure<int> failure:
        setState(() {
          _saving = false;
          _fieldErrors = <ValidationField, String>{
            for (final FieldError e in failure.errors) e.field: e.message,
          };
          _shakeTicks = _nextShakeTicks(failure.errors);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.firstMessage)),
        );
    }
  }

  String? _errorFor(ValidationField field) =>
      _submitAttempted ? _fieldErrors[field] : null;

  /// Salinan penanda goyangan dengan field yang ditolak dinaikkan satu.
  Map<ValidationField, int> _nextShakeTicks(Iterable<FieldError> errors) =>
      <ValidationField, int>{
        for (final FieldError error in errors)
          error.field: (_shakeTicks[error.field] ?? 0) + 1,
      };

  // ---------------------------------------------------------------------------
  // Build helpers — mengikuti mockup "Tambah Transaksi (Standalone).html".
  // Logika state di atas TIDAK tersentuh oleh restyle ini.
  // ---------------------------------------------------------------------------

  /// Kartu putih rounded soft-shadow — pengganti `_cardDecoration` lama
  /// yang pakai border abu-abu, sekarang memakai token bayangan kartu
  /// (dua lapis, [AppShadows.card]) yang sama dengan seluruh halaman lain
  /// supaya satu keluarga desain. [radius] diisi token [AppRadii] supaya
  /// bahasa bentuknya juga seragam.
  BoxDecoration _shadowCard(
    ColorScheme scheme, {
    double radius = AppRadii.card,
  }) =>
      BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.card(scheme),
      );

  Widget _captionLabel(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );

  /// Segmented 3-way: track PUTIH (bukan abu) dengan indikator aktif
  /// berwarna AKSEN TIPE (hijau/merah/biru), bukan satu warna primary
  /// yang sama untuk semua tipe seperti sebelumnya.
  Widget _buildSegmented(ColorScheme scheme) {
    Widget segment(TransactionType type) {
      final bool active = _type == type;
      final _TypeAccent accent = _kTypeAccents[type]!;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _type = type;
            _categoryId = null;
            _toAccountId = null;
            _direction = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? accent.color : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              accent.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: active ? Colors.white : scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: _shadowCard(scheme, radius: AppRadii.field),
      child: Row(
        children: <Widget>[
          segment(TransactionType.income),
          segment(TransactionType.expense),
          segment(TransactionType.transfer),
        ],
      ),
    );
  }

  /// HERO NOMINAL CARD: chip label kecil berwarna tint aksen, nominal
  /// besar berwarna aksen penuh (bukan hitam netral) — warnanya berganti
  /// mengikuti tipe transaksi yang dipilih di segmented switch.
  Widget _buildHeroAmount(
    _TypeAccent accent,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: _shadowCard(scheme),
      child: Column(
        children: <Widget>[
          Text(
            'Total Nominal',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: accent.tint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              accent.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent.color,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Rp',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent.color,
                ),
              ),
              const SizedBox(width: 8),
              IntrinsicWidth(
                child: ShakeWidget(
                    tick: _shakeTicks[ValidationField.amount] ?? 0,
                    child: TextFormField(
                      key: const Key('tx_amount_field'),
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorFormatter(),
                      ],
                      textAlign: TextAlign.left,
                      autofocus: !_isEditing,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Nominal',
                        hintText: '0',
                        filled: false,
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorText: _errorFor(ValidationField.amount),
                        errorStyle: const TextStyle(
                          color: FinanceColors.expense,
                          fontWeight: FontWeight.w600,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent.color,
                      ),
                    )),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// DATE & TIME row — dua kartu putih shadow (bukan surfaceContainerHighest
  /// polos) dengan ikon di depan, sama seperti kartu lain di halaman ini.
  Widget _buildDateTimeRow(ColorScheme scheme) {
    return Row(
      children: <Widget>[
        Expanded(
          child: ShakeWidget(
              tick: _shakeTicks[ValidationField.date] ?? 0,
              child: _PickerTile(
                icon: Icons.calendar_today,
                label: _dateFormat.format(_date),
                onTap: _pickDate,
                errorText: _errorFor(ValidationField.date),
                decoration: _shadowCard(scheme, radius: AppRadii.field),
              )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PickerTile(
            icon: Icons.schedule,
            label: _timeFormat.format(_combinedDateTime),
            onTap: _pickTime,
            decoration: _shadowCard(scheme, radius: AppRadii.field),
          ),
        ),
      ],
    );
  }

  /// Ikon bulat bertint — dipakai sebagai `prefixIcon` dropdown rekening/
  /// kategori/arah transfer, meniru avatar bulat di mockup.
  Widget _iconCircle(IconData icon, Color tint, Color color) => Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
        child: Icon(icon, size: 18, color: color),
      );

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final _TypeAccent accent = _kTypeAccents[_type]!;
    final List<Category> categories =
        ref.watch(activeCategoriesProvider(_type)).valueOrNull ??
            const <Category>[];
    final List<Account> accounts =
        ref.watch(activeAccountsProvider).valueOrNull ?? const <Account>[];

    // Pastikan nilai terpilih masih ada di daftar aktif.
    if (_categoryId != null &&
        !categories.any((Category c) => c.id == _categoryId)) {
      _categoryId = null;
    }

    // Transfer TIDAK LAGI pakai dropdown rekening tujuan bebas — hanya
    // ada 2 rekening tetap (Tunai/Non Tunai), jadi arahnya cukup dipilih
    // lewat _TransferDirection lalu accountId/toAccountId diturunkan di
    // sini (lihat dokumentasi enum). Cari dulu ID kedua rekening tetap.
    Account? cashAccount;
    Account? nonCashAccount;
    for (final Account a in accounts) {
      if (a.type == AccountType.cash) cashAccount = a;
      if (a.type == AccountType.nonCash) nonCashAccount = a;
    }

    if (_isTransfer && cashAccount != null && nonCashAccount != null) {
      // Tebak arah dari accountId/toAccountId hasil load (mode edit)
      // kalau _direction belum sempat diisi.
      _direction ??= (_accountId == nonCashAccount.id &&
              _toAccountId == cashAccount.id)
          ? _TransferDirection.withdraw
          : (_accountId == cashAccount.id && _toAccountId == nonCashAccount.id)
              ? _TransferDirection.deposit
              : null;

      switch (_direction) {
        case _TransferDirection.withdraw:
          _accountId = nonCashAccount.id;
          _toAccountId = cashAccount.id;
        case _TransferDirection.deposit:
          _accountId = cashAccount.id;
          _toAccountId = nonCashAccount.id;
        case null:
          // Belum dipilih — biarkan kosong supaya validator tampilkan
          // "wajib dipilih" seperti field lain, bukan menebak default.
          _accountId = null;
          _toAccountId = null;
      }
    } else if (!_isTransfer) {
      _toAccountId = null;
    }

    // Rekening & ikon kategori terpilih untuk avatar bulat di dropdown.
    Account? selectedAccount;
    for (final Account a in accounts) {
      if (a.id == _accountId) {
        selectedAccount = a;
        break;
      }
    }
    Category? selectedCategory;
    for (final Category c in categories) {
      if (c.id == _categoryId) {
        selectedCategory = c;
        break;
      }
    }

    if (_loadingExisting) {
      return Scaffold(
        appBar: GradientAppBar(
          title: _isEditing ? 'Edit Transaksi' : 'Tambah Transaksi',
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: GradientAppBar(
        title: _isEditing ? 'Edit Transaksi' : 'Tambah Transaksi',
      ),
      body: FormPopGuard(
        isDirty: _dirty,
        // Cek isi nyata: nominal ter-parse > 0 ATAU ada catatan/tag.
        // Mencegah dialog untuk dirty palsu (controller disentuh tapi
        // kosong) — form kosong memang tidak ada yang bisa dibuang.
        hasContent: () =>
            ThousandsSeparatorFormatter.parse(_amountController.text) > 0 ||
            _noteController.text.trim().isNotEmpty ||
            _tagsController.text.trim().isNotEmpty,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      _buildSegmented(scheme),
                      const SizedBox(height: 14),
                      _buildHeroAmount(accent, scheme, textTheme),
                      const SizedBox(height: 14),
                      _buildDateTimeRow(scheme),
                      const SizedBox(height: 14),

                      // GROUP: rekening sumber — disembunyikan utk transfer,
                      // karena arahnya sudah otomatis menentukan sumber+tujuan
                      // (lihat card "Arah Transfer" di bawah).
                      if (!_isTransfer) ...<Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: _shadowCard(scheme),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _captionLabel(context, 'Pilih Rekening/Dompet'),
                              const SizedBox(height: 8),
                              ShakeWidget(
                                  tick:
                                      _shakeTicks[ValidationField.account] ?? 0,
                                  child: AppDropdownField<int>(
                                    value: _accountId,
                                    decoration: InputDecoration(
                                      labelText: 'Rekening / Dompet',
                                      errorText:
                                          _errorFor(ValidationField.account),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      prefixIcon: _iconCircle(
                                        selectedAccount == null
                                            ? Icons
                                                .account_balance_wallet_outlined
                                            : appIconForKey(
                                                selectedAccount.icon),
                                        AppSurfaceTints.iconContainerBlue,
                                        scheme.primary,
                                      ),
                                    ),
                                    items: accounts
                                        .map(
                                          (Account a) => DropdownMenuItem<int>(
                                            value: a.id,
                                            child: Text(a.name),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (int? value) =>
                                        setState(() => _accountId = value),
                                    validator: (_) =>
                                        _errorFor(ValidationField.account),
                                  )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Transfer tidak punya kategori — ganti dengan pemilih
                      // arah transfer.
                      if (!_isTransfer)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: _shadowCard(scheme),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _captionLabel(context, 'Pilih Kategori'),
                              const SizedBox(height: 8),
                              ShakeWidget(
                                  tick: _shakeTicks[ValidationField.category] ??
                                      0,
                                  child: AppDropdownField<int>(
                                    value: _categoryId,
                                    decoration: InputDecoration(
                                      labelText: 'Kategori',
                                      errorText:
                                          _errorFor(ValidationField.category),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      prefixIcon: _iconCircle(
                                        selectedCategory == null
                                            ? Icons.help_outline
                                            : appIconForKey(
                                                selectedCategory.icon),
                                        selectedCategory?.colorValue != null
                                            ? Color(selectedCategory!
                                                    .colorValue!)
                                                .withValues(alpha: 0.15)
                                            : const Color(0xFFF0F1F5),
                                        selectedCategory?.colorValue != null
                                            ? Color(
                                                selectedCategory!.colorValue!)
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    items: categories
                                        .map(
                                          (Category c) => DropdownMenuItem<int>(
                                            value: c.id,
                                            child: Text(c.name),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (int? value) =>
                                        setState(() => _categoryId = value),
                                    validator: (_) =>
                                        _errorFor(ValidationField.category),
                                  )),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: _shadowCard(scheme),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _captionLabel(context, 'Arah Transfer'),
                              const SizedBox(height: 8),
                              ShakeWidget(
                                  tick: _shakeTicks[
                                          ValidationField.toAccount] ??
                                      _shakeTicks[ValidationField.account] ??
                                      0,
                                  child: AppDropdownField<_TransferDirection>(
                                    key: const Key(
                                        'transfer_direction_dropdown'),
                                    value: _direction,
                                    decoration: InputDecoration(
                                      labelText: 'Tarik Tunai / Setor Tunai',
                                      errorText: _errorFor(
                                              ValidationField.toAccount) ??
                                          _errorFor(ValidationField.account),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      prefixIcon: _iconCircle(
                                        Icons.swap_horiz,
                                        accent.tint,
                                        accent.color,
                                      ),
                                    ),
                                    items: _TransferDirection.values
                                        .map(
                                          (_TransferDirection d) =>
                                              DropdownMenuItem<
                                                  _TransferDirection>(
                                            value: d,
                                            child: Text(d.label),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (_TransferDirection? value) =>
                                        setState(() => _direction = value),
                                    validator: (_) =>
                                        _errorFor(ValidationField.toAccount) ??
                                        _errorFor(ValidationField.account),
                                  )),
                            ],
                          ),
                        ),

                      const SizedBox(height: 14),

                      // EXTRA card: catatan & tag — kotak abu berbatas, bukan
                      // TextFormField outline default, sama seperti mockup.
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _shadowCard(scheme),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _captionLabel(context, 'Catatan (opsional)'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _noteController,
                              decoration: _boxFieldDecoration(
                                scheme,
                                hint: 'Tulis catatan...',
                              ),
                              maxLines: 2,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            _captionLabel(
                                context, 'Tag (pisahkan dengan koma)'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _tagsController,
                              decoration: _boxFieldDecoration(
                                scheme,
                                hint: 'mis. kantor, mingguan',
                              ),
                              textInputAction: TextInputAction.done,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                // Tombol Simpan MENEMPEL di bawah layar (bukan ikut scroll),
                // berwarna aksen tipe yang sedang aktif — sama seperti
                // mockup, bukan warna primary tetap seperti sebelumnya.
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7FB),
                    border: Border(
                      top: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('tx_save_button'),
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent.color,
                        disabledBackgroundColor: const Color(0xFF9CA3AF),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 3,
                        shadowColor: accent.color.withValues(alpha: 0.4),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.save_outlined,
                              color: Colors.white),
                      label: Text(
                        _saving ? 'Menyimpan...' : 'Simpan Transaksi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _boxFieldDecoration(ColorScheme scheme, {String? hint}) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE4E6EC)),
    );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF6F7FB),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary),
      ),
      contentPadding: const EdgeInsets.all(10),
    );
  }
}

/// Tombol tanggal/jam: kartu putih shadow (lihat `_shadowCard`) dengan
/// ikon di depan.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.decoration,
    this.errorText,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final BoxDecoration decoration;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.fieldBorder,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: decoration,
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (errorText != null)
                    Text(
                      errorText!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
