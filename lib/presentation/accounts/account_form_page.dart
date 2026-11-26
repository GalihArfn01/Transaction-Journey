import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart' show AppRadii;
import '../../core/errors/result.dart';
import '../../data/datasource/app_database.dart';
import '../../data/repository/account_repository.dart';
import '../../domain/model/enums.dart';
import '../shared/app_icons.dart';
import '../shared/widgets/animations.dart';
import '../shared/widgets/app_dropdown_field.dart';
import '../shared/widgets/form_pop_guard.dart';
import 'providers.dart';

/// Form tambah/edit rekening & dompet — gaya Stitch: label-caps
/// UPPERCASE di atas field, kontainer input surfaceContainerHighest
/// rounded-lg tanpa border default (konsisten form transaksi W6c).
///
/// [accountId] NULL = mode tambah. Jenis terkunci saat edit, saldo awal
/// hanya tersedia saat tambah (IMMUTABLE setelah create). Restyle layout
/// saja — seluruh logika/validasi dipertahankan persis.
class AccountFormPage extends ConsumerStatefulWidget {
  const AccountFormPage({super.key, this.accountId});

  final int? accountId;

  @override
  ConsumerState<AccountFormPage> createState() => _AccountFormPageState();
}

/// Label seksi kecil UPPERCASE di atas field (pola label-caps Stitch).
Widget _fieldLabel(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
    ),
  );
}

/// Kontainer input rounded-lg surfaceContainerHighest tanpa border
/// default; border primary saat fokus.
InputDecoration _stitchInput(BuildContext context,
    {String? hint, String? errorText, Widget? prefix}) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hint,
    prefix: prefix,
    errorText: errorText,
    errorMaxLines: 2,
    filled: true,
    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: AppRadii.fieldBorder,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: AppRadii.fieldBorder,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: AppRadii.fieldBorder,
      borderSide: BorderSide(color: scheme.primary, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: AppRadii.fieldBorder,
      borderSide: BorderSide(color: scheme.error, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: AppRadii.fieldBorder,
      borderSide: BorderSide(color: scheme.error, width: 1.4),
    ),
  );
}

