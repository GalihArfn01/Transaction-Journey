import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart' show AppRadii;
import '../../core/errors/result.dart';
import '../../data/datasource/app_database.dart';
import '../../data/repository/category_repository.dart';
import '../../domain/model/enums.dart';
import '../shared/app_icons.dart';
import '../shared/widgets/animations.dart';
import '../shared/widgets/form_pop_guard.dart';
import 'providers.dart';

/// Preset warna kategori sebagai ARGB int (10 warna + tanpa warna = null).
const List<int?> kPresetCategoryColors = <int?>[
  0xFFE53935,
  0xFFFB8C00,
  0xFFFBC02D,
  0xFF43A047,
  0xFF00ACC1,
  0xFF1E88E5,
  0xFF3949AB,
  0xFF8E24AA,
  0xFFD81B60,
  0xFF546E7A,
  null,
];

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

/// Kontainer input rounded-xl surfaceContainerHighest tanpa border
/// default; ring primary saat fokus — identik dengan form anggaran &
/// transaksi berulang (supaya ketiga form terasa satu aplikasi).
InputDecoration _stitchInput(BuildContext context,
    {String? hint, String? errorText}) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hint,
    errorText: errorText,
    errorMaxLines: 2,
    filled: true,
    fillColor: scheme.surfaceContainerHighest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.error, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.error, width: 1.4),
    ),
  );
}

/// Form tambah/edit kategori — gaya Stitch. [categoryId] NULL = mode
/// tambah. Jenis (income/expense) terkunci saat edit. Restyle layout
/// saja — logika/validasi dipertahankan persis.
class CategoryFormPage extends ConsumerStatefulWidget {
  const CategoryFormPage({super.key, this.categoryId});

  final int? categoryId;

  @override
  ConsumerState<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends ConsumerState<CategoryFormPage> {
  final TextEditingController _nameController = TextEditingController();

  bool get _isEditing => widget.categoryId != null;

  TransactionType _type = TransactionType.expense;
  String _iconKey = 'category';
  int? _colorValue;

  /// Mode edit menunggu data dimuat; mode tambah langsung siap.
  bool _loadingExisting = true;
  bool _saving = false;

  /// True bila ada isian berubah -> back minta konfirmasi ([FormPopGuard]).
  bool _dirty = false;
  late final void Function() _disposeDirtyWatch;
  String? _nameError;

  /// Penanda goyangan field nama (lihat [ShakeWidget]).
  int _shakeName = 0;

  @override
  void initState() {
    super.initState();
    // Listener dirty di initState — lihat catatan di form transaksi.
    _disposeDirtyWatch = watchFormDirty(
      <TextEditingController>[_nameController],
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
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final Category? category =
        await ref.read(categoryRepositoryProvider).byId(widget.categoryId!);
    if (!mounted) return;
    if (category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategori tidak ditemukan')),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _nameController.text = category.name;
      _type = category.type;
      _iconKey = category.icon;
      _colorValue = category.colorValue;
      _loadingExisting = false;
    });
  }

  Future<void> _save() async {
    setState(() => _nameError = null);

    final CategoryRepository repo = ref.read(categoryRepositoryProvider);
    setState(() => _saving = true);

    if (_isEditing) {
      final Result<void> result = await repo.update(
        id: widget.categoryId!,
        name: _nameController.text,
        icon: _iconKey,
        colorValue: _colorValue,
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
        colorValue: _colorValue,
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
              Text(_isEditing ? 'Kategori diperbarui' : 'Kategori tersimpan'),
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
            title: Text(_isEditing ? 'Edit Kategori' : 'Tambah Kategori')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Kategori' : 'Tambah Kategori'),
      ),
      body: FormPopGuard(
        isDirty: _dirty,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              SegmentedButton<TransactionType>(
                segments: const <ButtonSegment<TransactionType>>[
                  ButtonSegment<TransactionType>(
                    value: TransactionType.income,
                    label: Text('Pemasukan'),
                    icon: Icon(Icons.south_west),
                  ),
                  ButtonSegment<TransactionType>(
                    value: TransactionType.expense,
                    label: Text('Pengeluaran'),
                    icon: Icon(Icons.north_east),
                  ),
                ],
                selected: <TransactionType>{_type},
                // Jenis IMMUTABLE setelah create — mengubahnya akan merusak
                // makna histori transaksi yang memakai kategori ini.
                onSelectionChanged: _isEditing
                    ? null
                    : (Set<TransactionType> selection) =>
                        setState(() => _type = selection.first),
              ),
              const SizedBox(height: 20),
              _fieldLabel(context, 'Nama kategori'),
              ShakeWidget(
                  tick: _shakeName,
                  child: TextFormField(
                    key: const Key('category_name_field'),
                    controller: _nameController,
                    decoration: _stitchInput(
                      context,
                      hint: 'mis. Makan & Minum',
                      errorText: _nameError,
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                    textInputAction: TextInputAction.done,
                    autofocus: !_isEditing,
                  )),
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
              const SizedBox(height: 24),
              _fieldLabel(context, 'Warna'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final int? preset in kPresetCategoryColors)
                    _ColorOption(
                      colorValue: preset,
                      selected: _colorValue == preset,
                      onTap: () => setState(() => _colorValue = preset),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                key: const Key('category_save_button'),
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

class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.colorValue,
    required this.selected,
    required this.onTap,
  });

  final int? colorValue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool noColor = colorValue == null;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: noColor
            ? Theme.of(context).colorScheme.surface
            : Color(colorValue!),
        child: noColor
            ? Icon(Icons.not_interested,
                size: 20, color: Theme.of(context).colorScheme.outline)
            : selected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
      ),
    );
  }
}
