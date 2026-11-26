import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/result.dart';
import '../../core/utils/input_formatters.dart';
import '../../data/datasource/app_database.dart';
import '../../data/repository/goal_repository.dart';
import '../shared/app_icons.dart';
import '../shared/widgets/animations.dart';
import '../shared/widgets/form_pop_guard.dart';
import 'providers.dart';

/// Form buat/edit tujuan tabungan. Nominal terkumpul TIDAK diedit di sini —
/// hanya lewat aksi setor/tarik agar jejaknya jelas.
///
/// Bila [parentId] diisi, form membuat ANAK di bawah node tsb (grouping
/// berjenjang). Pilihan Tujuan/Grup hanya muncul saat membuat baru.
class GoalFormPage extends ConsumerStatefulWidget {
  const GoalFormPage({
    super.key,
    this.existing,
    this.parentId,
    this.parentName,
  });

  final FinancialGoal? existing;
  final int? parentId;
  final String? parentName;

  @override
  ConsumerState<GoalFormPage> createState() => _GoalFormPageState();
}

class _GoalFormPageState extends ConsumerState<GoalFormPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _target = TextEditingController();
  final TextEditingController _description = TextEditingController();

  bool get _isEditing => widget.existing != null;

  DateTime? _deadline;
  String _icon = 'savings';
  int? _colorValue;
  bool _saving = false;
  String? _error;
  bool _isGroup = false;

  /// True bila pengguna sudah mengubah isian -> back akan meminta
  /// konfirmasi (lihat [FormPopGuard]).
  bool _dirty = false;

  /// Penanda goyangan field yang ditolak validasi (lihat [ShakeWidget]).
  int _shakeName = 0;
  int _shakeTarget = 0;
  late final void Function() _disposeDirtyWatch;

  static const List<String> _iconChoices = <String>[
    'savings',
    'wallet',
    'home_work',
    'commute',
    'school',
    'medical_services',
    'movie',
    'storefront',
    'trending_up',
    'more_horiz',
  ];

  static const List<int?> _colorChoices = <int?>[
    null,
    0xFF00695C,
    0xFF2E7D32,
    0xFF1E88E5,
    0xFF3949AB,
    0xFF8E24AA,
    0xFFD81B60,
    0xFFEF6C00,
    0xFFF9A825,
    0xFF757575,
  ];

  @override
  void initState() {
    super.initState();
    // Listener dirty di initState — lihat catatan di form transaksi.
    _disposeDirtyWatch = watchFormDirty(
      <TextEditingController>[_name, _target, _description],
      () => mounted ? setState(() => _dirty = true) : (),
    );
    final FinancialGoal? g = widget.existing;
    if (g != null) {
      _name.text = g.name;
      _target.text = ThousandsSeparatorFormatter.formatInt(g.targetAmountMinor);
      _description.text = g.description ?? '';
      _deadline = g.deadline;
      _icon = g.icon;
      _colorValue = g.colorValue;
      _isGroup = g.isGroup;
    }
  }

  @override
  void dispose() {
    _disposeDirtyWatch();
    _name.dispose();
    _target.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final int target = ThousandsSeparatorFormatter.parse(_target.text);
    final GoalRepository repo = ref.read(goalRepositoryProvider);

    final Result<dynamic> result;
    if (_isEditing) {
      result = await repo.update(
        id: widget.existing!.id,
        name: _name.text,
        targetAmountMinor: target,
        description: _description.text,
        deadline: _deadline,
        icon: _icon,
        colorValue: _colorValue,
      );
    } else if (widget.parentId != null) {
      result = await repo.addChild(
        parentId: widget.parentId!,
        name: _name.text,
        targetAmountMinor: target,
        isGroup: _isGroup,
        description: _description.text,
        deadline: _deadline,
        icon: _icon,
        colorValue: _colorValue,
      );
    } else {
      result = await repo.create(
        name: _name.text,
        targetAmountMinor: target,
        isGroup: _isGroup,
        description: _description.text,
        deadline: _deadline,
        icon: _icon,
        colorValue: _colorValue,
      );
    }

    if (!mounted) {
      return;
    }
    switch (result) {
      case Success<dynamic>():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? 'Tujuan diperbarui'
                : (widget.parentId != null
                    ? 'Item ditambahkan'
                    : 'Tujuan tabungan dibuat')),
          ),
        );
        Navigator.of(context).pop();
      case final Failure<dynamic> failure:
        setState(() => _saving = false);
        setState(() {
          _error = failure.firstMessage;
          // Pesan validasi repository menyebut 'target' untuk nominal;
          // selain itu field nama yang perlu digoyang.
          if (failure.firstMessage.toLowerCase().contains('target')) {
            _shakeTarget++;
          } else {
            _shakeName++;
          }
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.firstMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing
            ? 'Edit Tujuan'
            : (widget.parentName == null
                ? 'Tujuan Baru'
                : 'Item dalam ${widget.parentName}')),
      ),
      body: FormPopGuard(
        isDirty: _dirty,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (!_isEditing) ...<Widget>[
                SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                        value: false,
                        label: Text('Tujuan'),
                        icon: Icon(Icons.flag_outlined)),
                    ButtonSegment<bool>(
                        value: true,
                        label: Text('Grup'),
                        icon: Icon(Icons.folder_outlined)),
                  ],
                  selected: <bool>{_isGroup},
                  onSelectionChanged: (Set<bool> s) =>
                      setState(() => _isGroup = s.first),
                ),
                const SizedBox(height: 8),
                Text(
                  _isGroup
                      ? 'Grup = wadah. Total & targetnya otomatis dari item di dalamnya.'
                      : 'Tujuan punya target & dana sendiri.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ],
              ShakeWidget(
                  tick: _shakeName,
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nama tujuan'),
                    textInputAction: TextInputAction.next,
                  )),
              if (!_isGroup) ...<Widget>[
                const SizedBox(height: 16),
                ShakeWidget(
                    tick: _shakeTarget,
                    child: TextField(
                      controller: _target,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Nominal target',
                        prefixText: 'Rp ',
                        hintText: '0',
                        errorText:
                            _error?.contains('target') == true ? _error : null,
                      ),
                    )),
              ],
              const SizedBox(height: 16),
              _PickerTile(
                label: _deadline == null
                    ? 'Tenggat (opsional)'
                    : DateFormat('d MMMM y', 'id_ID').format(_deadline!),
                icon: Icons.event_outlined,
                onTap: _pickDeadline,
                trailing: _deadline == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _deadline = null),
                      ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Catatan (opsional)'),
              ),
              const SizedBox(height: 16),
              Text('Ikon', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String key in _iconChoices)
                    ChoiceChip(
                      label: Icon(appIconForKey(key), size: 18),
                      selected: _icon == key,
                      onSelected: (_) => setState(() => _icon = key),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Warna', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final int? c in _colorChoices)
                    GestureDetector(
                      onTap: () => setState(() => _colorValue = c),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: c == null
                            ? Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                            : Color(c),
                        child: _colorValue == c
                            ? const Icon(Icons.check, size: 16)
                            : (c == null
                                ? const Icon(Icons.not_interested, size: 14)
                                : null),
                      ),
                    ),
                ],
              ),
              if (_error != null && !_error!.contains('target')) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('goal_save_button'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
