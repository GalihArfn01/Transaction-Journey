import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';

/// AppBar gradient biru (`AppGradients.hero`) dipakai di 4 tab utama
/// (Dashboard, Transaksi, Analisis, Pengaturan) supaya H1 konsisten
/// dengan warna hero yang sama seperti kartu ringkasan utama.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradientAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
      ),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      // WAJIB `Container`, BUKAN `DecoratedBox`/`Positioned.fill` — AppBar
      // membungkus `flexibleSpace` dalam `Semantics` sebelum menaruhnya di
      // `Stack`, jadi `Positioned` di sini bukan anak langsung `Stack` dan
      // parent-data-nya diabaikan (tidak melebar sama sekali). `Container`
      // tanpa child otomatis melebar mengisi constraint yang bounded —
      // tidak bergantung pada mekanisme Positioned/ParentData sama sekali.
      flexibleSpace: Container(
        decoration: const BoxDecoration(gradient: AppGradients.hero),
      ),
      actions: actions,
    );
  }
}
