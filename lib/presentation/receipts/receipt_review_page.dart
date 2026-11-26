import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/result.dart';
import '../../core/utils/input_formatters.dart';
import '../../data/datasource/app_database.dart';
import '../../data/repository/receipt_repository.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/receipt_parser.dart';
import '../../domain/model/transaction_input.dart';
import '../shared/widgets/app_dropdown_field.dart';
import '../transactions/providers.dart'
    show activeAccountsProvider, activeCategoriesProvider;
import 'providers.dart';

/// Halaman review hasil OCR nota. Teks OCR diterima via konstruktor —
/// kamera/ML Kit menyusul di R10 (oleh A).
///
/// Field editable hasil parser: merchant / tanggal / total / kategori /
/// rekening. Simpan -> transaksi expense source=receiptScan + attachmentPath
/// dari scan; Buang -> scan discarded.
class ReceiptReviewPage extends ConsumerStatefulWidget {
  const ReceiptReviewPage({
    super.key,
    required this.ocrText,
    this.scanId,
  });

  /// Teks mentah hasil OCR.
  final String ocrText;

  /// ID scan bila teks sudah tersimpan di DB (status pending);
  /// NULL = akan dibuatkan scan pending baru saat simpan.
  final int? scanId;

  @override
  ConsumerState<ReceiptReviewPage> createState() => _ReceiptReviewPageState();
}

class _ReceiptReviewPageState extends ConsumerState<ReceiptReviewPage> {
  final TextEditingController _merchant = TextEditingController();
  final TextEditingController _total = TextEditingController();
  late DateTime _date;
  double _confidence = 0;

  int? _accountId;
  int? _categoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ReceiptParseResult parsed = parseReceiptText(widget.ocrText);
    _merchant.text = parsed.merchant ?? '';
    _total.text = parsed.totalMinor == null
        ? ''
        : ThousandsSeparatorFormatter.formatInt(parsed.totalMinor!);
    _date = parsed.date ?? DateTime.now();
    _confidence = parsed.confidence;
  }

  @override
  void dispose() {
    _merchant.dispose();
    _total.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rekening wajib dipilih')),
      );
      return;
    }
    setState(() => _saving = true);

    final ReceiptRepository repo = ref.read(receiptRepositoryProvider);
    final int amountMinor = ThousandsSeparatorFormatter.parse(_total.text);
    final int scanId =
        widget.scanId ?? await repo.insertPending(ocrText: widget.ocrText);

    final Result<int> result = await repo.saveConfirmed(
      scanId: scanId,
      input: TransactionInput(
        type: TransactionType.expense,
        amountMinor: amountMinor,
        date: _date,
        accountId: _accountId!,
        categoryId: _categoryId,
        note: _merchant.text.trim().isEmpty
            ? null
            : 'Nota: ${_merchant.text.trim()}',
      ),
    );

    if (!mounted) return;
    switch (result) {
      case Success<int>():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nota tersimpan')),
        );
        Navigator.of(context).pop();
      case final Failure<int> failure:
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.firstMessage)));
    }
  }

  Future<void> _discard() async {
    if (widget.scanId != null) {
      await ref.read(receiptRepositoryProvider).discard(widget.scanId!);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<Account> accounts =
        ref.watch(activeAccountsProvider).valueOrNull ?? const <Account>[];
    final List<Category> categories = ref
            .watch(activeCategoriesProvider(TransactionType.expense))
            .valueOrNull ??
        const <Category>[];
    final int percent = (_confidence * 100).round();

    return Scaffold(
      appBar: AppBar(title: const Text('Review Nota')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            // Indikator confidence OCR.
            Card(
              key: const Key('receipt_confidence_card'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: LinearProgressIndicator(
                        value: _confidence.clamp(0.0, 1.0),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$percent%',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _merchant,
              decoration: const InputDecoration(labelText: 'Merchant'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Tanggal',
                  border: OutlineInputBorder(),
                ),
                child: Text(DateFormat('d MMMM y', 'id_ID').format(_date)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _total,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                ThousandsSeparatorFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Total',
                prefixText: 'Rp ',
                hintText: '0',
              ),
            ),
            const SizedBox(height: 16),
            AppDropdownField<int>(
              value: categories.any((Category c) => c.id == _categoryId)
                  ? _categoryId
                  : null,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: <DropdownMenuItem<int>>[
                for (final Category c in categories)
                  DropdownMenuItem<int>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (int? v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 16),
            AppDropdownField<int>(
              value: accounts.any((Account a) => a.id == _accountId)
                  ? _accountId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Rekening',
              ),
              items: <DropdownMenuItem<int>>[
                for (final Account a in accounts)
                  DropdownMenuItem<int>(value: a.id, child: Text(a.name)),
              ],
              onChanged: (int? v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('receipt_save_button'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Simpan'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('receipt_discard_button'),
              onPressed: _discard,
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              label: Text(
                'Buang',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
