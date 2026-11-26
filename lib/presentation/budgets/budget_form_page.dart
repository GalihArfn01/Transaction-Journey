import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/result.dart';
import '../../core/notifications/health_reminder_service.dart';
import '../../core/utils/input_formatters.dart';
import '../../data/datasource/app_database.dart';
import '../../data/repository/budget_repository.dart';
import '../../domain/model/alert_templates.dart';
import '../../domain/model/enums.dart';
import '../shared/widgets/animations.dart';
import '../shared/widgets/app_dropdown_field.dart';
import '../shared/widgets/form_pop_guard.dart';
import '../transactions/providers.dart' show activeCategoriesProvider;
import 'providers.dart';

/// Form buat/edit anggaran. Nominal wajib > 0 (divalidasi repository).
/// Kategori kosong = budget keseluruhan (semua pengeluaran).
///
/// Seksi "Notifikasi Peringatan" (v6): user dapat mengaktifkan notifikasi
/// per-budget dan mengatur bebas judul + isinya (placeholder opsional).
class BudgetFormPage extends ConsumerStatefulWidget {
  const BudgetFormPage({super.key, this.existing});

  final Budget? existing;

  @override
  ConsumerState<BudgetFormPage> createState() => _BudgetFormPageState();
}

class _BudgetFormPageState extends ConsumerState<BudgetFormPage> {
  /// Sentinel dropdown: null kategori = keseluruhan.
  static const int _allCategories = -1;

  final TextEditingController _amount = TextEditingController();
  final TextEditingController _alertTitle = TextEditingController();
  final TextEditingController _alertBody = TextEditingController();

  /// Ambang NOMINAL pemicu notifikasi (rupiah, teks bebas). Kosong =
  /// pemicu saat pemakaian mencapai batas budget.
  final TextEditingController _alertThreshold = TextEditingController();

  /// Chips placeholder menyisipkan ke field yang terakhir difokuskan
  /// (default: isi notifikasi).
  final FocusNode _alertTitleFocus = FocusNode();
  final FocusNode _alertBodyFocus = FocusNode();
  TextEditingController? _lastAlertFocus;

  bool get _isEditing => widget.existing != null;

  BudgetPeriod _period = BudgetPeriod.monthly;
  int _categoryId = _allCategories;
  DateTime _startDate = DateTime.now();
  bool _alertEnabled = false;
  bool _saving = false;

  /// True bila ada isian berubah -> back minta konfirmasi ([FormPopGuard]).
  bool _dirty = false;
  late final void Function() _disposeDirtyWatch;
  String? _error;

  /// Penanda goyangan field nominal (lihat [ShakeWidget]).
  int _shakeAmount = 0;

