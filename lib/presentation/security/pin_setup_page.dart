import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/database_provider.dart';
import '../../data/repository/security_repository.dart';

/// Provider repository keamanan — satu instance bersama modul security.
final Provider<SecurityRepository> securityRepositoryProvider =
    Provider<SecurityRepository>(
  (Ref ref) => SecurityRepository(ref.watch(appDatabaseProvider)),
);

/// Halaman setup PIN dua langkah: masukkan PIN baru -> konfirmasi.
/// Sukses menyimpan via [SecurityRepository.setPin] lalu pop dengan
/// hasil `true`.
class PinSetupPage extends ConsumerStatefulWidget {
  const PinSetupPage({super.key});

  @override
  ConsumerState<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends ConsumerState<PinSetupPage> {
  static final RegExp _pinPattern = RegExp(r'^\d{4,8}$');

  final TextEditingController _pinController = TextEditingController();

  bool _isConfirmStep = false;
  String _firstPin = '';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String pin = _pinController.text.trim();

    if (!_pinPattern.hasMatch(pin)) {
      setState(() => _error = 'PIN harus 4-8 digit');
      return;
    }

    if (!_isConfirmStep) {
      // Langkah 1 lolos -> minta konfirmasi.
      setState(() {
        _firstPin = pin;
        _isConfirmStep = true;
        _error = null;
        _pinController.clear();
      });
      return;
    }

    if (pin != _firstPin) {
      setState(() => _error = 'Konfirmasi PIN tidak cocok');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref.read(securityRepositoryProvider).setPin(pin);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message?.toString() ?? 'PIN tidak valid';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat PIN')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              _isConfirmStep
                  ? 'Langkah 2 dari 2 — ulangi PIN baru Anda'
                  : 'Langkah 1 dari 2 — masukkan PIN baru',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'PIN dipakai untuk mengunci aplikasi. 4-8 digit angka.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('pin_setup_field'),
              controller: _pinController,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(
                labelText: _isConfirmStep ? 'Ulangi PIN baru' : 'PIN baru',
                errorText: _error,
                counterText: '',
              ),
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('pin_setup_save_button'),
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isConfirmStep ? 'Simpan PIN' : 'Lanjut'),
            ),
          ],
        ),
      ),
    );
  }
}
