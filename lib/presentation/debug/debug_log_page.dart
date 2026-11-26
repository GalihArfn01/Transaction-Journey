import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/debug/crash_logger.dart';
import '../shared/widgets/gradient_app_bar.dart';

/// Halaman sementara untuk melihat log error tanpa USB/adb — lihat
/// dokumentasi `CrashLogger`. HANYA dimaksudkan untuk bantu diagnosis
/// bug widget layar utama; bisa dihapus lagi kapan saja setelah bug
/// terkait selesai ditelusuri (tidak ada bagian lain aplikasi yang
/// bergantung padanya).
class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  String _content = 'Memuat...';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final String content = await CrashLogger.readAll();
    if (!mounted) return;
    setState(() {
      _content = content;
      _loading = false;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log disalin ke clipboard')),
    );
  }

  Future<void> _clear() async {
    await CrashLogger.clear();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log dibersihkan')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Log Debug',
        actions: <Widget>[
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reload,
          ),
          IconButton(
            tooltip: 'Salin semua',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _loading ? null : _copy,
          ),
          IconButton(
            tooltip: 'Bersihkan log',
            icon: const Icon(Icons.delete_outline),
            onPressed: _loading ? null : _clear,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
      ),
    );
  }
}