  @override
  void initState() {
    super.initState();
    // Listener dirty di initState — lihat catatan di form transaksi.
    _disposeDirtyWatch = watchFormDirty(
      <TextEditingController>[
        _amount,
        _alertTitle,
        _alertBody,
        _alertThreshold
      ],
      () => mounted ? setState(() => _dirty = true) : (),
    );
    final Budget? b = widget.existing;
    if (b != null) {
      _amount.text = ThousandsSeparatorFormatter.formatInt(b.amountMinor);
      _period = b.periodType;
      _categoryId = b.categoryId ?? _allCategories;
      _startDate = b.startDate;
      _alertEnabled = b.alertEnabled;
      _alertTitle.text = b.alertTitle ?? '';
      _alertBody.text = b.alertBody ?? '';
      if (b.alertThresholdMinor != null) {
        _alertThreshold.text =
            ThousandsSeparatorFormatter.formatInt(b.alertThresholdMinor!);
      }
    }
    _alertTitleFocus
        .addListener(() => _trackFocus(_alertTitleFocus, _alertTitle));
    _alertBodyFocus.addListener(() => _trackFocus(_alertBodyFocus, _alertBody));
    // Preview notifikasi merender teks field secara live — dengarkan
    // semua controller yang memengaruhi hasilnya (batas + ambang).
    _amount.addListener(_refreshPreview);
    _alertTitle.addListener(_refreshPreview);
    _alertBody.addListener(_refreshPreview);
    _alertThreshold.addListener(_refreshPreview);
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  void _trackFocus(FocusNode node, TextEditingController controller) {
    if (node.hasFocus) _lastAlertFocus = controller;
  }

  @override
  void dispose() {
    _disposeDirtyWatch();
    _amount.dispose();
    _alertTitle.dispose();
    _alertBody.dispose();
    _alertThreshold.dispose();
    _alertTitleFocus.dispose();
    _alertBodyFocus.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    final int amount = ThousandsSeparatorFormatter.parse(_amount.text);
    final int? categoryId = _categoryId == _allCategories ? null : _categoryId;
    // Ambang kosong/0 = NULL -> pemicu = batas budget.
    final int threshold =
        ThousandsSeparatorFormatter.parse(_alertThreshold.text);
    final int? alertThreshold = threshold > 0 ? threshold : null;
    final BudgetRepository repo = ref.read(budgetRepositoryProvider);

    final Result<dynamic> result;
    if (_isEditing) {
      result = await repo.update(
        id: widget.existing!.id,
        amountMinor: amount,
        periodType: _period,
        categoryId: categoryId,
        startDate: _startDate,
        alertEnabled: _alertEnabled,
        alertTitle: _alertTitle.text,
        alertBody: _alertBody.text,
        alertThresholdMinor: alertThreshold,
      );
    } else {
      result = await repo.create(
        amountMinor: amount,
        periodType: _period,
        categoryId: categoryId,
        startDate: _startDate,
        alertEnabled: _alertEnabled,
        alertTitle: _alertTitle.text,
        alertBody: _alertBody.text,
        alertThresholdMinor: alertThreshold,
      );
    }

    if (!mounted) return;
    switch (result) {
      case Success<dynamic>():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(_isEditing ? 'Anggaran diperbarui' : 'Anggaran dibuat'),
          ),
        );
        Navigator.of(context).pop();
      case final Failure<dynamic> failure:
        setState(() => _saving = false);
        setState(() {
          _error = failure.firstMessage;
          // Nominal <= 0 ditolak repository dengan pesan berawalan
          // 'Nominal' — hanya field itu yang perlu digoyang.
          if (failure.firstMessage.contains('Nominal')) _shakeAmount++;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.firstMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Category> categories = ref
            .watch(activeCategoriesProvider(TransactionType.expense))
            .valueOrNull ??
        const <Category>[];
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar:
          AppBar(title: Text(_isEditing ? 'Edit Anggaran' : 'Anggaran Baru')),
      body: FormPopGuard(
        isDirty: _dirty,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _capsLabel(context, 'Nominal'),
              const SizedBox(height: 6),
              ShakeWidget(
                  tick: _shakeAmount,
                  child: TextFormField(
                    key: const Key('budget_amount_field'),
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    autofocus: !_isEditing,
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
              if (_error != null && _error!.contains('Nominal')) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(Icons.error_outline,
                        size: 16, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _capsLabel(context, 'Periode'),
              const SizedBox(height: 6),
              AppDropdownField<BudgetPeriod>(
                value: _period,
                decoration: _fieldDecoration(scheme),
                items: <DropdownMenuItem<BudgetPeriod>>[
                  for (final BudgetPeriod p in BudgetPeriod.values)
                    DropdownMenuItem<BudgetPeriod>(
                        value: p, child: Text(p.label)),
                ],
                onChanged: (BudgetPeriod? v) =>
                    setState(() => _period = v ?? BudgetPeriod.monthly),
              ),
              const SizedBox(height: 12),
              _capsLabel(context, 'Kategori (opsional)'),
              const SizedBox(height: 6),
              AppDropdownField<int>(
                // Guard: kategori lama yang sudah tidak aktif belum ada di
                // daftar -> nilai sementara null agar tidak assert.
                value: categories.any((Category c) => c.id == _categoryId)
                    ? _categoryId
                    : (_categoryId == _allCategories ? _allCategories : null),
                decoration: _fieldDecoration(scheme),
                items: <DropdownMenuItem<int>>[
                  const DropdownMenuItem<int>(
                    value: _allCategories,
                    child: Text('Keseluruhan (semua kategori)'),
                  ),
                  for (final Category c in categories)
                    DropdownMenuItem<int>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (int? v) =>
                    setState(() => _categoryId = v ?? _allCategories),
              ),
              const SizedBox(height: 12),
              _capsLabel(context, 'Tanggal mulai'),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickStartDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.event_outlined,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          DateFormat('d MMMM y', 'id_ID').format(_startDate),
                        ),
                      ),
                      Icon(Icons.expand_more,
                          size: 20, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _capsLabel(context, 'Notifikasi Peringatan'),
              const SizedBox(height: 8),
              _alertSection(context, scheme, categories),
              if (_error != null && !_error!.contains('Nominal')) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('budget_save_button'),
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

  /// Label seksi gaya label-caps Stitch.
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

  // -------------------------------------------------------------------------
  // Notifikasi Peringatan (v6)
  // -------------------------------------------------------------------------

  /// Nama kategori terpilih (untuk preview template) — dari daftar
  /// kategori yang sudah ditonton di `build`.
  String _categoryNameOf(List<Category> categories) {
    if (_categoryId == _allCategories) return 'Semua kategori';
    for (final Category c in categories) {
      if (c.id == _categoryId) return c.name;
    }
    return 'Semua kategori';
  }

  Future<void> _toggleAlert(bool value) async {
    setState(() => _alertEnabled = value);
    // Minta izin notifikasi TEPAT saat toggle dinyalakan (pola sama
    // dengan pengaturan pengingat skor — izin tanpa konteks mudah
    // ditolak user). Service menelan kegagalannya sendiri (termasuk
    // request-in-progress bila toggle di-togle cepat) -> bool saja.
    if (value) {
      unawaited(
        HealthReminderService.instance.requestPermissionIfNeeded(),
      );
    }
  }

  Widget _alertSection(
    BuildContext context,
    ColorScheme scheme,
    List<Category> categories,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => _toggleAlert(!_alertEnabled),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.notifications_outlined,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Notifikasi peringatan'),
                      Text(
                        'Kirim notifikasi saat pemakaian mencapai ambang batas',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const Key('budget_alert_switch'),
                  value: _alertEnabled,
                  onChanged: _toggleAlert,
                ),
              ],
            ),
          ),
        ),
        if (_alertEnabled) ...<Widget>[
          const SizedBox(height: 12),
          _capsLabel(context, 'Ambang pemicu (Rp)'),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('budget_alert_threshold_field'),
            controller: _alertThreshold,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              ThousandsSeparatorFormatter(),
            ],
            decoration: _fieldDecoration(
              scheme,
              prefixText: 'Rp ',
              hintText: 'Sama dengan batas',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Notifikasi terkirim saat pemakaian periode mencapai nominal '
            'ini. Kosong = saat mencapai batas anggaran.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          _capsLabel(context, 'Judul notifikasi (opsional)'),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('budget_alert_title_field'),
            controller: _alertTitle,
            focusNode: _alertTitleFocus,
            decoration: _fieldDecoration(
              scheme,
              hintText: kDefaultAlertTitle,
            ),
          ),
          const SizedBox(height: 12),
          _capsLabel(context, 'Isi notifikasi (opsional)'),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('budget_alert_body_field'),
            controller: _alertBody,
            focusNode: _alertBodyFocus,
            minLines: 2,
            maxLines: 5,
            decoration: _fieldDecoration(
              scheme,
              hintText: kDefaultAlertBody,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ketuk untuk menyisipkan placeholder ke field yang sedang '
            'difokuskan:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final String p in kAlertPlaceholders)
                ActionChip(
                  label: Text(p),
                  onPressed: () => _insertPlaceholder(p),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _alertPreview(context, scheme, _categoryNameOf(categories)),
        ],
      ],
    );
  }

  void _insertPlaceholder(String placeholder) {
    final TextEditingController target = _lastAlertFocus ?? _alertBody;
    final TextSelection selection = target.value.selection;
    final String text = target.text;
    final int insertAt = selection.isValid ? selection.baseOffset : text.length;
    final int at = insertAt.clamp(0, text.length);
    target.text = text.replaceRange(at, at, placeholder);
    target.selection = TextSelection.collapsed(offset: at + placeholder.length);
  }

  /// Pratinjau notifikasi seperti yang akan terkirim — nilai pemakaian
  /// disimulasikan tepat di titik pemicu: ambang kustom bila diisi,
  /// selain itu batas anggaran.
  Widget _alertPreview(
    BuildContext context,
    ColorScheme scheme,
    String categoryName,
  ) {
    final int limit = ThousandsSeparatorFormatter.parse(_amount.text);
    final int threshold =
        ThousandsSeparatorFormatter.parse(_alertThreshold.text);
    final int trigger = threshold > 0 ? threshold : limit;
    final AlertTemplateValues values = AlertTemplateValues(
      categoryName: categoryName,
      spentMinor: trigger,
      limitMinor: limit,
    );
    return Container(
      key: const Key('budget_alert_preview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primary,
            child: Icon(Icons.account_balance_wallet_outlined,
                size: 14, color: scheme.onPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  renderAlertTitle(_alertTitle.text, values),
                  key: const Key('budget_alert_preview_title'),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  renderAlertBody(_alertBody.text, values),
                  key: const Key('budget_alert_preview_body'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Kontainer field konsisten form transaksi W6c: fill
  /// surfaceContainerHighest rounded-xl tanpa border, ring primary fokus.
  /// Label field SELALU di luar (caps label kecil di atas) — floating
  /// label di dalam field terisi menumpuk dengan isi field.
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