class _AccountFormPageState extends ConsumerState<AccountFormPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _initialBalanceController =
      TextEditingController(text: '0');

  bool get _isEditing => widget.accountId != null;

  AccountType _type = AccountType.cash;
  String _iconKey = 'wallet';
  int? _existingColorValue;

  /// Mode edit menunggu data dimuat; mode tambah langsung siap.
  bool _loadingExisting = true;
  bool _saving = false;

  /// True bila ada isian berubah -> back minta konfirmasi ([FormPopGuard]).
  bool _dirty = false;
  late final void Function() _disposeDirtyWatch;
  String? _nameError;
  String? _balanceError;

  /// Penanda goyangan field (lihat [ShakeWidget]): naik saat field itu
  /// ditolak validasi.
  int _shakeName = 0;
  int _shakeBalance = 0;

  @override
  void initState() {
    super.initState();
    // Listener dirty di initState — lihat catatan di form transaksi.
    _disposeDirtyWatch = watchFormDirty(
      <TextEditingController>[_nameController, _initialBalanceController],
      () => mounted ? setState(() => _dirty = true) : (),
    );
    if (_isEditing) {
      _loadExisting();
    } else {
      _loadingExisting = false;
    }
  }

  @override
  void dispose() {
    _disposeDirtyWatch();
    _nameController.dispose();
    _initialBalanceController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final Account? account =
        await ref.read(accountRepositoryProvider).byId(widget.accountId!);
    if (!mounted) return;
    if (account == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rekening tidak ditemukan')),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _nameController.text = account.name;
      _type = account.type;
      _iconKey = account.icon;
      _existingColorValue = account.colorValue;
      _loadingExisting = false;
    });
  }

  /// Input sudah dibatasi digitsOnly; kosong dianggap 0, selain angka
  /// bulat non-negatif ditolak (null).
  int? _parseInitialBalance() {
    final String raw = _initialBalanceController.text.trim();
    if (raw.isEmpty) return 0;
    return int.tryParse(raw);
  }

  Future<void> _save() async {
    setState(() {
      _nameError = null;
      _balanceError = null;
    });

    int initialBalanceMinor = 0;
    if (!_isEditing) {
      final int? parsed = _parseInitialBalance();
      if (parsed == null || parsed < 0) {
        setState(() {
          _balanceError = 'Saldo awal harus berupa angka >= 0';
          _shakeBalance++;
        });
        return;
      }
      initialBalanceMinor = parsed;
    }

    final AccountRepository repo = ref.read(accountRepositoryProvider);
    setState(() => _saving = true);

    if (_isEditing) {
      final Result<void> result = await repo.update(
        id: widget.accountId!,
        name: _nameController.text,
        type: _type,
        icon: _iconKey,
        colorValue: _existingColorValue,
      );
      await _handleResult(
        result.isSuccess,
        result is Failure<void> ? result.firstMessage : null,
      );
    } else {
      final Result<int> result = await repo.create(
        name: _nameController.text,
        type: _type,
        icon: _iconKey,
        initialBalanceMinor: initialBalanceMinor,
      );
      await _handleResult(
        result.isSuccess,
        result is Failure<int> ? result.firstMessage : null,
      );
    }
  }

  Future<void> _handleResult(bool isSuccess, String? errorMessage) async {
    if (!mounted) return;
    if (isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_isEditing ? 'Rekening diperbarui' : 'Rekening tersimpan'),
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _nameError = errorMessage;
      _shakeName++;
    });
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingExisting) {
      return Scaffold(
        appBar: AppBar(
            title: Text(_isEditing ? 'Edit Rekening' : 'Tambah Rekening')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Rekening' : 'Tambah Rekening'),
      ),
      body: FormPopGuard(
        isDirty: _dirty,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _fieldLabel(context, 'Nama rekening'),
              ShakeWidget(
                  tick: _shakeName,
                  child: TextFormField(
                    key: const Key('account_name_field'),
                    controller: _nameController,
                    decoration: _stitchInput(
                      context,
                      hint: 'mis. BCA / GoPay / Cash',
                      errorText: _nameError,
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                    textInputAction: TextInputAction.next,
                    autofocus: !_isEditing,
                  )),
              const SizedBox(height: 20),

              // Jenis IMMUTABLE dari sisi UI — mengubahnya setelah create
              // membuat histori transaksi sulit dibaca pengguna.
              _fieldLabel(context, 'Jenis'),
              AppDropdownField<AccountType>(
                key: const Key('account_type_dropdown'),
                value: _type,
                decoration: _stitchInput(context),
                items: <DropdownMenuItem<AccountType>>[
                  for (final AccountType type in AccountType.values)
                    DropdownMenuItem<AccountType>(
                      value: type,
                      child: Text(type.label),
                    ),
                ],
                onChanged: _isEditing
                    ? null
                    : (AccountType? value) =>
                        setState(() => _type = value ?? AccountType.cash),
              ),
              if (!_isEditing) ...<Widget>[
                const SizedBox(height: 20),
                _fieldLabel(context, 'Saldo awal'),
                ShakeWidget(
                    tick: _shakeBalance,
                    child: TextFormField(
                      key: const Key('account_initial_balance_field'),
                      controller: _initialBalanceController,
                      decoration: _stitchInput(
                        context,
                        hint: '0',
                        prefix: const Text('Rp'),
                        errorText: _balanceError,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    )),
              ],
              const SizedBox(height: 24),
              _fieldLabel(context, 'Ikon'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final MapEntry<String, IconData> entry
                      in kAppIcons.entries)
                    _IconOption(
                      icon: entry.value,
                      selected: _iconKey == entry.key,
                      onTap: () => setState(() => _iconKey = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                key: const Key('account_save_button'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadii.fieldBorder,
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_isEditing ? 'Simpan Perubahan' : 'Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected ? scheme.primaryContainer : null,
        ),
        child: Icon(
          icon,
          size: 22,
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
