import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/result.dart';
import '../../core/utils/input_formatters.dart';
import '../../data/datasource/app_database.dart';
import '../../data/repository/recurring_repository.dart';
import '../../domain/model/enums.dart';
import '../shared/widgets/animations.dart';
import '../shared/widgets/app_dropdown_field.dart';
import '../shared/widgets/form_pop_guard.dart';
import '../transactions/providers.dart'
    show activeAccountsProvider, activeCategoriesProvider;
import 'providers.dart';

const List<String> _kWeekdayNames = <String>[
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

/// Form buat/edit template transaksi berulang.
///
/// Sebelumnya halaman Recurring hanya punya tombol "Proses Jatuh Tempo"
/// dan toggle aktif/nonaktif — TIDAK ADA jalur untuk membuat template
/// baru dari UI, meski engine `RecurringRepository.generateDue` +
/// `nextOccurrence` (recurrence_math.dart) sudah matang & teruji. Form
/// ini menutup celah itu.
class RecurringFormPage extends ConsumerStatefulWidget {
  const RecurringFormPage({super.key, this.existing});

  final RecurringTransaction? existing;

  @override
  ConsumerState<RecurringFormPage> createState() => _RecurringFormPageState();
}

class _RecurringFormPageState extends ConsumerState<RecurringFormPage> {
  bool get _isEditing => widget.existing != null;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _interval = TextEditingController(text: '1');

  TransactionType _type = TransactionType.expense;
  int? _accountId;
  int? _categoryId;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  int _dayOfMonth = 1;
  int _dayOfWeek = 1;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _autoCreate = true;
  bool _saving = false;

  /// True bila ada isian berubah -> back minta konfirmasi ([FormPopGuard]).
  bool _dirty = false;
  late final void Function() _disposeDirtyWatch;
  String? _error;

  /// Penanda goyangan per field (lihat [ShakeWidget]).
  int _shakeName = 0;
  int _shakeAmount = 0;
  int _shakeAccount = 0;
  int _shakeCategory = 0;

  @override
  void initState() {
    super.initState();
    // Listener dirty di initState — lihat catatan di form transaksi.
    _disposeDirtyWatch = watchFormDirty(
      <TextEditingController>[_name, _amount, _interval],
      () => mounted ? setState(() => _dirty = true) : (),
    );
    final RecurringTransaction? t = widget.existing;
    if (t != null) {
      _name.text = t.name;
      _amount.text = ThousandsSeparatorFormatter.formatInt(t.amountMinor);
      _type = t.type;
      _accountId = t.accountId;
      _categoryId = t.categoryId;
      _frequency = t.frequency;
      _interval.text = '${t.intervalCount}';
      _dayOfMonth = t.dayOfMonth ?? t.startDate.day;
      _dayOfWeek = t.dayOfWeek ?? t.startDate.weekday;
      _startDate = t.startDate;
      _endDate = t.endDate;
      _autoCreate = t.autoCreate;
    }
  }

  @override
  void dispose() {
    _disposeDirtyWatch();
    _name.dispose();
    _amount.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? _startDate),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _saving = true;
    });

    final int amount = ThousandsSeparatorFormatter.parse(_amount.text);
    final int interval = int.tryParse(_interval.text) ?? 1;
    final int? accountId = _accountId;
    final RecurringRepository repo = ref.read(recurringRepositoryProvider);

    if (accountId == null) {
      setState(() {
        _saving = false;
        _error = 'Rekening wajib dipilih';
        _shakeAccount++;
      });
      return;
    }

    final Result<dynamic> result;
    if (_isEditing) {
      result = await repo.update(
        id: widget.existing!.id,
        name: _name.text,
        type: _type,
        amountMinor: amount,
        accountId: accountId,
        categoryId: _categoryId,
        frequency: _frequency,
        intervalCount: interval,
        dayOfMonth:
            _frequency == RecurrenceFrequency.monthly ? _dayOfMonth : null,
        dayOfWeek: _frequency == RecurrenceFrequency.weekly ? _dayOfWeek : null,
        startDate: _startDate,
        endDate: _endDate,
        autoCreate: _autoCreate,
      );
    } else {
      result = await repo.create(
        name: _name.text,
        type: _type,
        amountMinor: amount,
        accountId: accountId,
        categoryId: _categoryId,
        frequency: _frequency,
        intervalCount: interval,
        dayOfMonth:
            _frequency == RecurrenceFrequency.monthly ? _dayOfMonth : null,
        dayOfWeek: _frequency == RecurrenceFrequency.weekly ? _dayOfWeek : null,
        startDate: _startDate,
        endDate: _endDate,
        autoCreate: _autoCreate,
      );
    }

    if (!mounted) return;
    switch (result) {
      case Success<dynamic>():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(_isEditing ? 'Template diperbarui' : 'Template dibuat'),
          ),
        );
        Navigator.of(context).pop();
      case final Failure<dynamic> failure:
        setState(() {
          _saving = false;
          _error = failure.firstMessage;
          // Peta pesan validasi repository -> field yang digoyang.
          final String message = failure.firstMessage;
          if (message.contains('ekening')) {
            _shakeAccount++;
          } else if (message.contains('ategori')) {
            _shakeCategory++;
          } else if (message.toLowerCase().contains('nominal')) {
            _shakeAmount++;
          } else {
            _shakeName++;
          }
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Account> accounts =
        ref.watch(activeAccountsProvider).valueOrNull ?? const <Account>[];
    final List<Category> categories =
        ref.watch(activeCategoriesProvider(_type)).valueOrNull ??
            const <Category>[];
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // Guard: rekening/kategori lama yang sudah dinonaktifkan tidak lagi
    // ada di daftar aktif — jangan crash dropdown, biarkan null (pengguna
    // wajib pilih ulang) daripada assert error.
    final int? accountValue =
        accounts.any((Account a) => a.id == _accountId) ? _accountId : null;
    final int? categoryValue =
        categories.any((Category c) => c.id == _categoryId)
            ? _categoryId
            : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Berulang' : 'Berulang Baru'),
      ),
      body: FormPopGuard(
        isDirty: _dirty,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _capsLabel(context, 'Nama template'),
              const SizedBox(height: 6),
              ShakeWidget(
                  tick: _shakeName,
                  child: TextFormField(
                    controller: _name,
                    autofocus: !_isEditing,
                    decoration: _fieldDecoration(
                      scheme,
                      hintText: 'mis. Listrik bulanan',
                    ),
                  )),
              const SizedBox(height: 12),
              SegmentedButton<TransactionType>(
                segments: const <ButtonSegment<TransactionType>>[
                  ButtonSegment<TransactionType>(
                    value: TransactionType.expense,
                    label: Text('Pengeluaran'),
                  ),
                  ButtonSegment<TransactionType>(
                    value: TransactionType.income,
                    label: Text('Pemasukan'),
                  ),
                ],
                selected: <TransactionType>{_type},
                onSelectionChanged: (Set<TransactionType> s) => setState(() {
                  _type = s.first;
                  // Kategori lama mungkin tidak berlaku untuk jenis baru.
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 12),
              _capsLabel(context, 'Nominal'),
              const SizedBox(height: 6),
              ShakeWidget(
                  tick: _shakeAmount,
                  child: TextFormField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      ThousandsSeparatorFormatter(),
                    ],
                    decoration: _fieldDecoration(
                      scheme,
                      prefixText: 'Rp ',
                      hintText: '0',
                    ),
                  )),
              const SizedBox(height: 12),
              _capsLabel(context, 'Rekening'),
              const SizedBox(height: 6),
              ShakeWidget(
                  tick: _shakeAccount,
                  child: AppDropdownField<int>(
                    value: accountValue,
                    decoration: _fieldDecoration(scheme),
                    items: <DropdownMenuItem<int>>[
                      for (final Account a in accounts)
                        DropdownMenuItem<int>(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (int? v) => setState(() => _accountId = v),
                  )),
              const SizedBox(height: 12),
              _capsLabel(context, 'Kategori'),
              const SizedBox(height: 6),
              ShakeWidget(
                  tick: _shakeCategory,
                  child: AppDropdownField<int>(
                    value: categoryValue,
                    decoration: _fieldDecoration(scheme),
                    items: <DropdownMenuItem<int>>[
                      for (final Category c in categories)
                        DropdownMenuItem<int>(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (int? v) => setState(() => _categoryId = v),
                  )),
              const SizedBox(height: 16),
              _capsLabel(context, 'Jadwal — Frekuensi'),
              const SizedBox(height: 6),
              AppDropdownField<RecurrenceFrequency>(
                value: _frequency,
                decoration: _fieldDecoration(scheme),
                items: <DropdownMenuItem<RecurrenceFrequency>>[
                  for (final RecurrenceFrequency f
                      in RecurrenceFrequency.values)
                    DropdownMenuItem<RecurrenceFrequency>(
                      value: f,
                      child: Text(f.label),
                    ),
                ],
                onChanged: (RecurrenceFrequency? v) => setState(
                    () => _frequency = v ?? RecurrenceFrequency.monthly),
              ),
              const SizedBox(height: 12),
              _capsLabel(context, 'Interval'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _interval,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _fieldDecoration(scheme, hintText: '1'),
              ),
              if (_frequency == RecurrenceFrequency.monthly) ...<Widget>[
                const SizedBox(height: 12),
                _capsLabel(context, 'Tanggal tiap bulan'),
                const SizedBox(height: 6),
                AppDropdownField<int>(
                  value: _dayOfMonth,
                  decoration: _fieldDecoration(scheme),
                  items: <DropdownMenuItem<int>>[
                    for (int d = 1; d <= 31; d++)
                      DropdownMenuItem<int>(
                          value: d, child: Text('Tanggal $d')),
                  ],
                  onChanged: (int? v) => setState(() => _dayOfMonth = v ?? 1),
                ),
              ],
              if (_frequency == RecurrenceFrequency.weekly) ...<Widget>[
                const SizedBox(height: 12),
                _capsLabel(context, 'Hari'),
                const SizedBox(height: 6),
                AppDropdownField<int>(
                  value: _dayOfWeek,
                  decoration: _fieldDecoration(scheme),
                  items: <DropdownMenuItem<int>>[
                    for (int i = 1; i <= 7; i++)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text(_kWeekdayNames[i - 1]),
                      ),
                  ],
                  onChanged: (int? v) => setState(() => _dayOfWeek = v ?? 1),
                ),
              ],
              const SizedBox(height: 12),
              _capsLabel(context, 'Mulai'),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => _pickDate(isStart: true),
                borderRadius: BorderRadius.circular(12),
                child: _dateTile(
                  scheme,
                  value: DateFormat('d MMMM y', 'id_ID').format(_startDate),
                ),
              ),
              const SizedBox(height: 12),
              _capsLabel(context, 'Berakhir (opsional)'),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => _pickDate(isStart: false),
                borderRadius: BorderRadius.circular(12),
                child: _dateTile(
                  scheme,
                  value: _endDate == null
                      ? 'Tidak ditentukan'
                      : DateFormat('d MMMM y', 'id_ID').format(_endDate!),
                  trailing: _endDate == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _endDate = null),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Buat transaksi otomatis'),
                subtitle: const Text(
                  'Nonaktifkan untuk mode pengingat saja — tidak membuat '
                  'transaksi otomatis saat jatuh tempo.',
                ),
                value: _autoCreate,
                onChanged: (bool v) => setState(() => _autoCreate = v),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('recurring_form_save_button'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Simpan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _dateTile(
    ColorScheme scheme, {
    required String value,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.event_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
          trailing ??
              Icon(Icons.expand_more, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  static Widget _capsLabel(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.05,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  static InputDecoration _fieldDecoration(
    ColorScheme scheme, {
    String? prefixText,
    String? hintText,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      prefixText: prefixText,
      hintText: hintText,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(scheme.primary, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}
